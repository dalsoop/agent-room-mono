import Foundation
import os
import SandboxKit
import StateRootKit

public struct RoomInfo: Codable, Sendable, Equatable {
    public let roomID: String
    public let path: String
    public let createdAt: Date?
    public let sizeBytes: Int64

    public init(roomID: String, path: String, createdAt: Date?, sizeBytes: Int64) {
        self.roomID = roomID
        self.path = path
        self.createdAt = createdAt
        self.sizeBytes = sizeBytes
    }
}

/// 룸 샌드박스의 생성, 원샷 실행, 단방향 승격, 소각, 원격 라우팅.
/// 원격 경로는 컴파일만 되며 공개 CLI 명령에 노출하지 않는다.
public enum RoomOps {
    public static func sandboxesRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = StateRootKit.resolveHost()
    ) -> URL {
        StateRootKit.url(
            SandboxContext.sandboxesDirectoryName,
            environment: environment,
            homeDirectory: homeDirectory
        )
    }

    private static let remoteRunnerLock = OSAllocatedUnfairLock<any RemoteRoomRunning>(initialState: SSHRemoteRoomRunner())

    public static var remoteRunner: any RemoteRoomRunning {
        get { remoteRunnerLock.withLock { $0 } }
        set { remoteRunnerLock.withLock { $0 = newValue } }
    }

    @discardableResult
    public static func routeRemote(
        host: String,
        remoteCommandLine: String,
        runner: (any RemoteRoomRunning)? = nil,
        timeout: TimeInterval? = nil
    ) throws -> RemoteRoomExecutionResult {
        let activeRunner = runner ?? remoteRunner
        return try activeRunner.runRemoteSync(
            host: host,
            remoteCommandLine: remoteCommandLine,
            timeout: timeout
        )
    }

    public static func routeRemoteAsync(
        host: String,
        remoteCommandLine: String,
        runner: (any RemoteRoomRunning)? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> RemoteRoomExecutionResult {
        let activeRunner = runner ?? remoteRunner
        return try await activeRunner.runRemote(
            host: host,
            remoteCommandLine: remoteCommandLine,
            timeout: timeout
        )
    }

    public static func listRooms(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = StateRootKit.resolveHost()
    ) throws -> [RoomInfo] {
        let root = sandboxesRoot(environment: environment, homeDirectory: homeDirectory)
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        let items = try fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.creationDateKey, .totalFileSizeKey],
            options: [.skipsHiddenFiles]
        )
        return try items.compactMap { url -> RoomInfo? in
            try roomInfo(at: url)
        }
        .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    public static func enter(
        tenant: String,
        roomName: String? = nil,
        agentID: String? = nil,
        homeDirectory: String = StateRootKit.resolveHost()
    ) throws -> SandboxContext {
        let cleanTenant = stripTenantPrefix(tenant)
        let roomID = roomName ?? "room-\(cleanTenant)-\(UUID().uuidString.prefix(8).lowercased())"
        return try SandboxContext.allocate(
            tenant: cleanTenant,
            agentID: agentID,
            roomID: roomID,
            homeDirectory: homeDirectory
        )
    }

    public static func exec(
        tenant: String,
        agentID: String? = nil,
        command: [String],
        applySeatbelt: Bool = true,
        homeDirectory: String = StateRootKit.resolveHost()
    ) throws -> SandboxExecutionResult {
        guard let first = command.first else {
            return SandboxExecutionResult(
                exitCode: 64,
                stdout: "",
                stderr: "실행할 명령어가 비어 있습니다."
            )
        }
        let rest = Array(command.dropFirst())
        return try SandboxRunner.withOneShotSandbox(
            tenant: tenant,
            agentID: agentID,
            homeDirectory: homeDirectory
        ) { context in
            try SandboxRunner.run(
                executable: first,
                arguments: rest,
                context: context,
                applySeatbelt: applySeatbelt
            )
        }
    }

    public static func promote(
        roomID: String,
        tenant: String,
        relativePaths: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = StateRootKit.resolveHost()
    ) throws -> PromotionReceipt {
        let cleanTenant = stripTenantPrefix(tenant)
        let roomDir = sandboxesRoot(environment: environment, homeDirectory: homeDirectory)
            .appendingPathComponent(roomID, isDirectory: true)
        let masterRoot = StateRootKit.url(
            "\(RoomPaths.tenantsDirectoryName)/\(cleanTenant)",
            environment: environment,
            homeDirectory: homeDirectory
        )
        let context = SandboxContext(
            roomID: roomID,
            tenantSlug: cleanTenant,
            sandboxDirectory: roomDir,
            tmpDirectory: roomDir.appendingPathComponent("tmp"),
            readOnlyMasterRoot: masterRoot
        )
        let receipt = try PromotionEngine.makeReceipt(context: context, relativePaths: relativePaths)
        try PromotionEngine.promote(context: context, receipt: receipt)
        return receipt
    }

    public static func discard(
        roomID: String,
        archive: Bool = true,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = StateRootKit.resolveHost()
    ) throws {
        let roomDir = sandboxesRoot(environment: environment, homeDirectory: homeDirectory)
            .appendingPathComponent(roomID, isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: roomDir.path) else { return }
        if archive {
            try RoomArchive.archive(roomID: roomID, homeDirectory: homeDirectory)
        } else {
            try fm.removeItem(at: roomDir)
        }
    }

    public static func listArchived(
        homeDirectory: String = StateRootKit.resolveHost()
    ) throws -> [ArchivedRoomInfo] {
        try RoomArchive.listArchived(homeDirectory: homeDirectory)
    }

    @discardableResult
    public static func pruneArchived(
        maxAgeDays: Double = 7.0,
        homeDirectory: String = StateRootKit.resolveHost()
    ) throws -> [String] {
        _ = maxAgeDays
        return try RoomArchive.pruneExpired(homeDirectory: homeDirectory)
    }

    @discardableResult
    public static func restore(
        archiveName: String,
        homeDirectory: String = StateRootKit.resolveHost()
    ) throws -> String {
        try RoomArchive.restore(archiveName: archiveName, homeDirectory: homeDirectory)
    }

    @discardableResult
    public static func prune(
        maxAgeSeconds: TimeInterval = 86400,
        archive: Bool = true,
        now: Date = Date(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = StateRootKit.resolveHost()
    ) throws -> [String] {
        let root = sandboxesRoot(environment: environment, homeDirectory: homeDirectory)
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        let items = try fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return try pruneItems(
            items,
            maxAgeSeconds: maxAgeSeconds,
            archive: archive,
            now: now,
            homeDirectory: homeDirectory
        )
    }

    private static func pruneItems(
        _ items: [URL],
        maxAgeSeconds: TimeInterval,
        archive: Bool,
        now: Date,
        homeDirectory: String
    ) throws -> [String] {
        var pruned: [String] = []
        for url in items {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modDate = values.contentModificationDate else { continue }
            guard now.timeIntervalSince(modDate) >= maxAgeSeconds else { continue }
            try discardAged(url: url, archive: archive, now: now, homeDirectory: homeDirectory)
            pruned.append(url.lastPathComponent)
        }
        return pruned
    }

    private static func discardAged(
        url: URL,
        archive: Bool,
        now: Date,
        homeDirectory: String
    ) throws {
        if archive {
            try RoomArchive.archive(
                roomID: url.lastPathComponent,
                homeDirectory: homeDirectory,
                now: now
            )
        } else {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func roomInfo(at url: URL) throws -> RoomInfo? {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        guard exists, isDir.boolValue else { return nil }
        let values = try url.resourceValues(forKeys: [.creationDateKey, .totalFileSizeKey])
        return RoomInfo(
            roomID: url.lastPathComponent,
            path: url.path,
            createdAt: values.creationDate,
            sizeBytes: Int64(values.totalFileSize ?? 0)
        )
    }

    private static func stripTenantPrefix(_ tenant: String) -> String {
        tenant.hasPrefix("tenant:") ? String(tenant.dropFirst(7)) : tenant
    }
}
