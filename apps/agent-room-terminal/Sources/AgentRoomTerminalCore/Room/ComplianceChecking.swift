import Foundation
import CommandKit

public protocol ComplianceChecking: Sendable {
    func isCompliant(cli: String) throws -> Bool
}

/// `agent-tenant-isolation-manager check <cli> --json` 의 `compliant` 필드.
public struct TenantIsolationComplianceChecker: ComplianceChecking, Sendable {
    public var isolationCLIName: String
    public var environment: [String: String]

    public init(
        isolationCLIName: String = "agent-tenant-isolation-manager",
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.isolationCLIName = isolationCLIName
        self.environment = environment
    }

    public func isCompliant(cli: String) throws -> Bool {
        let pathEnv = BinaryLocator.pathValue(from: environment)
        guard let exe = BinaryLocator.find(isolationCLIName, path: pathEnv) else {
            throw RoomAssemblyError.isolationCLIMissing
        }
        let result = CommandKitSync.run(exe, ["check", cli, "--json"])
        guard result.ok else {
            throw RoomAssemblyError.complianceCheckFailed(cli: cli, stderr: result.stderr)
        }
        return try ComplianceJSON.compliant(from: result.stdout)
    }
}

enum ComplianceJSON {
    struct Verdict: Decodable {
        var compliant: Bool?
        var result: Nested?

        struct Nested: Decodable {
            var compliant: Bool?
        }
    }

    static func compliant(from stdout: String) throws -> Bool {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw RoomAssemblyError.complianceJSONInvalid
        }
        let verdict = try JSONDecoder().decode(Verdict.self, from: data)
        if let value = verdict.compliant { return value }
        if let value = verdict.result?.compliant { return value }
        throw RoomAssemblyError.complianceJSONInvalid
    }
}

enum RoomNesting {
    static func validate(parent: RoomParentRef, child: RoomAssemblySpec) throws {
        if RoomWallPreset.childExceedsParent(child: child.blueprint.preset, parent: parent.preset) {
            throw RoomAssemblyError.childPresetExceedsParent(
                child: child.blueprint.preset,
                parent: parent.preset
            )
        }
        let allowed = parent.walls.intersection(child: child.blueprint.walls)
        let exceeding = child.blueprint.walls.writePaths.filter {
            !allowed.writePaths.contains($0)
        }
        if !exceeding.isEmpty {
            throw RoomAssemblyError.childWallsExceedParent(paths: exceeding)
        }
        if NetworkWall.childExceedsParent(
            child: child.blueprint.walls.network,
            parent: parent.walls.network
        ) {
            throw RoomAssemblyError.childWallsExceedParent(paths: ["network"])
        }
    }

    static func validateBinSubset(child: Set<String>, parent: RoomParentRef) throws {
        if parent.preset == .open { return }
        let extra = child.subtracting(parent.binNames)
        if !extra.isEmpty {
            throw RoomAssemblyError.childBinExceedsParent(names: extra.sorted())
        }
    }
}
