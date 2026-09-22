import Foundation

/// 캔버스용 필터 로직: 테넌트 필터링 및 비활성(dismantled/abandoned) 방 숨김 지원.
public enum RoomCanvasFilter {
    /// 방이 비활성(철거됨, 버려짐, 종결됨) 상태인지 판정.
    public static func isInactive(room: RoomSummary) -> Bool {
        // 1. 방 단계(phase) 기준: closed, exited는 비활성
        if room.status.phase == .closed || room.status.phase == .exited {
            return true
        }

        // 2. phase rawValue 또는 status 텍스트 기준
        let phaseRaw = room.status.rawValue.lowercased()
        if phaseRaw == "dismantled" || phaseRaw == "abandoned" || phaseRaw == "closed" || phaseRaw == "exited" {
            return true
        }

        // 3. 마크다운 본문 내 명시적 상태 기술 검사
        let markdown = room.roomMarkdown.lowercased()
        if markdown.contains("dismantled") || markdown.contains("abandoned") ||
            markdown.contains("상태: dismantled") || markdown.contains("상태: abandoned") ||
            markdown.contains("상태: 철거") || markdown.contains("상태: 폐기") {
            return true
        }

        // 4. 세션이 없고 종료 코드가 0이 아니거나 남아있는 경우 중 비정상 종료 상태
        if room.sessionID == nil && room.status.exitCode != nil && room.status.exitCode != 0 {
            return true
        }

        return false
    }

    /// 테넌트 이름 추출 (RoomListFilter의 정본 규칙 공유)
    public static func tenant(for room: RoomSummary) -> String {
        RoomListFilter.tenantName(for: room)
    }

    /// 테넌트 매칭 여부
    public static func matchesTenant(room: RoomSummary, tenantFilter: String) -> Bool {
        let trimmed = tenantFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty || trimmed == "all" {
            return true
        }
        let tName = tenant(for: room).lowercased()
        if tName == trimmed {
            return true
        }
        // "tenant:xxx" 혹은 "tenant-xxx" 형태 매칭 지원
        if let parent = room.parentID?.lowercased() {
            if parent == trimmed || parent == "tenant:\(trimmed)" || parent == "tenant-\(trimmed)" {
                return true
            }
        }
        return false
    }

    /// 캔버스용 노드 필터링
    /// - Parameters:
    ///   - rooms: 전체 노드 목록
    ///   - tenantFilter: 특정 테넌트 또는 "all"
    ///   - hideInactiveRooms: dismantled/abandoned 등 비활성 방 숨김 여부 (기본값 true)
    ///   - searchQuery: 검색 쿼리
    public static func filter(
        rooms: [RoomSummary],
        tenantFilter: String = "all",
        hideInactiveRooms: Bool = true,
        searchQuery: String = ""
    ) -> [RoomSummary] {
        // 타일 제외 및 표출 가능한 방 대상
        var candidates = rooms.filter { TenantRoomFilterPolicy.isDisplayableRoom(node: $0) }

        // 비활성 방 필터링 (기본값 true)
        if hideInactiveRooms {
            candidates = candidates.filter { !isInactive(room: $0) }
        }

        // 테넌트 필터링
        if tenantFilter.lowercased() != "all" {
            candidates = candidates.filter { matchesTenant(room: $0, tenantFilter: tenantFilter) }
        }

        // 검색어 필터링
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmedQuery.isEmpty {
            candidates = candidates.filter { node in
                node.title.lowercased().contains(trimmedQuery) ||
                node.id.lowercased().contains(trimmedQuery) ||
                node.roomMarkdown.lowercased().contains(trimmedQuery) ||
                (node.parentID?.lowercased().contains(trimmedQuery) ?? false) ||
                node.occupants.contains(where: { $0.handle.lowercased().contains(trimmedQuery) })
            }
        }

        return candidates
    }
}
