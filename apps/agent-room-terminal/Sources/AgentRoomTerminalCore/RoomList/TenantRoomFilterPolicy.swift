import Foundation

/// 테넌트 루트 디렉터리 및 테넌트 식별자를 방(Room) 목록에서 배제하는 정책 모델.
/// GUI 방 목록이나 스냅샷에서 테넌트 루트(예: `tenant:gujo`, `tenant:personal`)가
/// 방으로 오인되어 노출되는 결함을 차단한다.
public enum TenantRoomFilterPolicy {
    public static let tenantPrefixColon = "tenant:"
    public static let tenantPrefixHyphen = "tenant-"
    public static let roomJSONName = "ROOM.json"
    public static let specFileName = "spec.json"

    /// 식별자가 테넌트 루트를 가리키는지 검사 (`tenant:<tenantId>` 형식).
    public static func isTenantRootIdentifier(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.hasPrefix(tenantPrefixColon)
    }

    /// 방 식별자 규약 검사: 테넌트 접두사가 없고 비어있지 않아야 함.
    public static func isValidRoomIdentifier(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !isTenantRootIdentifier(trimmed)
    }

    /// 방 slug 규약 검사 (UUID 형식 또는 소문자 영문·숫자·하이픈 규약)
    public static func isValidRoomSlug(_ slug: String) -> Bool {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !isTenantRootIdentifier(trimmed) else { return false }
        if UUID(uuidString: trimmed) != nil {
            return true
        }
        let pattern = "^[a-z0-9]+(-[a-z0-9]+)*$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    /// 해당 노드가 GUI/터미널 목록에 노출 가능한 유효한 방인지 판정.
    /// 테넌트 루트 행(`tenant:gujo` 등)이나 타일 등 비방 노드를 엄격히 배제한다.
    public static func isDisplayableRoom(node: RoomSummary) -> Bool {
        // 1. 노드 종류 검사: 터미널 호스팅 가능한 방이어야 함
        guard node.kind.hostsTerminal else { return false }
        guard node.kind != .tenant, node.kind != .appTile else { return false }

        // 2. 테넌트 루트 식별자 배제
        guard !isTenantRootIdentifier(node.id) else { return false }

        // 3. title 이 테넌트 루트 형태(예: "tenant:gujo")인 경우 배제
        guard !isTenantRootIdentifier(node.title) else { return false }

        return true
    }

    /// 디렉터리가 유효한 방 폴더인지 검사.
    /// 테넌트 루트 디렉터리(`~/.tenants/<tenant>`)나 비방 폴더를 배제한다.
    public static func isValidRoomDirectory(
        url: URL,
        fileManager: FileManager = FileManager()
    ) -> Bool {
        let name = url.lastPathComponent
        // 숨김 폴더나 내부 폴더 제외
        if name.hasPrefix(".") || name.hasPrefix("_") { return false }

        // 테넌트 접두사 폴더 제외
        if isTenantRootIdentifier(name) { return false }

        // "rooms" 또는 "children" 디렉터리 자체는 방이 아님
        if name == "rooms" || name == "children" { return false }

        // 테넌트 루트 폴더 특성: 내부에 rooms/ 폴더를 가지고 있으면서 자체 ROOM.json 이 없는 경우
        let roomsSubdir = url.appendingPathComponent("rooms", isDirectory: true)
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: roomsSubdir.path, isDirectory: &isDir), isDir.boolValue {
            return false
        }

        // 방 메타데이터 파일(ROOM.json 또는 spec.json)이 존재하는지 확인
        let roomJSON = url.appendingPathComponent(roomJSONName)
        let specJSON = url.appendingPathComponent(specFileName)
        let hasMetadata = fileManager.fileExists(atPath: roomJSON.path) ||
                          fileManager.fileExists(atPath: specJSON.path)
        guard hasMetadata else { return false }

        return true
    }

    /// 노드 목록에서 테넌트 루트 노드를 필터링하여 방만 반환
    public static func filter(nodes: [RoomSummary]) -> [RoomSummary] {
        nodes.filter { isDisplayableRoom(node: $0) }
    }

    /// 디렉터리 URL 목록에서 테넌트 루트 폴더를 필터링
    public static func filterDirectories(
        urls: [URL],
        fileManager: FileManager = FileManager()
    ) -> [URL] {
        urls.filter { isValidRoomDirectory(url: $0, fileManager: fileManager) }
    }
}
