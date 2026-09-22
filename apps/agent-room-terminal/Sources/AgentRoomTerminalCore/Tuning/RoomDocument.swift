import Foundation
import RoomKit
import AppPathsKit

/// Public ROOM.json snapshot. Core `RoomJSONFile.Document` is internal.
public struct RoomDocument: Codable, Equatable, Sendable {
    public var id: String
    public var slug: String
    public var tenant: String
    public var layoutId: String
    public var parentRoomID: String
    public var preset: RoomWallPreset
    public var task: String
    public var verdict: String
    public var brief: [String]
    public var toolbelt: [String]
    public var walls: RoomWallSnapshot
    public var budget: RoomBudgetSnapshot
    public var excludedTools: [String]
    public var sandboxBackend: String?

    public static func load(from roomURL: URL) throws -> RoomDocument {
        let url = roomURL.appendingPathComponent("ROOM.json")
        let fm = FileManager()
        if fm.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(RoomDocument.self, from: data)
        }
        let specURL = roomURL.appendingPathComponent(RoomPaths.specFileName)
        if fm.fileExists(atPath: specURL.path) {
            let specData = try Data(contentsOf: specURL)
            let spec = try JSONDecoder().decode(RoomSpec.self, from: specData)
            return RoomDocument(
                id: spec.roomID.uuidString,
                slug: spec.lineage.blueprintSlug ?? roomURL.lastPathComponent,
                tenant: spec.tenant,
                layoutId: spec.lineage.planID ?? "",
                parentRoomID: spec.lineage.parentRoomID?.uuidString ?? "",
                preset: .toolbelt,
                task: spec.task,
                verdict: spec.verdict,
                brief: [],
                toolbelt: [],
                walls: RoomWallSnapshot(
                    writePaths: spec.walls.filesystem.allowWrite,
                    network: spec.walls.network
                ),
                budget: spec.budget,
                excludedTools: [],
                sandboxBackend: spec.sandboxBackend.rawValue
            )
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RoomDocument.self, from: data)
    }
}

/// Walks tenant room trees without using internal `RoomPaths`.
public enum RoomFolderLocator {
    public static let tenantsName = ".tenants"
    public static let roomsName = "rooms"
    public static let childrenName = "children"
    public static let roomJSONName = "ROOM.json"

    public static func find(
        roomID: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL? {
        let home = environment["HOME"] ?? DurableAppLayout.defaultHomeDirectory.path
        if let found = RoomPaths.findRoomDirectory(roomID: roomID, tenant: nil, environment: environment, homeDirectory: home) {
            return found
        }
        let root = RoomPaths.tenantsRoot(environment: environment, homeDirectory: home)
        return try find(roomID: roomID, under: root)
    }

    public static func find(roomID: String, under root: URL) throws -> URL? {
        try walk(root).first { url in
            if url.lastPathComponent == roomID { return true }
            return (try? RoomDocument.load(from: url).id) == roomID
        }
    }

    public static func allRooms(
        tenant: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> [URL] {
        // 방 폴더 위치 규약은 RoomPaths 하나만 안다(`.tenants` 겹침 계산을 두 벌로 두지 않는다).
        let tenants = RoomPaths.tenantsRoot(environment: environment, homeDirectory: DurableAppLayout.defaultHomeDirectory.path)
        let root: URL
        if let tenant, !tenant.isEmpty {
            let slug = tenant.hasPrefix("tenant:") ? String(tenant.dropFirst(7)) : tenant
            root = tenants.appendingPathComponent(slug, isDirectory: true)
        } else {
            root = tenants
        }
        return try walk(root)
    }

    /// 스캐폴드 홈 하위 스캔을 `~/.tenants/<tenant>/rooms/` 와 `children/` 로 엄격히 한정한다.
    /// `_base-bin`, `_daemon`, `skills`, `wiki`, `Library`, 방 내부 `bin/` 등의 심링크/파일을
    /// 전수 순회하지 않아 GUI 기동 시 시스템/문서(Documents) 폴더 권한 팝업을 원천 차단한다.
    static func walk(_ root: URL) throws -> [URL] {
        let fm = FileManager()
        guard fm.fileExists(atPath: root.path) else { return [] }

        // 1. root 자체가 방인 경우 (ROOM.json 보유)
        if fm.fileExists(atPath: root.appendingPathComponent(roomJSONName).path) {
            return collectRoomAndDescendants(at: root, fm: fm)
        }

        // 2. root 자체가 rooms 폴더인 경우
        if root.lastPathComponent == roomsName {
            return collectRooms(inRoomsDir: root, fm: fm)
        }

        // 3. root 바로 아래 rooms/ 폴더가 있는 경우 (예: ~/.tenants/<slug>)
        let directRooms = root.appendingPathComponent(roomsName, isDirectory: true)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: directRooms.path, isDirectory: &isDir), isDir.boolValue {
            return collectRooms(inRoomsDir: directRooms, fm: fm)
        }

        // 4. root 가 tenantsRoot(예: ~/.tenants) 또는 테넌트 폴더 컨테이너인 경우:
        //    _ 나 . 로 시작하는 내부 디렉터리(_base-bin, _daemon 등)는 건너뛰고,
        //    각 테넌트의 rooms/ 만 선택 진입한다.
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        var rooms: [URL] = []
        for entry in entries {
            let name = entry.lastPathComponent
            if name.hasPrefix(".") || name.hasPrefix("_") {
                continue
            }
            let tenantRooms = entry.appendingPathComponent(roomsName, isDirectory: true)
            var isTenantRoomsDir: ObjCBool = false
            if fm.fileExists(atPath: tenantRooms.path, isDirectory: &isTenantRoomsDir), isTenantRoomsDir.boolValue {
                rooms.append(contentsOf: collectRooms(inRoomsDir: tenantRooms, fm: fm))
            } else if fm.fileExists(atPath: entry.appendingPathComponent(roomJSONName).path) {
                rooms.append(contentsOf: collectRoomAndDescendants(at: entry, fm: fm))
            }
        }
        return rooms
    }

    private static func collectRoomAndDescendants(at roomURL: URL, fm: FileManager) -> [URL] {
        guard TenantRoomFilterPolicy.isValidRoomDirectory(url: roomURL, fileManager: fm) else { return [] }
        var result = [roomURL]
        let childrenURL = roomURL.appendingPathComponent(childrenName, isDirectory: true)
        let childEntries: [URL]
        do {
            childEntries = try fm.contentsOfDirectory(
                at: childrenURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            childEntries = []
        }
        for childURL in childEntries {
            let childName = childURL.lastPathComponent
            if childName.hasPrefix(".") || childName.hasPrefix("_") { continue }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: childURL.path, isDirectory: &isDir), isDir.boolValue {
                result.append(contentsOf: collectRoomAndDescendants(at: childURL, fm: fm))
            }
        }
        return result
    }

    private static func collectRooms(inRoomsDir roomsURL: URL, fm: FileManager) -> [URL] {
        let layoutEntries: [URL]
        do {
            layoutEntries = try fm.contentsOfDirectory(
                at: roomsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }
        var result: [URL] = []
        for layoutURL in layoutEntries {
            let layoutName = layoutURL.lastPathComponent
            if layoutName.hasPrefix(".") || layoutName.hasPrefix("_") {
                continue
            }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: layoutURL.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            if fm.fileExists(atPath: layoutURL.appendingPathComponent(roomJSONName).path) ||
               fm.fileExists(atPath: layoutURL.appendingPathComponent("spec.json").path) {
                result.append(contentsOf: collectRoomAndDescendants(at: layoutURL, fm: fm))
                continue
            }
            let roomEntries: [URL]
            do {
                roomEntries = try fm.contentsOfDirectory(
                    at: layoutURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
            } catch {
                continue
            }
            for roomCandidate in roomEntries {
                let roomName = roomCandidate.lastPathComponent
                if roomName.hasPrefix(".") || roomName.hasPrefix("_") {
                    continue
                }
                result.append(contentsOf: collectRoomAndDescendants(at: roomCandidate, fm: fm))
            }
        }
        return result
    }
}
