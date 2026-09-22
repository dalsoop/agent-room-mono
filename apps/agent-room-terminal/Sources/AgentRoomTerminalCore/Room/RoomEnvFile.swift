import Foundation
import StateRootKit

enum RoomEnvFile {
    static let keys = [
        "ROOM_ID",
        "ROOM_SESSION",
        "ROOM_TENANT",
        "ROOM_PARENT",
        "ROOM_PRESET",
        "AGENT_TENANT",
        "TENANT_ID",
        "SWIFT_APP_STATE_ROOT",
        "AGENT_WIKI_WORLD",
        "PATH",
        "HOME",
        "USER",
        "LANG",
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "CLAUDE_CONFIG_DIR",
    ]

    static let closedNetworkProxy = "http://127.0.0.1:9"

    static func renderBody(from map: [String: String]) -> String {
        let extraKeys = map.keys.filter { !keys.contains($0) }.sorted()
        let allKeys = keys + extraKeys
        return allKeys.map { key in
            "\(key)=\(map[key] ?? "")"
        }.joined(separator: "\n") + "\n"
    }

    static func write(
        spec: RoomAssemblySpec,
        roomURL: URL,
        baseBin: URL,
        proxyPort: UInt16? = nil
    ) throws {
        let values = makeValues(spec: spec, roomURL: roomURL, baseBin: baseBin, proxyPort: proxyPort)
        let body = renderBody(from: values)
        let url = roomURL.appendingPathComponent("env")
        try Data(body.utf8).write(to: url, options: .atomic)
    }

    static func proxyValue(wall: NetworkWall, proxyPort: UInt16?) -> String {
        switch wall {
        case .open:
            return ""
        case .closed:
            return closedNetworkProxy
        case .allow:
            guard let proxyPort else { return closedNetworkProxy }
            return "http://localhost:\(proxyPort)"
        }
    }

    /// 프록시 포트가 늦게 정해지면 HTTP_PROXY 세 키만 고친다.
    static func applyProxy(roomURL: URL, wall: NetworkWall, proxyPort: UInt16?) throws {
        let url = roomURL.appendingPathComponent("env")
        let proxy = proxyValue(wall: wall, proxyPort: proxyPort)
        let existing: String
        do {
            existing = try String(contentsOf: url, encoding: .utf8)
        } catch {
            existing = ""
        }
        var map: [String: String] = [:]
        for line in existing.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            guard let eq = text.firstIndex(of: "=") else { continue }
            let key = String(text[..<eq])
            map[key] = String(text[text.index(after: eq)...])
        }
        map["HTTP_PROXY"] = proxy
        map["HTTPS_PROXY"] = proxy
        map["ALL_PROXY"] = proxy
        let body = renderBody(from: map)
        try Data(body.utf8).write(to: url, options: .atomic)
    }

    static func makeValues(
        spec: RoomAssemblySpec,
        roomURL: URL,
        baseBin: URL,
        proxyPort: UInt16? = nil
    ) -> [String: String] {
        let tenant = spec.tenantID
        let proxy = proxyValue(wall: spec.blueprint.walls.network, proxyPort: proxyPort)
        var values: [String: String] = [
            "ROOM_ID": spec.roomID,
            "ROOM_SESSION": "",
            "ROOM_TENANT": tenant,
            "ROOM_PARENT": spec.parent?.roomID ?? "",
            "ROOM_PRESET": spec.blueprint.preset.rawValue,
            "AGENT_TENANT": tenant,
            "TENANT_ID": tenant,
            "SWIFT_APP_STATE_ROOT": spec.tenantPolicy.stateRoot,
            "AGENT_WIKI_WORLD": spec.tenantPolicy.wikiWorld,
            "PATH": pathValue(spec: spec, roomURL: roomURL, baseBin: baseBin),
            // HOME 은 사용자 홈(상태 루트가 아니다). 에이전트 CLI 의 자격증명·전사가 여기 있다.
            "HOME": StateRootKit.resolveHost(environment: [:]),
            "USER": spec.environment["USER"] ?? NSUserName(),
            "LANG": spec.environment["LANG"] ?? "en_US.UTF-8",
            "HTTP_PROXY": proxy,
            "HTTPS_PROXY": proxy,
            "ALL_PROXY": proxy,
            // seatbelt 는 keychain 을 막는다 — 이 디렉터리 밑 파일로 대신 인증한다
            // (AgentCredentialInjector.seed 가 방 열 때마다 keychain 값을 여기 복제한다).
            "CLAUDE_CONFIG_DIR": claudeConfigDir(spec: spec, roomURL: roomURL),
        ]
        let hooks = resolveGitHooksPath(spec: spec, roomURL: roomURL)
        applyGitHooksConfig(into: &values, hooksPath: hooks, environment: spec.environment)
        return values
    }

    // MARK: - Git Hooks Configuration

    static let gitHooksConfigKey = "core.hooksPath"
    static let gitHooksSharedDirName = "hooks-shared"
    static let gitDirPrefix = "gitdir:"
    static let gitCommonDirFileName = "commondir"
    static let gitConfigCountKey = "GIT_CONFIG_COUNT"

    static func gitHooksPath(
        workdir: String?,
        fileManager: FileManager = .default
    ) -> String? {
        guard let wd = workdir?.trimmingCharacters(in: .whitespacesAndNewlines), !wd.isEmpty else {
            return nil
        }
        let startURL = URL(fileURLWithPath: (wd as NSString).expandingTildeInPath)
        guard let commonDir = gitCommonDir(startingAt: startURL, fileManager: fileManager) else {
            return nil
        }
        let hooks = commonDir.appendingPathComponent(gitHooksSharedDirName)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: hooks.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return hooks.path
    }

    static func gitCommonDir(
        startingAt startURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        var current = startURL.standardized
        while true {
            let gitPath = current.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: gitPath.path, isDirectory: &isDir) {
                return isDir.boolValue
                    ? gitPath
                    : resolveWorktreeCommonDir(gitFile: gitPath, fileManager: fileManager)
            }
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            current = parent
        }
        return nil
    }

    private static func resolveWorktreeCommonDir(
        gitFile: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let content: String
        do {
            content = try String(contentsOf: gitFile, encoding: .utf8)
        } catch {
            return nil
        }
        let lines = content.split(separator: "\n")
        guard let gitdirLine = lines.first(where: { $0.hasPrefix(gitDirPrefix) }) else {
            return nil
        }
        let rawGitDir = gitdirLine.dropFirst(gitDirPrefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawGitDir.isEmpty else { return nil }

        let gitdirURL: URL
        if rawGitDir.hasPrefix("/") {
            gitdirURL = URL(fileURLWithPath: rawGitDir).standardized
        } else {
            gitdirURL = gitFile.deletingLastPathComponent().appendingPathComponent(rawGitDir).standardized
        }

        let commondirFile = gitdirURL.appendingPathComponent(gitCommonDirFileName)
        do {
            let commonContent = try String(contentsOf: commondirFile, encoding: .utf8)
            let trimmed = commonContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed.hasPrefix("/")
                    ? URL(fileURLWithPath: trimmed).standardized
                    : gitdirURL.appendingPathComponent(trimmed).standardized
            }
        } catch {
            _ = error
        }

        if gitdirURL.pathComponents.contains("worktrees") {
            return gitdirURL.deletingLastPathComponent().deletingLastPathComponent().standardized
        }

        return gitdirURL
    }

    static func candidateWorkdirs(spec: RoomAssemblySpec, roomURL: URL) -> [String] {
        var candidates: [String] = []
        let pwd = spec.environment["PWD"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        for raw in spec.blueprint.walls.writePaths {
            let trimmed = raw.replacingOccurrences(of: "/**", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("/") {
                candidates.append(trimmed)
            } else if !pwd.isEmpty {
                candidates.append((pwd as NSString).appendingPathComponent(trimmed))
            }
        }

        if !pwd.isEmpty {
            candidates.append(pwd)
        }

        return candidates
    }

    static func resolveGitHooksPath(
        spec: RoomAssemblySpec,
        roomURL: URL,
        fileManager: FileManager = .default
    ) -> String? {
        let candidates = candidateWorkdirs(spec: spec, roomURL: roomURL)
        for candidate in candidates {
            if let hooks = gitHooksPath(workdir: candidate, fileManager: fileManager) {
                return hooks
            }
        }
        return nil
    }

    static func applyGitHooksConfig(
        into values: inout [String: String],
        hooksPath: String?,
        environment: [String: String]
    ) {
        guard let hooksPath, !hooksPath.isEmpty else { return }

        let existingCountStr = environment[gitConfigCountKey]
        let existingCount = Int(existingCountStr ?? "") ?? 0

        for i in 0..<existingCount {
            let keyName = "GIT_CONFIG_KEY_\(i)"
            let valName = "GIT_CONFIG_VALUE_\(i)"
            if let k = environment[keyName] {
                values[keyName] = k
            }
            if let v = environment[valName] {
                values[valName] = v
            }
        }

        let newIndex = existingCount
        values["GIT_CONFIG_KEY_\(newIndex)"] = gitHooksConfigKey
        values["GIT_CONFIG_VALUE_\(newIndex)"] = hooksPath
        values[gitConfigCountKey] = String(newIndex + 1)
    }

    private static func claudeConfigDir(spec: RoomAssemblySpec, roomURL: URL) -> String {
        guard spec.blueprint.agentTools.contains(AgentRoomTool.claude.rawValue) else { return "" }
        return AgentCredentialInjector.configDirName(tool: .claude, roomURL: roomURL).path
    }

    private static func pathValue(
        spec: RoomAssemblySpec,
        roomURL: URL,
        baseBin: URL
    ) -> String {
        if spec.blueprint.preset == .open {
            return BinaryLocator.pathValue(from: spec.environment)
        }
        let bin = roomURL.appendingPathComponent("bin", isDirectory: true).path
        return "\(bin):\(baseBin.path)"
    }
}

enum RoomMarkdown {
    static let missingHabits = "습관 없음"

    static func write(spec: RoomAssemblySpec, roomURL: URL) throws {
        let body = try render(spec: spec, roomURL: roomURL)
        let url = roomURL.appendingPathComponent("ROOM.md")
        try Data(body.utf8).write(to: url, options: .atomic)
    }

    static func render(spec: RoomAssemblySpec, roomURL: URL) throws -> String {
        var lines: [String] = [
            "일: \(spec.blueprint.task)",
            "완료: \(spec.blueprint.verdict)",
            "계율:",
        ]
        if spec.blueprint.brief.isEmpty {
            lines.append("- (없음)")
        } else {
            lines.append(contentsOf: spec.blueprint.brief.map { "- \($0)" })
        }
        let tools = spec.blueprint.toolbelt.joined(separator: ", ")
        lines.append("도구: \(tools)")
        lines.append("벽: \(spec.blueprint.preset.rawValue)")
        lines.append("습관:")
        lines.append(try habitsText(at: roomURL))
        if let note = try latestHandoffNote(at: roomURL) {
            lines.append("마지막 빈병: \(note)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func habitsText(at roomURL: URL) throws -> String {
        let index = roomURL
            .appendingPathComponent("habits", isDirectory: true)
            .appendingPathComponent("INDEX.md")
        guard FileManager.default.fileExists(atPath: index.path) else {
            return missingHabits
        }
        let text = try String(contentsOf: index, encoding: .utf8)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? missingHabits : trimmed
    }

    private static func latestHandoffNote(at roomURL: URL) throws -> String? {
        let dir = roomURL.appendingPathComponent("handoff", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return nil }
        return try readLatestNote(in: dir)
    }

    private static func readLatestNote(in dir: URL) throws -> String? {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let jsons = items.filter { $0.pathExtension == "json" }
        guard !jsons.isEmpty else { return nil }
        let ranked = try jsons.map { url -> (Date, String, URL) in
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            let date = values.contentModificationDate ?? .distantPast
            return (date, url.lastPathComponent, url)
        }
        .sorted { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 > rhs.0 }
            return lhs.1 > rhs.1
        }
        guard let first = ranked.first else { return nil }
        return try noteField(in: first.2)
    }

    private static func noteField(in url: URL) throws -> String? {
        let data = try Data(contentsOf: url)
        let obj = try JSONDecoder().decode(HandoffNote.self, from: data)
        let trimmed = obj.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct HandoffNote: Decodable {
        var note: String
    }
}
