import AgentRoomMonitorCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 한 화면 벽 표. 행=방, 열=입주·방·테넌트·도메인·도구·쓰기·네트워크. 층 쪼개기·카메라·중첩 보드는 없다.
struct FloorGridView: View {
    @Environment(AppModel.self) private var app
    let board: BoardModel

    var body: some View {
        let rows = board.floorNodes
        VStack(spacing: 0) {
            hudHeader(for: rows)
            Group {
                if rows.isEmpty {
                    emptyFloor
                } else {
                    table(for: rows)
                }
            }
        }
        .background(LinearGradient(colors: [VColor.sea0, VColor.sea1], startPoint: .top, endPoint: .bottom))
    }

    private func hudHeader(for rows: [VNode]) -> some View {
        VStack(spacing: 0) {
            FloorBuildingMacroHUD(
                totalTenants: board.world.tenants.count,
                totalRooms: rows.count,
                activeOccupants: rows.filter { $0.agentKey != nil }.count,
                riskRooms: rows.filter { IsolationRisk.writesAreHomeWide(writePaths(of: $0)) }.count
            )
            FloorBuildingHierarchyBar(board: board)
        }
    }

    private func table(for rows: [VNode]) -> some View {
        Table(rows, selection: selectionBinding) {
            whoColumn
            roomColumn
            tenantColumn
            domainColumn
            toolsColumn
            writesColumn
            netColumn
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var whoColumn: some TableColumnContent<VNode, Never> {
        TableColumn(app.L(.isolationWho)) { node in
            FloorWallCell(node: node, board: board) {
                FloorPawnView(
                    name: occupant(of: node),
                    tokens: node.tokens,
                    maxTokens: node.maxTokens,
                    isOccupied: node.agentKey != nil
                )
            }
            .accessibilityLabel(accessibilityText(for: node))
            .accessibilityAddTraits(.isButton)
        }
        .width(min: 100, ideal: 140)
    }

    private var roomColumn: some TableColumnContent<VNode, Never> {
        TableColumn(app.L(.isolationRoom)) { node in
            FloorRoomCellView(
                name: node.name,
                state: node.state,
                blueprint: node.blueprint,
                hasVault: node.attachments.contains(where: { $0.kind == "vault" })
            )
        }
        .width(min: 100, ideal: 150)
    }

    private var tenantColumn: some TableColumnContent<VNode, Never> {
        TableColumn(app.L(.isolationTenant)) { node in
            FloorTenantCellView(displayName: tenantText(of: node))
        }
        .width(min: 90, ideal: 120)
    }

    private var domainColumn: some TableColumnContent<VNode, Never> {
        TableColumn(app.L(.isolationDomain)) { node in
            Text(domainText(of: node))
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
        }
        .width(min: 140, ideal: 220)
    }

    private var toolsColumn: some TableColumnContent<VNode, Never> {
        TableColumn(app.L(.isolationTools)) { node in
            let tools = toolNames(of: node)
            Text(displayList(tools))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(IsolationRisk.manyTools(tools.count) ? VColor.gate : .primary)
                .textSelection(.enabled)
        }
        .width(min: 100, ideal: 160)
    }

    private var writesColumn: some TableColumnContent<VNode, Never> {
        TableColumn(app.L(.isolationWrites)) { node in
            let writes = writePaths(of: node)
            Text(displayList(writes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(
                    IsolationRisk.writesAreHomeWide(writes) ? VColor.bad : .primary
                )
                .textSelection(.enabled)
        }
        .width(min: 140, ideal: 240)
    }

    private var netColumn: some TableColumnContent<VNode, Never> {
        TableColumn(app.L(.isolationNet)) { node in
            Text(netText(of: node))
                .font(.system(size: 11))
                .foregroundStyle((netAllowed(of: node) ?? false) ? VColor.gate : .secondary)
        }
        .width(min: 88, ideal: 120)
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { board.selected?.id },
            set: { id in
                guard let id, let node = board.floorNodes.first(where: { $0.id == id }) else { return }
                board.select(node: node)
            }
        )
    }

    private var emptyFloor: some View {
        VStack(spacing: 10) {
            Text(app.L(.floorEmptyTitle))
                .font(.system(size: 16, weight: .semibold))
            Text(app.L(.floorEmptyBody))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(32)
    }

    private func occupant(of node: VNode) -> String {
        if let key = node.agentKey, let agent = board.world.agents[key] { return agent.name }
        return app.L(.cardEmpty)
    }

    private func tenantText(of node: VNode) -> String {
        guard let id = node.tenantID, !id.isEmpty else { return app.L(.isolationNone) }
        if let named = board.world.tenants.first(where: { $0.id == id })?.displayName, !named.isEmpty {
            return named
        }
        return id
    }

    private func domainText(of node: VNode) -> String {
        if let path = node.leaseDetail, !path.isEmpty { return path }
        return app.L(.isolationNone)
    }

    private func toolNames(of node: VNode) -> [String] {
        let attached = node.attachments.filter { $0.kind == "skill" || $0.kind == "tool" }.map(\.name)
        if !attached.isEmpty { return attached }
        return node.skills
    }

    private func writePaths(of node: VNode) -> [String] {
        node.attachments.filter { $0.kind == "write" }.map(\.name)
    }

    private func netAllowed(of node: VNode) -> Bool? {
        guard let net = node.attachments.first(where: { $0.kind == "net" }) else { return nil }
        return net.value == "1"
    }

    private func netText(of node: VNode) -> String {
        switch netAllowed(of: node) {
        case true: return app.L(.isolationNetOn)
        case false: return app.L(.isolationNetOff)
        case nil: return app.L(.isolationNone)
        }
    }

    private func displayList(_ items: [String]) -> String {
        items.isEmpty ? app.L(.isolationNone) : items.joined(separator: " · ")
    }

    /// 쓰기·네트워크를 항상 포함한다. 잘리지 않게 전체 경로를 붙인다.
    private func accessibilityText(for node: VNode) -> String {
        [
            occupant(of: node),
            node.name,
            tenantText(of: node),
            domainText(of: node),
            displayList(toolNames(of: node)),
            displayList(writePaths(of: node)),
            netText(of: node),
        ].joined(separator: ", ")
    }
}

/// 행 드롭 타깃. 표 셀에 스킬을 놓는다.
private struct FloorWallCell<Content: View>: View {
    let node: VNode
    let board: BoardModel
    @ViewBuilder var content: () -> Content
    @State private var dropTargeted = false

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .background(dropTargeted ? VColor.accent.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { board.select(node: node) }
            .modifier(SkillDragDrop(node: node, board: board, targeted: $dropTargeted))
    }
}

private struct SkillDragDrop: ViewModifier {
    let node: VNode
    let board: BoardModel
    @Binding var targeted: Bool

    func body(content: Content) -> some View {
        content
            .onDrag(if: node.kindRaw == "skill") {
                NSItemProvider(object: node.name as NSString)
            }
            .onDrop(of: [.utf8PlainText, .plainText], isTargeted: $targeted) { providers in
                guard acceptsDrop else { return false }
                guard let provider = providers.first else { return false }
                provider.loadItem(forTypeIdentifier: UTType.utf8PlainText.identifier, options: nil) { data, _ in
                    let name: String?
                    if let data = data as? Data {
                        name = String(data: data, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if let s = data as? String {
                        name = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        name = nil
                    }
                    guard let skill = name, !skill.isEmpty else { return }
                    Task { @MainActor in
                        await board.dropSkill(onto: node, skill: skill)
                    }
                }
                return true
            }
    }

    private var acceptsDrop: Bool {
        guard !node.blueprint.isEmpty else { return false }
        return node.kindRaw == "room" || node.kindRaw == "placement"
    }
}

private extension View {
    @ViewBuilder
    func onDrag(if condition: Bool, _ payload: @escaping () -> NSItemProvider) -> some View {
        if condition {
            self.onDrag(payload)
        } else {
            self
        }
    }
}
