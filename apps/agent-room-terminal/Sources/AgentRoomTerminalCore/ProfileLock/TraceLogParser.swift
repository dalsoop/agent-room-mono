import Foundation

/// fs_usage, opensnoop 등 시스템 관찰 로그 파서.
public enum TraceLogParser {
    private static let writeKeywords = ["write", "wrdata", "create", "unlink", "mkdir", "rmdir", "rename", "truncate"]
    private static let readKeywords = ["open", "read", "rddata", "stat", "access", "getattr"]
    private static let networkKeywords = ["connect", "sendto", "sendmsg"]

    /// macOS fs_usage 출력 라인을 파싱하여 ExecutionFootprint로 집계한다.
    public static func parseFsUsage(
        lines: [String],
        argv: [String] = [],
        exitCode: Int = 0,
        durationMs: Int = 0,
        workingDirectory: String? = nil
    ) -> ExecutionFootprint {
        var reads = Set<String>()
        var writes = Set<String>()
        var networks = Set<String>()
        var procs = Set<String>()

        for rawLine in lines {
            parseFsUsageLine(rawLine, reads: &reads, writes: &writes, networks: &networks, procs: &procs)
        }

        return ExecutionFootprint(
            argv: argv,
            exitCode: exitCode,
            durationMs: durationMs,
            fileReads: Array(reads),
            fileWrites: Array(writes),
            networkOutbound: Array(networks),
            childProcesses: Array(procs),
            workingDirectory: workingDirectory
        )
    }

    private static let pathPrefixes = ["/", "~", "."]

    private static func isFilePathCandidate(_ token: String) -> Bool {
        pathPrefixes.contains(where: { token.hasPrefix($0) })
    }

    private static func isIgnoredLine(_ line: String, prefixes: [String]) -> Bool {
        guard !line.isEmpty else { return true }
        return prefixes.contains(where: { line.hasPrefix($0) })
    }

    private static func parseFsUsageLine(
        _ rawLine: String,
        reads: inout Set<String>,
        writes: inout Set<String>,
        networks: inout Set<String>,
        procs: inout Set<String>
    ) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isIgnoredLine(line, prefixes: ["#", "TIME"]) else { return }

        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 2 else { return }

        let callIndex = resolveCallIndex(tokens)
        guard callIndex < tokens.count else { return }
        let call = tokens[callIndex].lowercased()

        recordProcName(from: tokens, callIndex: callIndex, procs: &procs)
        recordTokens(tokens.dropFirst(callIndex + 1), call: call, reads: &reads, writes: &writes, networks: &networks)
    }

    private static func resolveCallIndex(_ tokens: [String]) -> Int {
        let first = tokens[0]
        if first.contains(":") || first.contains(".") {
            return 1
        }
        return 0
    }

    private static func recordProcName(from tokens: [String], callIndex: Int, procs: inout Set<String>) {
        guard tokens.count > callIndex + 2, let procName = tokens.last, !procName.isEmpty, !procName.hasPrefix("0.") else {
            return
        }
        procs.insert(procName)
    }

    private static func recordTokens(
        _ pathTokens: ArraySlice<String>,
        call: String,
        reads: inout Set<String>,
        writes: inout Set<String>,
        networks: inout Set<String>
    ) {
        for token in pathTokens {
            if isFilePathCandidate(token) {
                recordFilePath(token, call: call, reads: &reads, writes: &writes)
                break
            }
            recordNetworkToken(token, call: call, networks: &networks)
        }
    }

    private static func recordFilePath(
        _ token: String,
        call: String,
        reads: inout Set<String>,
        writes: inout Set<String>
    ) {
        let cleaned = cleanPath(token)
        if isWriteCall(call) {
            writes.insert(cleaned)
        } else if isReadCall(call) {
            reads.insert(cleaned)
        }
    }

    private static func recordNetworkToken(
        _ token: String,
        call: String,
        networks: inout Set<String>
    ) {
        let isCandidate = isNetworkCall(call) || token.contains(":")
        guard isCandidate else { return }
        let hasHostIndicator = token.contains(".") || token.contains(":")
        guard hasHostIndicator else { return }
        networks.insert(token)
    }

    /// opensnoop 출력 라인을 파싱하여 ExecutionFootprint로 집계한다.
    public static func parseOpensnoop(
        lines: [String],
        argv: [String] = [],
        exitCode: Int = 0,
        durationMs: Int = 0,
        workingDirectory: String? = nil
    ) -> ExecutionFootprint {
        var reads = Set<String>()
        var procs = Set<String>()

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !isIgnoredLine(line, prefixes: ["#", "UID"]) else { continue }

            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.count >= 5 else { continue }
            procs.insert(tokens[2])

            guard let path = tokens.last, isFilePathCandidate(path) else { continue }
            reads.insert(cleanPath(path))
        }

        return ExecutionFootprint(
            argv: argv,
            exitCode: exitCode,
            durationMs: durationMs,
            fileReads: Array(reads),
            fileWrites: [],
            networkOutbound: [],
            childProcesses: Array(procs),
            workingDirectory: workingDirectory
        )
    }

    private static func isWriteCall(_ call: String) -> Bool {
        writeKeywords.contains { call.contains($0) }
    }

    private static func isReadCall(_ call: String) -> Bool {
        readKeywords.contains { call.contains($0) }
    }

    private static func isNetworkCall(_ call: String) -> Bool {
        networkKeywords.contains { call.contains($0) }
    }

    private static func cleanPath(_ raw: String) -> String {
        var path = raw
        if path.hasSuffix(",") || path.hasSuffix(";") {
            path.removeLast()
        }
        return (path as NSString).standardizingPath
    }
}
