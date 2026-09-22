import Foundation

public enum EnvFileError: Error, Equatable, Sendable {
    case unreadable(String)
    case invalidLine(String)
}

public enum EnvFile {
    public static func load(url: URL) throws -> [String: String] {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw EnvFileError.unreadable(url.path)
        }
        return try parse(text)
    }

    public static func parse(_ text: String) throws -> [String: String] {
        var env: [String: String] = [:]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else {
                throw EnvFileError.invalidLine(String(line))
            }
            let key = String(line[..<eq])
            let value = String(line[line.index(after: eq)...])
            guard !key.isEmpty else {
                throw EnvFileError.invalidLine(String(line))
            }
            env[key] = value
        }
        return env
    }

    public static func pairs(_ env: [String: String]) -> [String] {
        env.keys.sorted().map { key in
            "\(key)=\(env[key] ?? "")"
        }
    }
}
