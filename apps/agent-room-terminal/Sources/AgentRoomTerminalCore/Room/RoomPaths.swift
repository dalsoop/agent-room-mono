import Foundation
import StateRootKit
import RoomKit

extension RoomPaths {
    static func directory(for spec: RoomAssemblySpec) -> URL {
        if let parent = spec.parent {
            return parent.folderURL
                .appendingPathComponent("children", isDirectory: true)
                .appendingPathComponent(spec.slug, isDirectory: true)
        }
        return RoomPathResolver.resolveRoomURL(
            roomID: spec.roomID,
            tenant: spec.tenantSlug,
            environment: spec.environment,
            homeDirectory: spec.homeDirectory
        )
    }
}

enum RoomDirectoryLayout {
    static let folderNames = ["bin", "work", "state", "children", "handoff", "habits"]

    static func create(at roomURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: roomURL, withIntermediateDirectories: true)
        for name in folderNames {
            try fm.createDirectory(
                at: roomURL.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        try fm.createDirectory(
            at: roomURL.appendingPathComponent("state/notes", isDirectory: true),
            withIntermediateDirectories: true
        )
    }
}

enum RoomSlug {
    static let pattern = "^[a-z0-9]+(-[a-z0-9]+)*$"

    static func validate(_ slug: String) throws {
        guard slug.range(of: pattern, options: .regularExpression) != nil else {
            throw RoomAssemblyError.invalidSlug(slug)
        }
    }
}

public enum BinaryLocator {
    public static let posixSearchDirs = ["/bin", "/usr/bin", "/usr/local/bin"]

    public static func find(_ name: String, path: String? = nil) -> String? {
        if name.contains("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        let resolvedPath = path ?? pathValue(from: [:])
        var dirs: [String] = resolvedPath.split(separator: ":").map(String.init)
        dirs.append(contentsOf: posixSearchDirs)
        var seen = Set<String>()
        for dir in dirs where seen.insert(dir).inserted {
            let candidate = URL(fileURLWithPath: dir, isDirectory: true)
                .appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    public static func pathValue(from environment: [String: String]) -> String {
        environment["PATH"] ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
    }
}
