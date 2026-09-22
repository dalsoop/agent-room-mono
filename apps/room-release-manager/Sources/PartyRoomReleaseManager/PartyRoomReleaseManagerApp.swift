import StateRootKit
import AppScaffoldKit
import PartyRoomReleaseManagerCore
import DualEntryKit
import PartyRoomReleaseManagerCore
import PermissionKit
import SingleInstanceKit
import SwiftUI

@main
struct PartyRoomReleaseManagerApp: App {
    @State private var model = AppModel()

    init() {
        DualEntryRules.exitIfMisusedFromIdentity()
        RanodeAppBootstrap.applyFleetDeskPolicy()
        HealthPulse.publish(app: "party-room-release-manager", status: "launch")
        if !PermissionBootstrap.isRequested {
            SingleInstance.exitIfAlreadyRunning()
        HealthPulse.publish(app: "party-room-release-manager")
        }
        Task { @MainActor in
            _ = PermissionBootstrap.runIfRequested(appName: "PartyRoomReleaseManager")
        }
    }

    var body: some Scene {
        MenuBarExtra("Party Room Release", systemImage: "shippingbox") {
            if PermissionBootstrap.isRequested {
                EmptyView()
            } else {
                MenuBarView(model: model)
            }
        }
        .menuBarExtraStyle(.window)

        Window("Party Room Release Manager", id: "main") {
            if PermissionBootstrap.isRequested {
                Color.clear.frame(width: 1, height: 1)
            } else {
                MainWindowView(model: model)
                    .gujoManaged()
            }
        }
        .defaultSize(width: 860, height: 560)

        Settings {
            if PermissionBootstrap.isRequested {
                Color.clear.frame(width: 1, height: 1)
            } else {
                SettingsView(model: model)
                    .frame(minWidth: 480, minHeight: 360)
                    .gujoManaged()
            }
        }
    }
}
