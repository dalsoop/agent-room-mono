import Foundation
import RadialGraphUIKit
import TimelineGraphUIKit
import RoomKit
import AgentRoomTerminalCore

private struct RadialVisualTier {
    let tier: RadialTier
    let distance: Double
    let iconName: String
    let shape: RadialNodeShape
    let tintHex: String
    let size: Double
}

extension AppModel {
    // MARK: - Perspective / Radial Graph Mapping

    private func resolveVisualTier(for room: RoomSummary, isFocus: Bool) -> RadialVisualTier {
        guard !isFocus && room.kind != .commandRoom else {
            return RadialVisualTier(
                tier: .core,
                distance: 0.15,
                iconName: "command",
                shape: .circle,
                tintHex: "#007AFF",
                size: 38.0
            )
        }
        let hasSession = room.sessionID != nil || !room.occupants.isEmpty
        let isRunning = hasSession || room.pid != nil
        guard !isRunning else {
            return RadialVisualTier(
                tier: .near,
                distance: 0.38,
                iconName: "chair.lounge.fill",
                shape: .circle,
                tintHex: "#34C759",
                size: 34.0
            )
        }
        guard room.status.phase != .open else {
            return RadialVisualTier(
                tier: .mid,
                distance: 0.63,
                iconName: "circle.dashed",
                shape: .circle,
                tintHex: "#FF9500",
                size: 30.0
            )
        }
        return RadialVisualTier(
            tier: .outer,
            distance: 0.88,
            iconName: "lock.fill",
            shape: .roundedRectangle,
            tintHex: "#8E8E93",
            size: 28.0
        )
    }

    /// RoomSummary 노드를 4단 concentric tier (core, near, mid, outer)를 갖는 RadialNode로 매핑
    func radialNode(for room: RoomSummary, isFocus: Bool = false) -> RadialNode {
        let visual = resolveVisualTier(for: room, isFocus: isFocus)
        let badge = room.bottles.isEmpty ? nil : "\(room.bottles.count)"
        return RadialNode(
            id: room.id,
            label: RoomListFilter.displayName(for: room),
            iconSystemName: visual.iconName,
            distance: visual.distance,
            tier: visual.tier,
            shape: visual.shape,
            tintHex: visual.tintHex,
            badge: badge,
            size: visual.size
        )
    }

    /// 방 목록을 방사형 레이더 노드 목록으로 매핑 (선택/초점 노드 제외 주변 노드들)
    func radialNodes(for rooms: [RoomSummary]? = nil) -> [RadialNode] {
        let targetRooms = rooms ?? nodes
        let focus = focusRadialNode()
        return targetRooms
            .filter { $0.id != focus?.id }
            .map { radialNode(for: $0, isFocus: false) }
    }

    /// 현재 중심 관점 초점 노드 (선택된 노드 우선, 없으면 지휘실/첫번째 방)
    func focusRadialNode() -> RadialNode? {
        if let selected = selectedNode {
            return radialNode(for: selected, isFocus: true)
        }
        let fallback = nodes.first(where: { $0.kind == .commandRoom }) ?? nodes.first
        return fallback.map { radialNode(for: $0, isFocus: true) }
    }

    // MARK: - Perspective / Timeline Mapping

    private func makeTimelineSegment(room: RoomSummary, now: Date) -> TimelineSegment {
        let hasSession = room.sessionID != nil || !room.occupants.isEmpty
        let isRunning = hasSession || room.pid != nil
        let lastByte = lastByteReceived[room.id]

        let startTime: Date
        let endTime: Date
        let tintHex: String
        let segLabel: String

        if isRunning {
            startTime = now.addingTimeInterval(-1800)
            endTime = lastByte ?? now
            tintHex = "#34C759"
            segLabel = room.occupants.first?.handle ?? (room.sessionID.map { String($0.prefix(8)) } ?? "Active")
        } else if room.status.phase == .open {
            startTime = now.addingTimeInterval(-3600)
            endTime = now.addingTimeInterval(-600)
            tintHex = "#007AFF"
            segLabel = room.status.phase.rawValue
        } else {
            startTime = now.addingTimeInterval(-3600)
            endTime = now.addingTimeInterval(-2400)
            tintHex = "#8E8E93"
            segLabel = "Closed"
        }

        return TimelineSegment(
            id: "\(room.id)-seg-0",
            trackID: room.id,
            startDate: startTime,
            endDate: endTime,
            label: segLabel,
            tintHex: tintHex
        )
    }

    private func makeTimelineMarkers(room: RoomSummary, now: Date) -> [TimelineMarker] {
        var markers: [TimelineMarker] = []
        if let lastByte = lastByteReceived[room.id] {
            markers.append(TimelineMarker(
                id: "\(room.id)-marker-byte",
                trackID: room.id,
                date: lastByte,
                label: "Activity",
                tintHex: "#34C759"
            ))
        }
        guard !room.bottles.isEmpty else { return markers }
        markers.append(TimelineMarker(
            id: "\(room.id)-marker-bottle",
            trackID: room.id,
            date: now.addingTimeInterval(-900),
            label: "Bottle",
            tintHex: "#FF9500"
        ))
        return markers
    }

    /// 방 목록을 시계열 트랙 및 세그먼트, 마커로 매핑
    func timelineTracks(for rooms: [RoomSummary]? = nil) -> [TimelineTrack] {
        let targetRooms = rooms ?? nodes
        let now = Date()

        return targetRooms.map { room in
            TimelineTrack(
                id: room.id,
                title: RoomListFilter.displayName(for: room),
                segments: [makeTimelineSegment(room: room, now: now)],
                markers: makeTimelineMarkers(room: room, now: now)
            )
        }
    }

    /// 타임라인 표시 시간 범위 (기본: 최근 1시간)
    func timelineRange() -> ClosedRange<Date> {
        let now = Date()
        return now.addingTimeInterval(-3600)...now
    }
}
