import SwiftUI

/// 한 화면 운영면. 벽 표(입주·방·테넌트·도메인·도구·쓰기·네트워크) + 테넌트 + 방 만들기. 층 쪼개기·카메라는 없다.
struct MainView: View {
    @Bindable var model: AppModel
    @State private var board = BoardModel()
    @State private var showNewRoom = false
    @State private var showMemorySearch = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                chrome
                FloorGridView(board: board)
                    .id(board.tick)
            }
            sidePanel
        }
        .environment(model)
        .frame(minWidth: 1100, minHeight: 640)
        .preferredColorScheme(.dark)
        .background(VColor.sea1)
        .task { await board.autoRefreshLoop() }
        .sheet(isPresented: $showNewRoom) { NewRoomSheet(board: board) }
    }

    private var chrome: some View {
        HStack(spacing: 10) {
            tenantMenu
            viewpointDock
            Spacer()
            refreshButton
            Button {
                showMemorySearch.toggle()
            } label: {
                Label(app.L(.menuSearchMemory), systemImage: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(VColor.accent)
            .popover(isPresented: $showMemorySearch, arrowEdge: .bottom) {
                MemorySearchPopover(board: board, isPresented: $showMemorySearch)
                    .environment(app)
            }
            Button {
                showNewRoom = true
            } label: {
                Label(app.L(.newRoomTitle), systemImage: "plus.rectangle.on.folder")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(VColor.accent)
            .help(app.L(.newRoomHelp))
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.black.opacity(0.6))
        .overlay(alignment: .bottom) { Divider().opacity(0.4) }
    }

    private var app: AppModel { model }

    private var tenantMenu: some View {
        Menu {
            Button(app.L(.tenantAll)) { board.selectTenant(nil) }
            ForEach(board.world.tenants) { tenant in
                Button(tenant.current ? "\(tenant.displayName) · \(app.L(.tenantCurrent))" : tenant.displayName) {
                    board.selectTenant(tenant.id)
                }
            }
        } label: {
            let label = board.world.tenants.first(where: { $0.id == board.selectedTenantID })?.displayName
                ?? app.L(.tenantAll)
            Text(label).font(.system(size: 12, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var viewpointDock: some View {
        HStack(spacing: 2) {
            ForEach(BoardModel.Viewpoint.allCases, id: \.self) { vp in
                Button(app.L(vp.l10nKey)) {
                    board.viewpoint = vp
                    board.tick += 1
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: board.viewpoint == vp ? .bold : .regular))
                .foregroundStyle(board.viewpoint == vp ? VColor.accent : Color.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(board.viewpoint == vp ? VColor.accent.opacity(0.14) : .clear, in: Capsule())
            }
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await board.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.plain)
        .foregroundStyle(board.refreshing ? Color.secondary : VColor.accent)
        .disabled(board.refreshing)
        .help(app.L(.menuRefresh))
    }

    @ViewBuilder private var sidePanel: some View {
        if let selected = board.selected {
            DetailPanelView(
                node: selected,
                world: board.world,
                root: board.world.host,
                board: board,
                close: { board.selected = nil },
                enter: nil
            )
            .frame(width: 340)
            .background(Color(red: 0.043, green: 0.067, blue: 0.094))
        }
    }
}
