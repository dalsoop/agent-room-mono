import AppScaffoldKit
import CommonUI
import SwiftUI
import SingleInstanceKit

@main
struct AgentRoomWorktreeApp: FleetManagedWindowGroupApp {
    static let service = "net.ranode.agent-room-worktree"
    static let productName = "Agent Room Worktree"

    @State private var model = AppModel()

    init() {
        SingleInstance.exitIfAlreadyRunning()
        HealthPulse.publish(app: "agent-room-worktree")
    }

    var root: some View {
        MainView(model: model)
    }

    var settingsView: some View {
        SettingsView(model: model)
    }
}
