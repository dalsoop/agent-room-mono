import SwiftUI
import MenuBarPopoverUIKit
import AppKit
import PartyRoomReleaseManagerCore
import AppScaffoldKit

struct MenuBarView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        StandardMenuBarPopover(
            width: 280,
            settingsTitle: model.L(.menuSettings),
            quitTitle: model.L(.menuQuit),
            onOpenSettings: { RanodeSettingsLink.open() },
            onQuit: { NSApplication.shared.terminate(nil) }
        ) {
            HStack {
                            Text(model.L(.menubarTitle))
                                .font(.headline)
                            Spacer()
                            if model.isBusy {
                                ProgressView().controlSize(.small)
                            }
                        }
            
                        Text(model.statusLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(minWidth: 20)
                            .fixedSize(horizontal: false, vertical: true)
            
                        if let arts = model.probe?.artifacts {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(arts) { a in
                                    HStack(spacing: 6) {
                                        Image(systemName: a.platform.systemImage)
                                            .frame(width: 16)
                                        Text(a.platform.displayName)
                                            .font(.callout)
                                        Spacer()
                                        Image(systemName: a.ready ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(a.ready ? .green : .secondary)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
            
                        Divider()
            
                        Button {
                            Task { await model.build(.macos) }
                        } label: {
                            Label("macOS DMG (release.sh)", systemImage: "desktopcomputer")
                        }
                        .disabled(model.isBusy)
            
                        Button {
                            Task { await model.build(.android) }
                        } label: {
                            Label("Android APK", systemImage: "smartphone")
                        }
                        .disabled(model.isBusy)
            
                        Button {
                            openWindow(id: "main")
                        } label: {
                            Label(model.L(.menubarOpenMain), systemImage: "macwindow")
                        }
            
                        Divider()
            
                        Button {
                            Task { await model.refresh() }
                        } label: {
                            Label(model.L(.menuRefresh), systemImage: "arrow.clockwise")
                        }
                        .disabled(model.isBusy)
        }
        .task { await model.refresh() }
    }
}
