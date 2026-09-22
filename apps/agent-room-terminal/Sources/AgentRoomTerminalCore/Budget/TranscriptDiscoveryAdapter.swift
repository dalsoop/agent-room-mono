import Foundation

/// 방 내부 전사본 바인딩 및 파일 목록을 탐색하는 어댑터.
public struct TranscriptDiscoveryAdapter: Sendable {
    public let roomURL: URL

    public init(roomURL: URL) {
        self.roomURL = roomURL
    }

    /// 방에서 수집 가능한 바인딩 목록을 산출한다.
    public func discoverBindings() throws -> [TranscriptBinding] {
        let registryBindings = try TranscriptRegistry.load(in: roomURL)
        if !registryBindings.isEmpty {
            return registryBindings
        }

        let stateDir = roomURL.appendingPathComponent("state", isDirectory: true)
        let stateBindings = scanStateDirectory(stateDir)
        if !stateBindings.isEmpty {
            return stateBindings
        }

        return fallbackDefaultBindings()
    }

    /// state/ 디렉터리 내의 세션 로그 파일을 스캔한다.
    private func scanStateDirectory(_ stateDir: URL) -> [TranscriptBinding] {
        guard FileManager.default.fileExists(atPath: stateDir.path) else { return [] }
        var result: [TranscriptBinding] = []

        let directFiles = listDirectoryEntries(stateDir)
        for name in directFiles where name.hasSuffix(".jsonl") {
            let fileURL = stateDir.appendingPathComponent(name)
            let tool = inferTool(from: name)
            result.append(TranscriptBinding(tool: tool.rawValue, path: fileURL.path))
        }

        let subdirs = [
            "transcripts",
            AgentRoomTool.claude.rawValue,
            AgentRoomTool.codex.rawValue,
            AgentRoomTool.grok.rawValue,
            AgentRoomTool.agy.rawValue
        ]
        for sub in subdirs {
            let subURL = stateDir.appendingPathComponent(sub, isDirectory: true)
            let subFiles = listJsonlFiles(in: subURL)
            for fileURL in subFiles {
                let tool = inferTool(from: sub)
                result.append(TranscriptBinding(tool: tool.rawValue, path: fileURL.path))
            }
        }
        return result
    }

    private func listDirectoryEntries(_ dir: URL) -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: dir.path)
        } catch {
            return []
        }
    }

    private func listJsonlFiles(in dir: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }
        let names = listDirectoryEntries(dir)
        return names.filter { $0.hasSuffix(".jsonl") }.sorted().map { dir.appendingPathComponent($0) }
    }

    /// 파일명이나 디렉터리 이름에서 도구를 추론한다.
    public func inferTool(from name: String) -> AgentRoomTool {
        let lower = name.lowercased()
        for tool in AgentRoomTool.allCases {
            if lower.contains(tool.rawValue) {
                return tool
            }
        }
        if lower.contains("antigravity") {
            return .agy
        }
        return .claude
    }

    /// 기본 바인딩 경로 fallback.
    private func fallbackDefaultBindings() -> [TranscriptBinding] {
        guard let defaultTool = detectRoomDefaultTool() else { return [] }
        guard let candidatePath = TranscriptLocations.defaultBinding(tool: defaultTool, roomPath: roomURL.path) else {
            return []
        }
        guard FileManager.default.fileExists(atPath: candidatePath) else { return [] }
        return [TranscriptBinding(tool: defaultTool.rawValue, path: candidatePath)]
    }

    /// spec.json 또는 ROOM.json 에서 방의 지정 도구를 판정한다.
    public func detectRoomDefaultTool() -> AgentRoomTool? {
        let specURL = roomURL.appendingPathComponent("spec.json")
        let legacyURL = roomURL.appendingPathComponent("ROOM.json")
        let target = FileManager.default.fileExists(atPath: specURL.path) ? specURL : legacyURL
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }

        do {
            let data = try Data(contentsOf: target)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            if let tools = obj["agentTools"] as? [String], let first = tools.first {
                return AgentRoomTool(rawValue: first)
            }
            if let tool = obj["agentTool"] as? String {
                return AgentRoomTool(rawValue: tool)
            }
        } catch {
            return nil
        }
        return nil
    }

    /// 단일 바인딩에서 실제 전사본 파일 목록을 산출한다.
    public static func resolveFiles(for binding: TranscriptBinding) -> [URL] {
        let url = URL(fileURLWithPath: binding.path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return []
        }
        guard isDir.boolValue else {
            return [url]
        }
        do {
            let names = try FileManager.default.contentsOfDirectory(atPath: url.path)
            return names.filter { $0.hasSuffix(".jsonl") }.sorted().map { url.appendingPathComponent($0) }
        } catch {
            return []
        }
    }
}
