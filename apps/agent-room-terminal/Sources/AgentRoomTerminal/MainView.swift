import AppKit
import ClipboardActionUIKit
import NoticeBannerUIKit
import SwiftUI
import AgentRoomTerminalCore

struct MainView: View {
    @Bindable var model: AppModel
    @State private var showingStandUp = false

    var body: some View {
        content
            .frame(
                minWidth: 1080, idealWidth: 1280, maxWidth: .infinity,
                minHeight: 640, idealHeight: 720, maxHeight: .infinity
            )
    }

    private var content: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ErrorBanner(model.errorMessage, onDismiss: { model.errorMessage = nil })
                Group {
                    if model.viewMode == .canvas || model.viewMode == .perspective {
                        RoomTerminalColumnView(model: model)
                            .frame(
                                minWidth: 460,
                                idealWidth: proxy.size.width,
                                maxWidth: .infinity,
                                minHeight: 400,
                                idealHeight: max(400, proxy.size.height),
                                maxHeight: .infinity
                            )
                    } else {
                        // HSplitView 는 스스로 안 늘어난다
                        HSplitView {
                            RoomListView(model: model)
                                .frame(minWidth: 220, idealWidth: 280, maxWidth: 380)

                            RoomTerminalColumnView(model: model)
                                .frame(
                                    minWidth: 460,
                                    idealWidth: max(460, proxy.size.width - 600),
                                    maxWidth: .infinity,
                                    minHeight: 400,
                                    idealHeight: max(400, proxy.size.height),
                                    maxHeight: .infinity
                                )

                            RoomDetailView(model: model, node: model.selectedNode)
                                .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(
                    width: proxy.size.width,
                    height: max(0, proxy.size.height - (model.errorMessage != nil ? 44 : 0))
                )
            }
        }
        .task { await model.refresh() }
        .confirmationDialog(
            model.pendingActionTitle,
            isPresented: Binding(
                get: { model.pendingAction != nil },
                set: { if !$0 { model.pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(model.pendingActionTitle) {
                Task { await model.confirmPendingAction() }
            }
            Button(model.L(.menuRefresh), role: .cancel) {
                model.pendingAction = nil
            }
        }
        .sheet(isPresented: $showingStandUp) {
            RoomStandUpSheet(model: model, isPresented: $showingStandUp)
        }
    }
}

// MARK: - View Mode & Perspective Extension
extension MainView {
    /// 뷰 모드 피커 (터미널 / 캔버스 / 관점)
    @ViewBuilder
    func viewModePicker() -> some View {
        Picker("", selection: $model.viewMode) {
            Label(model.L(.canvasViewModeTerminal), systemImage: "terminal").tag(MainViewMode.terminal)
            Label(model.L(.canvasViewModeCanvas), systemImage: "square.grid.2x2").tag(MainViewMode.canvas)
            Label(model.L(.canvasViewModePerspective), systemImage: "scope").tag(MainViewMode.perspective)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("main-view-mode-picker")
    }

    /// 관점(Perspective) 뷰 렌더링: case .perspective 시 RoomPerspectiveView(model: model) 렌더링
    @ViewBuilder
    func perspectiveView() -> some View {
        switch model.viewMode {
        case .perspective:
            RoomPerspectiveView(model: model)
        default:
            EmptyView()
        }
    }
}
