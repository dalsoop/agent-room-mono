import Foundation
import SecretMaskKit

/// 빈병에 실리는 전임 세션 증거. 본문은 넣지 않는다. 전사가 없으면 전부 빈 값 + `none`.
public struct HandoffSessionEvidence: Codable, Equatable, Sendable {
    public var readDocuments: [String]
    public var executedCommands: [String]
    public var producedFiles: [String]
    public var lastAssistantText: String
    public var evidenceSource: String

    public static let noneSource = "none"
    public static let transcriptSource = "transcript"

    public static let none = HandoffSessionEvidence(
        readDocuments: [],
        executedCommands: [],
        producedFiles: [],
        lastAssistantText: "",
        evidenceSource: noneSource
    )

    public init(
        readDocuments: [String] = [],
        executedCommands: [String] = [],
        producedFiles: [String] = [],
        lastAssistantText: String = "",
        evidenceSource: String = noneSource
    ) {
        self.readDocuments = readDocuments
        self.executedCommands = executedCommands
        self.producedFiles = producedFiles
        self.lastAssistantText = lastAssistantText
        self.evidenceSource = evidenceSource
    }
}

/// 방 안 Claude JSONL 만 읽는다. 홈 `~/.claude/projects` 는 열지 않는다.
public enum HandoffTranscriptMiner {
    public static let maxCommands = 20
    public static let maxCommandChars = 120
    public static let maxAssistantChars = 400

    public static func collect(roomURL: URL, tool: AgentRoomTool) -> HandoffSessionEvidence {
        let files = jsonlFiles(roomURL: roomURL, tool: tool)
        guard !files.isEmpty else { return .none }
        var parsedAny = false
        var read: [String] = []
        var seenRead = Set<String>()
        var commands: [String] = []
        var lastText = ""
        var sessionStart: Date?
        for file in files {
            guard let raw = utf8Contents(of: file) else { continue }
            for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, let value = decodeLine(trimmed) else { continue }
                parsedAny = true
                if let ts = timestamp(in: value) {
                    sessionStart = minDate(sessionStart, ts)
                }
                ingest(
                    value,
                    roomURL: roomURL,
                    read: &read,
                    seenRead: &seenRead,
                    commands: &commands,
                    lastText: &lastText
                )
            }
        }
        guard parsedAny else { return .none }
        if commands.count > maxCommands {
            commands = Array(commands.prefix(maxCommands))
        }
        return HandoffSessionEvidence(
            readDocuments: read,
            executedCommands: commands,
            producedFiles: producedFiles(in: roomURL, after: sessionStart),
            lastAssistantText: String(lastText.prefix(maxAssistantChars)),
            evidenceSource: HandoffSessionEvidence.transcriptSource
        )
    }

    static func jsonlFiles(roomURL: URL, tool: AgentRoomTool) -> [URL] {
        var paths: [String] = []
        if let binding = TranscriptLocations.defaultBinding(
            tool: tool,
            roomPath: roomURL.path
        ), isInsideRoom(binding, roomURL: roomURL) {
            paths.append(binding)
        }
        let registered: [TranscriptBinding]
        do {
            registered = try TranscriptRegistry.load(in: roomURL)
        } catch {
            registered = []
        }
        for item in registered where isInsideRoom(item.path, roomURL: roomURL) {
            paths.append(item.path)
        }
        var seen = Set<String>()
        var files: [URL] = []
        for path in paths {
            let binding = TranscriptBinding(tool: tool.rawValue, path: path)
            for url in TranscriptUsageSource.transcriptFiles(for: binding) {
                let key = url.standardizedFileURL.path
                if seen.insert(key).inserted {
                    files.append(url)
                }
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    static func sanitizeCommand(_ raw: String) -> String {
        let first = raw.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        ).first.map(String.init) ?? raw
        let redacted = SecretMask.command(first)
        if redacted.count <= maxCommandChars { return redacted }
        return String(redacted.prefix(maxCommandChars))
    }

    static func redactSecrets(_ command: String) -> String {
        SecretMask.command(command)
    }

    static func roomRelative(_ path: String, roomURL: URL) -> String {
        let room = roomURL.standardizedFileURL.path
        let file = URL(fileURLWithPath: path).standardizedFileURL.path
        if file == room { return "." }
        let prefix = room.hasSuffix("/") ? room : room + "/"
        if file.hasPrefix(prefix) {
            return String(file.dropFirst(prefix.count))
        }
        return path
    }
}

extension HandoffTranscriptMiner {
    static func ingest(
        _ value: JSONValue,
        roomURL: URL,
        read: inout [String],
        seenRead: inout Set<String>,
        commands: inout [String],
        lastText: inout String
    ) {
        for block in contentBlocks(in: value) {
            guard let object = block.object else { continue }
            let type = object["type"]?.string
            if type == "tool_use" {
                ingestToolUse(object, roomURL: roomURL, read: &read, seenRead: &seenRead, commands: &commands)
            }
        }
        if isAssistant(value), let text = assistantText(in: value), !text.isEmpty {
            lastText = text
        }
    }

    static func ingestToolUse(
        _ object: [String: JSONValue],
        roomURL: URL,
        read: inout [String],
        seenRead: inout Set<String>,
        commands: inout [String]
    ) {
        let name = object["name"]?.string
        let input = object["input"]?.object
        if name == "Read", let path = input?["file_path"]?.string, !path.isEmpty {
            let relative = roomRelative(path, roomURL: roomURL)
            if seenRead.insert(relative).inserted {
                read.append(relative)
            }
        }
        if name == "Bash", let command = input?["command"]?.string, !command.isEmpty {
            commands.append(sanitizeCommand(command))
        }
    }

    static func contentBlocks(in value: JSONValue) -> [JSONValue] {
        let message = value.object?["message"] ?? value
        if let array = message.object?["content"]?.array { return array }
        if let array = value.object?["content"]?.array { return array }
        return []
    }

    static func isAssistant(_ value: JSONValue) -> Bool {
        let type = value.object?["type"]?.string
        let role = value.object?["message"]?.object?["role"]?.string
        return type == "assistant" || role == "assistant"
    }

    static func assistantText(in value: JSONValue) -> String? {
        let message = value.object?["message"] ?? value
        if let text = message.object?["content"]?.string, !text.isEmpty {
            return text
        }
        var parts: [String] = []
        for block in contentBlocks(in: value) {
            guard block.object?["type"]?.string == "text" else { continue }
            if let text = block.object?["text"]?.string, !text.isEmpty {
                parts.append(text)
            }
        }
        if parts.isEmpty { return nil }
        return parts.joined(separator: "\n")
    }

    static func timestamp(in value: JSONValue) -> Date? {
        guard let raw = value.object?["timestamp"]?.string else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: raw)
    }

    static func producedFiles(in roomURL: URL, after start: Date?) -> [String] {
        guard let start else { return [] }
        let work = roomURL.appendingPathComponent("work", isDirectory: true)
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: work.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return [] }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = fm.enumerator(
            at: work,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [String] = []
        for case let url as URL in enumerator {
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: keys)
            } catch {
                continue
            }
            guard let isFile = values.isRegularFile, isFile else { continue }
            guard let mtime = values.contentModificationDate, mtime >= start else { continue }
            files.append(roomRelative(url.path, roomURL: roomURL))
        }
        return files.sorted()
    }

    static func decodeLine(_ line: String) -> JSONValue? {
        do {
            return try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
        } catch {
            return nil
        }
    }

    static func utf8Contents(of url: URL) -> String? {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return nil
        }
    }

    static func isInsideRoom(_ path: String, roomURL: URL) -> Bool {
        let room = roomURL.standardizedFileURL.path
        let file = URL(fileURLWithPath: path).standardizedFileURL.path
        if file == room { return true }
        let prefix = room.hasSuffix("/") ? room : room + "/"
        return file.hasPrefix(prefix)
    }

    static func minDate(_ current: Date?, _ next: Date) -> Date {
        guard let current else { return next }
        return min(current, next)
    }
}
