import Foundation

public enum RoomListFilterMode: String, Sendable, CaseIterable, Equatable {
    case active
    case all
}

/// Core 방 목록 필터 및 테넌트 그룹화 순수 로직.
public enum RoomListFilter {
    /// 기본 필터: 진행 중(occupied, executing 등 세션이 있거나 실행 중인 방)
    /// 전체 필터: 폐기·완료·차단·계획 포함 모든 방
    public static func filter(
        nodes: [RoomSummary],
        mode: RoomListFilterMode = .active,
        query: String = ""
    ) -> [RoomSummary] {
        let rooms = nodes.filter { TenantRoomFilterPolicy.isDisplayableRoom(node: $0) }
        let filteredByMode: [RoomSummary] = switch mode {
        case .active:
            rooms.filter { node in
                node.status.phase == .open || node.status.phase == .occupied
            }
        case .all:
            rooms
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
        guard !trimmed.isEmpty else { return filteredByMode }

        return filteredByMode.filter { node in
            node.title.precomposedStringWithCanonicalMapping.lowercased().contains(trimmed) ||
            node.id.precomposedStringWithCanonicalMapping.lowercased().contains(trimmed) ||
            node.roomMarkdown.precomposedStringWithCanonicalMapping.lowercased().contains(trimmed) ||
            (node.parentID?.precomposedStringWithCanonicalMapping.lowercased().contains(trimmed) ?? false)
        }
    }

    /// 테넌트별 방 목록 그룹화 (정렬된 순서)
    public static func groupByTenant(nodes: [RoomSummary]) -> [(tenant: String, rooms: [RoomSummary])] {
        var groups: [String: [RoomSummary]] = [:]
        for node in nodes {
            let tenant = tenantName(for: node)
            groups[tenant, default: []].append(node)
        }
        return groups.keys.sorted().map { tenant in
            (tenant: tenant, rooms: groups[tenant] ?? [])
        }
    }

    public static func tenantName(for node: RoomSummary) -> String {
        let tenantID = node.tenantID.precomposedStringWithCanonicalMapping
        if !tenantID.isEmpty && tenantID != "default" && tenantID != "system" {
            return tenantID.hasPrefix("tenant:") ? String(tenantID.dropFirst(7)) : tenantID
        }
        if let parentTenant = extractParentTenant(parentID: node.parentID) {
            return parentTenant
        }
        let nodeID = node.id.precomposedStringWithCanonicalMapping
        guard !isSystemRoom(kind: node.kind, nodeID: nodeID, tenantID: tenantID) else {
            return "system"
        }
        return resolveFallbackTenant(node: node, nodeID: nodeID) ?? resolveDiskTenant(nodeID: nodeID) ?? "default"
    }

    private static func resolveFallbackTenant(node: RoomSummary, nodeID: String) -> String? {
        if let path = node.path, let tenant = extractTenant(fromPath: path) {
            return tenant
        }
        if let tenant = extractTenant(fromPath: nodeID) {
            return tenant
        }
        return extractTenant(fromMarkdown: node.roomMarkdown)
    }

    private static func resolveDiskTenant(nodeID: String) -> String? {
        do {
            if let found = try RoomFolderLocator.find(roomID: nodeID),
               let tenant = extractTenant(fromPath: found.path) {
                return tenant
            }
        } catch {
            _ = error
        }
        return nil
    }

    private static func isSystemRoom(kind: RoomKind, nodeID: String, tenantID: String) -> Bool {
        if kind == .commandRoom { return true }
        if tenantID == "system" { return true }
        return TenantRoomFilterPolicy.isTenantRootIdentifier(nodeID)
    }

    private static func extractParentTenant(parentID: String?) -> String? {
        guard let raw = parentID?.precomposedStringWithCanonicalMapping else { return nil }
        guard raw.hasPrefix("tenant:") || raw.hasPrefix("tenant-") else { return nil }
        let clean = String(raw.dropFirst(7))
        guard !clean.isEmpty, clean != "default", clean != "system" else { return nil }
        return clean
    }

    /// 파일 경로 문자열(.tenants/<slug>/rooms/... 등)에서 유효한 테넌트 slug 추출
    public static func extractTenant(fromPath path: String) -> String? {
        guard !path.isEmpty else { return nil }
        let normalized = path.precomposedStringWithCanonicalMapping

        if let tenant = parseTenantsMarker(normalized) {
            return tenant
        }
        return parseRoomsParent(normalized)
    }

    private static func parseTenantsMarker(_ path: String) -> String? {
        let markers = [".tenants/", "/tenants/"]
        for marker in markers {
            guard let range = path.range(of: marker) else { continue }
            let remainder = path[range.upperBound...]
            guard let first = remainder.split(separator: "/").first else { continue }
            let slug = String(first).trimmingCharacters(in: .whitespacesAndNewlines)
            if isValidTenantSlug(slug) {
                return slug
            }
        }
        guard path.hasPrefix("tenants/") else { return nil }
        let remainder = path.dropFirst(8)
        guard let first = remainder.split(separator: "/").first else { return nil }
        let slug = String(first).trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidTenantSlug(slug) ? slug : nil
    }

    private static func parseRoomsParent(_ path: String) -> String? {
        guard let roomsRange = path.range(of: "/rooms/") else { return nil }
        let prefix = path[..<roomsRange.lowerBound]
        guard let last = prefix.split(separator: "/").last else { return nil }
        let slug = String(last).trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidTenantSlug(slug) ? slug : nil
    }

    /// ROOM.md 마크다운 본문(테넌트: slug 또는 경로 포함 라인)에서 테넌트 slug 추출
    public static func extractTenant(fromMarkdown markdown: String) -> String? {
        guard !markdown.isEmpty else { return nil }
        let normalized = markdown.precomposedStringWithCanonicalMapping
        for line in normalized.split(separator: "\n") {
            if let tenant = parseMarkdownLine(String(line)) {
                return tenant
            }
        }
        return nil
    }

    private static func parsePrefixTenant(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("테넌트:") || lower.hasPrefix("tenant:") else { return nil }
        let dropCount = lower.hasPrefix("테넌트:") ? 4 : 7
        let rest = trimmed.dropFirst(dropCount).trimmingCharacters(in: .whitespaces)
        let candidate = rest.hasPrefix("tenant:") ? String(rest.dropFirst(7)) : rest
        return isValidTenantSlug(candidate) ? candidate : nil
    }

    private static func parseMarkdownLine(_ line: String) -> String? {
        if let prefixMatch = parsePrefixTenant(line) {
            return prefixMatch
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("/.tenants/") || trimmed.contains("/rooms/") else { return nil }
        return extractTenant(fromPath: trimmed)
    }

    /// 테넌트 식별자가 유효한지(시스템 예약어 및 폴더 배제) 검증
    public static func isValidTenantSlug(_ slug: String) -> Bool {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !trimmed.isEmpty else { return false }
        guard trimmed != "default" && trimmed != "system" else { return false }
        guard !trimmed.hasPrefix("_") && !trimmed.hasPrefix(".") else { return false }
        return true
    }

    /// 방 이름: 작업 한 문장의 앞 30자 (없으면 title)
    public static func displayName(for node: RoomSummary) -> String {
        if let taskLine = taskFirstSentence(from: node.roomMarkdown), !taskLine.isEmpty {
            return String(taskLine.precomposedStringWithCanonicalMapping.prefix(30))
        }
        return String(node.title.precomposedStringWithCanonicalMapping.prefix(30))
    }

    private static let taskPrefixes = ["일:", "작업:", "task:"]

    private static func taskFirstSentence(from markdown: String) -> String? {
        guard !markdown.isEmpty else { return nil }
        let normalized = markdown.precomposedStringWithCanonicalMapping
        for line in normalized.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let matchedPrefix = taskPrefixes.first(where: { trimmed.hasPrefix($0) }) else { continue }
            let rest = trimmed.dropFirst(matchedPrefix.count).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { return rest }
        }
        return nil
    }
}
