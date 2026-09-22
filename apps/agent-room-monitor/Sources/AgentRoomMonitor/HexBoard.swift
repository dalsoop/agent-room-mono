import AppKit
import SwiftUI

// ═══════════════════════════════════════════════════════════════
// 7타일 꽃 보드 (사용자 설계 v3):
//   모든 타일 = 같은 크기 육각. 내용물은 타일 안에서 개수만큼 작아져 채워진다(100+ 수납).
//   방 = 꽃 7타일: 가운데 = 방 문(에이전트 1), 둘레 6 = 주제 슬롯.
//   릴레이: 하위 슬롯 선택 → 방들이 1→2→3 순서로 옆으로 붙는 체인 뷰.
// ═══════════════════════════════════════════════════════════════

enum HexMath {
    static let tileRadius: CGFloat = 46          // 통일 타일 크기
    static let slabHeight: CGFloat = 10

    static func corners(center: CGPoint, radius: CGFloat) -> [CGPoint] {
        (0 ..< 6).map { i in
            let angle = CGFloat.pi / 180 * (60 * CGFloat(i) - 90)
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
    }

    static func hexPath(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        let pts = corners(center: center, radius: radius)
        path.move(to: pts[0])
        for pt in pts.dropFirst() { path.addLine(to: pt) }
        path.closeSubpath()
        return path
    }

    static func spiral(_ index: Int) -> (q: Int, r: Int) {
        guard index > 0 else { return (0, 0) }
        var ring = 1
        var count = 1
        while count + ring * 6 <= index {
            count += ring * 6
            ring += 1
        }
        var offset = index - count
        var q = 0, r = -ring
        let directions = [(1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1)]
        for direction in directions {
            let steps = min(offset, ring)
            q += direction.0 * steps
            r += direction.1 * steps
            offset -= steps
            guard offset > 0 else { break }
        }
        return (q, r)
    }

    static func axialPixel(q: Int, r: Int, pitch: CGFloat) -> CGPoint {
        CGPoint(x: pitch * (sqrt(3) * CGFloat(q) + sqrt(3) / 2 * CGFloat(r)),
                y: pitch * 1.5 * CGFloat(r))
    }

    static func rings(for count: Int) -> Int {
        guard count > 1 else { return 0 }
        return Int(ceil((sqrt(12.0 * Double(count) - 3) - 3) / 6))
    }
}

// MARK: - 슬롯 (둘레 6타일의 주제) — 데이터 테이블, 하드코딩 분기 금지

struct PetalItem {
    var color: Color
    var isDim: Bool = false
}

enum PetalTheme: Int, CaseIterable {
    case children = 0, skills, equipment, lease, decisions, problems

    var glyph: String {
        switch self {
        case .children: return "▣"
        case .skills: return "S"
        case .equipment: return "E"
        case .lease: return "A"
        case .decisions: return "D"
        case .problems: return "!"
        }
    }

    /// pointy-top 이웃은 변 방향(0°+60k) — 꼭짓점 방향이면 면이 안 붙는다(실측 수정).
    /// NE부터 시계방향: ▣NE · S E · E SE · A SW · D W · ! NW.
    var angle: CGFloat {
        CGFloat.pi / 180 * (CGFloat(rawValue) * 60 - 60)
    }

    func items(of node: VNode) -> [PetalItem] {
        switch self {
        case .children:
            return node.children.map { PetalItem(color: $0.state.roofColor) }
        case .skills:
            /* 호출 실측 반영 — 부른 스킬은 초록, 한 번도 안 부른 스킬은 흐림(부재의 가시화) */
            return node.attachments.filter { $0.kind == "skill" }
                .map { PetalItem(color: $0.isCalled ? VColor.exec : Color(red: 0.45, green: 0.5, blue: 0.57), isDim: !$0.isCalled) }
        case .equipment:
            return node.attachments.filter { $0.kind != "skill" }
                .map { _ in PetalItem(color: Color(red: 0.5, green: 0.56, blue: 0.66)) }
        case .lease:
            return node.leaseName == nil ? [] : [PetalItem(color: VColor.accent)]
        case .decisions:
            return node.decisions.map { PetalItem(color: $0.done ? VColor.exec : VColor.gate) }
        case .problems:
            return node.healthBlocked > 0
                ? Array(repeating: PetalItem(color: VColor.bad), count: node.healthBlocked)
                : []
        }
    }
}

/// 꽃 하나 = 노드 하나 (가운데 문 + 둘레 6슬롯).
struct Flower: Identifiable {
    let id: String
    let node: VNode
    var center: CGPoint
    var order: Int?   // 체인 뷰의 순서 번호
    var dimmed: Bool = false

    static var footprint: CGFloat { HexMath.tileRadius * 2.74 }   // 중심~바깥 슬롯 끝
}

// MARK: - 배치

@MainActor
enum FlowerLayout {
    struct Board {
        var flowers: [Flower]
        var clusterLabels: [(name: String, center: CGPoint, count: Int)]
        var threads: [[CGPoint]]   // 실 꿰매기 — 같은 그룹 멤버를 잇는 선
        var bounds: CGRect
        var chainTitle: String?
    }

    static func build(
        host: VNode,
        chainFocus: VNode?,
        groupKey: ((VNode) -> String)?,
        insideRoom: Bool,
        isDimmed: (VNode) -> Bool
    ) -> Board {
        guard let focus = chainFocus else {
            return overview(host: host, groupKey: groupKey, insideRoom: insideRoom, isDimmed: isDimmed)
        }
        return chain(focus: focus, isDimmed: isDimmed)
    }

    /// 방 안에서는 자식을 한 명도 빼지 않는다. 구역 지도의 최상위만 zone 컨테이너를 펼친다.
    private static func clusters(
        host: VNode,
        groupKey: ((VNode) -> String)?,
        insideRoom: Bool
    ) -> [(name: String, icon: String, members: [VNode])] {
        if insideRoom || host.children.allSatisfy({ $0.kindRaw != "zone" || $0.children.isEmpty }) {
            return host.children.isEmpty ? [] : [(host.name, host.icon, host.children)]
        }
        let allMembers = host.children.flatMap { group -> [VNode] in
            (group.kindRaw == "zone" && !group.children.isEmpty) ? group.children : [group]
        }
        guard let groupKey else {
            return host.children.compactMap { group in
                let members = (group.kindRaw == "zone" && !group.children.isEmpty) ? group.children : [group]
                return members.isEmpty ? nil : (group.name, group.icon, members)
            }
        }
        let grouped = Dictionary(grouping: allMembers) { groupKey($0) }
        return grouped.keys.sorted().map { key in (key, "🧵", grouped[key] ?? []) }
    }

    private static func overview(
        host: VNode,
        groupKey: ((VNode) -> String)?,
        insideRoom: Bool,
        isDimmed: (VNode) -> Bool
    ) -> Board {
        var flowers: [Flower] = []
        var labels: [(String, CGPoint, Int)] = []
        var threads: [[CGPoint]] = []
        // BOARD-PAN-PACK-MARKER — 격자로 모아 빈 바다 스크롤을 없앤다.
        let pitch = Flower.footprint * 2 + 6
        struct Packed { var name: String; var icon: String; var members: [VNode]; var extent: CGFloat }
        let packed: [Packed] = clusters(host: host, groupKey: groupKey, insideRoom: insideRoom).compactMap { group in
            guard !group.members.isEmpty else { return nil }
            let rings = CGFloat(HexMath.rings(for: group.members.count))
            return Packed(name: group.name, icon: group.icon, members: group.members,
                          extent: rings * pitch + Flower.footprint)
        }
        let cols = max(1, Int(ceil(sqrt(Double(packed.count)))))
        let rows = max(1, (packed.count + cols - 1) / cols)
        var colW = Array(repeating: CGFloat(0), count: cols)
        var rowH = Array(repeating: CGFloat(0), count: rows)
        for (i, item) in packed.enumerated() {
            colW[i % cols] = max(colW[i % cols], item.extent * 2 + 28)
            rowH[i / cols] = max(rowH[i / cols], item.extent * 2 + 56)
        }
        var colMid = Array(repeating: CGFloat(0), count: cols)
        var rowMid = Array(repeating: CGFloat(0), count: rows)
        var acc: CGFloat = 0
        for c in 0 ..< cols { colMid[c] = acc + colW[c] / 2; acc += colW[c] }
        acc = 0
        for r in 0 ..< rows { rowMid[r] = acc + rowH[r] / 2; acc += rowH[r] }
        for (i, item) in packed.enumerated() {
            let members = item.members
            let extent = item.extent
            let clusterCenter = CGPoint(x: colMid[i % cols], y: rowMid[i / cols])

            var threadPoints: [CGPoint] = []
            for (j, member) in members.enumerated() {
                let (q, r) = HexMath.spiral(j)
                let offset = HexMath.axialPixel(q: q, r: r, pitch: pitch)
                let center = CGPoint(x: clusterCenter.x + offset.x, y: clusterCenter.y + offset.y)
                flowers.append(Flower(id: member.id, node: member, center: center, dimmed: isDimmed(member)))
                threadPoints.append(center)
            }
            if threadPoints.count > 1 { threads.append(threadPoints) }
            labels.append(("\(item.icon) \(item.name)",
                           CGPoint(x: clusterCenter.x, y: clusterCenter.y - extent - 28), members.count))
        }
        return Board(flowers: flowers, clusterLabels: labels, threads: threads,
                     bounds: bounds(of: flowers), chainTitle: nil)
    }

    /// 릴레이 — 하위가 1→2→3 순서로 가로로 붙는다.
    private static func chain(focus: VNode, isDimmed: (VNode) -> Bool) -> Board {
        let members = focus.children
        let step = Flower.footprint * 2 + 12
        let flowers = members.enumerated().map { i, node in
            Flower(id: node.id, node: node, center: CGPoint(x: CGFloat(i) * step, y: 0), order: i + 1, dimmed: isDimmed(node))
        }
        return Board(flowers: flowers, clusterLabels: [], threads: [],
                     bounds: bounds(of: flowers),
                     chainTitle: "\(focus.icon) \(focus.name)")
    }

    private static func bounds(of flowers: [Flower]) -> CGRect {
        guard let first = flowers.first else { return CGRect(x: 0, y: 0, width: 400, height: 300) }
        var rect = CGRect(origin: first.center, size: .zero)
        for flower in flowers {
            let f = Flower.footprint + 16
            rect = rect.union(CGRect(x: flower.center.x - f, y: flower.center.y - f, width: f * 2, height: f * 2))
        }
        return rect.insetBy(dx: -36, dy: -48)
    }
}

// MARK: - 뷰

struct HexBoardView: View {
    @Environment(AppModel.self) private var app
    let board: BoardModel
    @State private var hoverID: String?
    @State private var magnifyBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panOrigin: CGSize?
    @State private var didPan = false
    @State private var lastFitKey = ""

    var body: some View {
        let keyClosure: ((VNode) -> String)? = board.groupLens == .zone ? nil : { board.groupKey(of: $0) }
        let layout = FlowerLayout.build(
            host: board.effectiveRoot,
            chainFocus: board.chainFocus,
            groupKey: keyClosure,
            insideRoom: !board.roomPath.isEmpty,
            isDimmed: { !board.isVisible($0) }
        )
        let z = board.zoom
        let fitKey = "\(board.currentSpecID)|\(board.roomPath.map(\.id).joined())|\(board.chainFocus?.id ?? "")"
        GeometryReader { geo in
            canvas(layout, zoom: z)
                .frame(width: layout.bounds.width * z, height: layout.bounds.height * z)
                .offset(pan)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in board.setZoom(magnifyBase * value.magnification) }
                        .onEnded { _ in magnifyBase = board.zoom }
                )
            .onAppear { fitIfNeeded(key: fitKey, layout: layout, viewport: geo.size) }
            .onChange(of: fitKey) { _, newKey in
                pan = .zero
                lastFitKey = ""
                fitIfNeeded(key: newKey, layout: layout, viewport: geo.size)
            }
            .overlay {
                BoardWheelCatcher { event, view in
                    applyWheel(event, in: view, viewport: geo.size)
                }
            }
        }
        .clipped()
        .overlay(alignment: .topLeading) { chainHeader(layout) }
    }

    // BOARD-PAN-PACK-MARKER
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if panOrigin == nil { panOrigin = pan }
                let origin = panOrigin ?? .zero
                pan = CGSize(width: origin.width + value.translation.width,
                             height: origin.height + value.translation.height)
                didPan = true
            }
            .onEnded { _ in
                panOrigin = nil
                DispatchQueue.main.async { didPan = false }
            }
    }

    private func fitIfNeeded(key: String, layout: FlowerLayout.Board, viewport: CGSize) {
        guard key != lastFitKey else { return }
        lastFitKey = key
        board.fitToViewport(content: layout.bounds.size, viewport: viewport)
        magnifyBase = board.zoom
    }

    // BOARD-WHEEL-ZOOM-MARKER — 휠·매직마우스 전부 줌. 이동은 드래그.
    private func applyWheel(_ event: NSEvent, in view: NSView, viewport: CGSize) {
        let loc = view.convert(event.locationInWindow, from: nil)
        let raw = event.scrollingDeltaY
        let steps: CGFloat = event.hasPreciseScrollingDeltas
            ? max(-2.5, min(2.5, raw / 6))
            : (raw == 0 ? 0 : (raw > 0 ? 1 : -1))
        guard abs(steps) > 0.02 else { return }
        let old = board.zoom
        board.setZoom(old * pow(1.18, steps))
        magnifyBase = board.zoom
        let ratio = board.zoom / max(old, 0.001)
        guard abs(ratio - 1) > 0.0001 else { return }
        let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let swiftY = viewport.height - loc.y
        let vecX = loc.x - center.x - pan.width
        let vecY = swiftY - center.y - pan.height
        pan.width += vecX * (1 - ratio)
        pan.height += vecY * (1 - ratio)
    }

    @ViewBuilder private func chainHeader(_ layout: FlowerLayout.Board) -> some View {
        if let title = layout.chainTitle {
            HStack(spacing: 8) {
                Button {
                    board.chainFocus = nil
                } label: {
                    Label(app.L(.breadcrumbAll), systemImage: "chevron.left")
                }
                .buttonStyle(.plain).foregroundStyle(VColor.accent)
                Text(String(format: app.L(.chainRelay), title, layout.flowers.count))
                    .font(.system(size: 12, weight: .bold))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.black.opacity(0.65), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.15)))
            .padding(12)
        }
    }

    private func canvas(_ layout: FlowerLayout.Board, zoom: CGFloat) -> some View {
        let origin = CGPoint(x: -layout.bounds.minX, y: -layout.bounds.minY)
        return Canvas { ctx, size in
            ctx.scaleBy(x: zoom, y: zoom)
            drawThreads(layout, origin: origin, in: ctx)
            drawClusterLabels(layout, origin: origin, in: ctx)
            drawChainConnectors(layout, origin: origin, in: ctx)
            for flower in layout.flowers.sorted(by: { $0.center.y < $1.center.y }) {
                draw(flower: flower, origin: origin, in: ctx)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(panGesture)
        .onTapGesture(count: 2) { location in
            guard !didPan else { return }
            handleDoubleTap(at: CGPoint(x: location.x / zoom, y: location.y / zoom), layout: layout, origin: origin)
        }
        .onTapGesture { location in
            guard !didPan else { return }
            handleTap(at: CGPoint(x: location.x / zoom, y: location.y / zoom), layout: layout, origin: origin)
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let scaled = CGPoint(x: location.x / zoom, y: location.y / zoom)
                hoverID = flowerHit(at: scaled, layout: layout, origin: origin)?.flower.id
            case .ended:
                hoverID = nil
            }
        }
    }

    // MARK: 꽃 그리기

    private func draw(flower: Flower, origin: CGPoint, in ctx: GraphicsContext) {
        var ctx = ctx
        if flower.dimmed { ctx.opacity = 0.38 }
        let base = CGPoint(x: flower.center.x + origin.x, y: flower.center.y + origin.y)
        let node = flower.node
        let R = HexMath.tileRadius
        let petalDist = R * sqrt(3)

        // 둘레 슬롯 6 — 빈 슬롯도 흐리게 자리를 지킨다(고정 주제 위치 = 관리 일관성)
        for theme in PetalTheme.allCases {
            let center = CGPoint(x: base.x + petalDist * cos(theme.angle),
                                 y: base.y + petalDist * sin(theme.angle))
            drawPetal(theme: theme, items: theme.items(of: node), at: center, in: ctx)
        }

        // 가운데 = 방 문
        drawTilePrism(at: base, fill: doorColor(node), stroke: hoverID == flower.id ? VColor.accent : nil, in: ctx)
        drawMascot(for: node, at: CGPoint(x: base.x, y: base.y - 6), in: ctx)
        drawAgentRing(node: node, at: CGPoint(x: base.x + R * 0.42, y: base.y + R * 0.34), in: ctx)
        drawDoorName(node, at: CGPoint(x: base.x, y: base.y + R * 0.55), in: ctx)

        if let order = flower.order {
            drawOrderBadge(order, at: CGPoint(x: base.x - R * 0.62, y: base.y - R * 0.62), in: ctx)
        }
        if hoverID == flower.id {
            drawNameChip(node, at: CGPoint(x: base.x, y: base.y - Flower.footprint - 4), in: ctx)
        }
    }

    private func doorColor(_ node: VNode) -> Color {
        switch node.state {
        case .exec: return VColor.exec.opacity(0.85)
        case .block: return VColor.bad.opacity(0.85)
        case .gate: return VColor.gate.opacity(0.85)
        case .sleep: return Color(red: 0.32, green: 0.36, blue: 0.48)
        case .queue: return Color(red: 0.55, green: 0.5, blue: 0.42)
        default: return Color(red: 0.42, green: 0.48, blue: 0.55)
        }
    }

    /// 슬롯 타일 — 내용물 미니 헥스가 개수에 맞춰 작아지며 안을 채운다 (100+ 수납).
    private func drawPetal(theme: PetalTheme, items: [PetalItem], at center: CGPoint, in ctx: GraphicsContext) {
        let R = HexMath.tileRadius
        let empty = items.isEmpty
        drawTilePrism(at: center,
                      fill: Color(red: 0.24, green: 0.29, blue: 0.35).opacity(empty ? 0.35 : 1),
                      stroke: nil, in: ctx, flat: empty)

        // 주제 글리프 (좌상 모서리)
        let glyph = ctx.resolve(
            Text(theme.glyph)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 0.62, green: 0.7, blue: 0.78).opacity(empty ? 0.4 : 1))
        )
        ctx.draw(glyph, at: CGPoint(x: center.x - R * 0.5, y: center.y - R * 0.62), anchor: .center)
        guard !empty else { return }

        // 내용물 — 나선 채움, 반지름은 개수에서 역산
        let rings = HexMath.rings(for: items.count)
        let mini = (R * 0.78) / (CGFloat(rings) * 2 + 1)
        let pitch = mini * 1.12
        for (i, item) in items.enumerated() {
            let (q, r) = HexMath.spiral(i)
            let offset = HexMath.axialPixel(q: q, r: r, pitch: pitch)
            let hex = HexMath.hexPath(center: CGPoint(x: center.x + offset.x, y: center.y + offset.y),
                                      radius: mini * 0.92)
            ctx.fill(hex, with: .color(item.color.opacity(item.isDim ? 0.4 : 0.92)))
        }

        // 개수 배지
        let count = ctx.resolve(
            Text("\(items.count)").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Color(red: 0.85, green: 0.9, blue: 0.94))
        )
        ctx.draw(count, at: CGPoint(x: center.x + R * 0.5, y: center.y - R * 0.62), anchor: .center)
    }

    private func drawTilePrism(at center: CGPoint, fill: Color, stroke: Color?, in ctx: GraphicsContext, flat: Bool = false) {
        let R = HexMath.tileRadius
        if !flat {
            let corners = HexMath.corners(center: center, radius: R)
            for i in 1 ... 3 {
                var side = Path()
                side.move(to: corners[i])
                side.addLine(to: corners[i + 1])
                side.addLine(to: CGPoint(x: corners[i + 1].x, y: corners[i + 1].y + HexMath.slabHeight))
                side.addLine(to: CGPoint(x: corners[i].x, y: corners[i].y + HexMath.slabHeight))
                side.closeSubpath()
                ctx.fill(side, with: .color(fill.opacity(i == 2 ? 0.45 : 0.6)))
            }
        }
        let top = HexMath.hexPath(center: center, radius: R)
        ctx.fill(top, with: .color(fill))
        ctx.stroke(top, with: .color(.black.opacity(0.35)), lineWidth: 1)
        if let stroke {
            ctx.stroke(top, with: .color(stroke), lineWidth: 2)
        }
    }

    private func drawMascot(for node: VNode, at point: CGPoint, in ctx: GraphicsContext) {
        if let ns = Mascots.image(board.world.iconOf[node.id]) {
            ctx.draw(Image(nsImage: ns), in: CGRect(x: point.x - 13, y: point.y - 14, width: 26, height: 26))
            return
        }
        ctx.draw(ctx.resolve(Text(node.icon).font(.system(size: 15))), at: point, anchor: .center)
    }

    private func drawAgentRing(node: VNode, at point: CGPoint, in ctx: GraphicsContext) {
        guard let key = node.agentKey, let agent = board.world.agents[key] else { return }
        let ratio = node.maxTokens > 0 ? Double(node.tokens) / Double(node.maxTokens) : 0
        ctx.stroke(Path(ellipseIn: CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)),
                   with: .color(.white.opacity(0.25)), lineWidth: 2.4)
        var arc = Path()
        arc.addArc(center: point, radius: 8, startAngle: .degrees(-90),
                   endAngle: .degrees(-90 + 360 * min(1, ratio)), clockwise: false)
        ctx.stroke(arc, with: .color(ratio > 0.9 ? VColor.bad : VColor.exec),
                   style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        ctx.draw(ctx.resolve(Text(String(agent.tool.prefix(1)).uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.white)),
                 at: point, anchor: .center)
    }

    private func drawDoorName(_ node: VNode, at point: CGPoint, in ctx: GraphicsContext) {
        let name = node.name.count > 9 ? String(node.name.prefix(8)) + "…" : node.name
        ctx.draw(ctx.resolve(Text(name).font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(Color(red: 0.9, green: 0.93, blue: 0.96))),
                 at: point, anchor: .center)
    }

    private func drawOrderBadge(_ order: Int, at point: CGPoint, in ctx: GraphicsContext) {
        let rect = CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
        ctx.fill(Path(ellipseIn: rect), with: .color(VColor.accent))
        ctx.draw(ctx.resolve(Text("\(order)").font(.system(size: 10, weight: .bold)).foregroundStyle(.black)),
                 at: point, anchor: .center)
    }

    private func drawNameChip(_ node: VNode, at point: CGPoint, in ctx: GraphicsContext) {
        var parts = [node.name]
        if let lease = node.leaseName { parts.append("📂\(lease)") }
        let resolved = ctx.resolve(Text(parts.joined(separator: " · "))
            .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(VColor.accent))
        let size = resolved.measure(in: CGSize(width: 420, height: 30))
        let chip = CGRect(x: point.x - size.width / 2 - 7, y: point.y - size.height / 2 - 3,
                          width: size.width + 14, height: size.height + 6)
        ctx.fill(Path(roundedRect: chip, cornerRadius: 5), with: .color(.black.opacity(0.8)))
        ctx.draw(resolved, at: point, anchor: .center)
    }

    private func drawClusterLabels(_ layout: FlowerLayout.Board, origin: CGPoint, in ctx: GraphicsContext) {
        for label in layout.clusterLabels {
            let at = CGPoint(x: label.center.x + origin.x, y: label.center.y + origin.y)
            let resolved = ctx.resolve(Text("\(label.name) · \(label.count)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(red: 0.87, green: 0.91, blue: 0.94)))
            let size = resolved.measure(in: CGSize(width: 500, height: 40))
            let chip = CGRect(x: at.x - size.width / 2 - 9, y: at.y - size.height / 2 - 4,
                              width: size.width + 18, height: size.height + 8)
            ctx.fill(Path(roundedRect: chip, cornerRadius: 6), with: .color(.black.opacity(0.6)))
            ctx.draw(resolved, at: at, anchor: .center)
        }
    }

    /// 실 꿰매기 — 같은 그룹의 꽃들을 잇는 은은한 실선.
    private func drawThreads(_ layout: FlowerLayout.Board, origin: CGPoint, in ctx: GraphicsContext) {
        for points in layout.threads where points.count > 1 {
            var path = Path()
            path.move(to: CGPoint(x: points[0].x + origin.x, y: points[0].y + origin.y))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x + origin.x, y: point.y + origin.y))
            }
            ctx.stroke(path, with: .color(VColor.accent.opacity(0.22)),
                       style: StrokeStyle(lineWidth: 1.4, dash: [6, 5]))
        }
    }

    private func drawChainConnectors(_ layout: FlowerLayout.Board, origin: CGPoint, in ctx: GraphicsContext) {
        guard layout.chainTitle != nil, layout.flowers.count > 1 else { return }
        let sorted = layout.flowers.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            let p0 = CGPoint(x: a.center.x + origin.x + Flower.footprint, y: a.center.y + origin.y)
            let p1 = CGPoint(x: b.center.x + origin.x - Flower.footprint, y: b.center.y + origin.y)
            var line = Path()
            line.move(to: p0)
            line.addLine(to: p1)
            ctx.stroke(line, with: .color(VColor.accent.opacity(0.7)), lineWidth: 2)
            var head = Path()
            head.move(to: p1)
            head.addLine(to: CGPoint(x: p1.x - 9, y: p1.y - 5))
            head.addLine(to: CGPoint(x: p1.x - 9, y: p1.y + 5))
            head.closeSubpath()
            ctx.fill(head, with: .color(VColor.accent.opacity(0.8)))
        }
    }

    // MARK: 히트테스트

    private struct Hit {
        var flower: Flower
        var petal: PetalTheme?
    }

    private func flowerHit(at location: CGPoint, layout: FlowerLayout.Board, origin: CGPoint) -> Hit? {
        let R = HexMath.tileRadius
        let petalDist = R * sqrt(3)
        for flower in layout.flowers {
            let base = CGPoint(x: flower.center.x + origin.x, y: flower.center.y + origin.y)
            if hypot(location.x - base.x, location.y - base.y) <= R { return Hit(flower: flower, petal: nil) }
            for theme in PetalTheme.allCases {
                let c = CGPoint(x: base.x + petalDist * cos(theme.angle), y: base.y + petalDist * sin(theme.angle))
                if hypot(location.x - c.x, location.y - c.y) <= R { return Hit(flower: flower, petal: theme) }
            }
        }
        return nil
    }

    /// 문·내부 슬롯 클릭 = 자식이 있으면 그 방으로 들어간다. 자식은 한 명도 빼지 않고 꽃으로 깐다.
    private func handleDoubleTap(at location: CGPoint, layout: FlowerLayout.Board, origin: CGPoint) {
        guard let hit = flowerHit(at: location, layout: layout, origin: origin) else { return }
        enterOrSelect(hit.flower.node, petal: hit.petal)
    }

    private func handleTap(at location: CGPoint, layout: FlowerLayout.Board, origin: CGPoint) {
        guard let hit = flowerHit(at: location, layout: layout, origin: origin) else { return }
        enterOrSelect(hit.flower.node, petal: hit.petal)
    }

    private func enterOrSelect(_ node: VNode, petal: PetalTheme?) {
        let goInside = (petal == nil || petal == .children) && !node.children.isEmpty
        if goInside {
            board.enterRoom(node)
            return
        }
        board.select(node: node)
    }
}

/// 클릭은 통과시키고 휠만 가로챈다.
private struct BoardWheelCatcher: NSViewRepresentable {
    var onWheel: (NSEvent, NSView) -> Void

    func makeNSView(context: Context) -> Catcher {
        Catcher(onWheel: onWheel)
    }

    func updateNSView(_ nsView: Catcher, context: Context) {
        nsView.onWheel = onWheel
    }

    final class Catcher: NSView {
        var onWheel: (NSEvent, NSView) -> Void
        private var monitor: Any?

        init(onWheel: @escaping (NSEvent, NSView) -> Void) {
            self.onWheel = onWheel
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { stop() } else { start() }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let loc = self.convert(event.locationInWindow, from: nil)
                if !self.bounds.isEmpty, !self.bounds.contains(loc) { return event }
                self.onWheel(event, self)
                return nil
            }
        }

        private func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
