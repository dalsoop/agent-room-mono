import Foundation
import StateRootKit

public enum BaseBinFolder {
    public static let posixNames = [
        "ls", "cat", "head", "tail", "sed", "grep", "find", "wc", "git",
    ]
    public static let selfCLIName = "agent-room-terminal"
    public static let forbiddenNames = ["python3", "sh", "bash", "env", "osa" + "script"]
    public static let expectedCount = posixNames.count + 1

    @discardableResult
    public static func ensure() throws -> URL {
        try ensure(
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: StateRootKit.resolveHost(),
            selfCLIPath: nil
        )
    }

    @discardableResult
    public static func ensure(
        environment: [String: String],
        homeDirectory: String,
        selfCLIPath: String?
    ) throws -> URL {
        let dir = RoomPaths.baseBin(environment: environment, homeDirectory: homeDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pathEnv = BinaryLocator.pathValue(from: environment)
        try linkPosixTools(into: dir, path: pathEnv)
        try linkSelfCLI(into: dir, path: pathEnv, selfCLIPath: selfCLIPath)
        try removeForbidden(from: dir)
        return dir
    }

    private static func linkPosixTools(into dir: URL, path: String) throws {
        for name in posixNames {
            guard let dest = BinaryLocator.find(name, path: path) else {
                throw RoomAssemblyError.posixToolMissing(name)
            }
            try replaceSymlink(
                at: dir.appendingPathComponent(name),
                destination: dest
            )
        }
    }

    private static func linkSelfCLI(into dir: URL, path: String, selfCLIPath: String?) throws {
        let dest: String
        if let given = selfCLIPath, FileManager.default.isExecutableFile(atPath: given) {
            dest = given
        } else if let found = BinaryLocator.find(selfCLIName, path: path) {
            dest = found
        } else {
            throw RoomAssemblyError.selfCLIMissing
        }
        try replaceSymlink(
            at: dir.appendingPathComponent(selfCLIName),
            destination: dest
        )
    }

    private static func removeForbidden(from dir: URL) throws {
        let fm = FileManager.default
        for name in forbiddenNames {
            let url = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        }
    }
}

enum RoomSymlink {
    /// 링크를 새로 건다. 끊어진(dangling) 링크도 지운다 — `fileExists` 는 링크 대상을
    /// 따라가므로 끊어진 링크에 false 를 돌려주고, 그러면 create 가 "이미 있음" 으로
    /// 죽는다(실측 2026-09-04: 상대경로 `.build/debug/...` 자기 링크가 남아 open 전부 실패).
    /// 대상은 항상 절대경로로 건다.
    static func replaceSymlink(at url: URL, destination: String) throws {
        let fm = FileManager.default
        if linkOrFileExists(at: url.path, fm: fm) {
            try fm.removeItem(at: url)
        }
        let absolute = destination.hasPrefix("/")
            ? destination
            : (fm.currentDirectoryPath as NSString).appendingPathComponent(destination)
        try fm.createSymbolicLink(
            atPath: url.path,
            withDestinationPath: (absolute as NSString).standardizingPath
        )
    }

    /// 대상 유무와 무관하게 "그 경로에 무엇이든 있는가" — lstat 기준.
    static func linkOrFileExists(at path: String, fm: FileManager) -> Bool {
        if fm.fileExists(atPath: path) { return true }
        do {
            _ = try fm.destinationOfSymbolicLink(atPath: path)
            return true
        } catch {
            return false
        }
    }
}

func replaceSymlink(at url: URL, destination: String) throws {
    try RoomSymlink.replaceSymlink(at: url, destination: destination)
}
