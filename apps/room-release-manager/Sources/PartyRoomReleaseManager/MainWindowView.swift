import SwiftUI
import AppKit
import PartyRoomReleaseManagerCore

/// 메인 배포 콘솔 — 플랫폼 빌드·경로·GitHub Release 힌트.
struct MainWindowView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            // HSplitView 는 스스로 안 늘어난다
            HSplitView {
                leftPane
                    .frame(minWidth: 280, idealWidth: 300)
                rightPane
                    .frame(minWidth: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 480)
        .task { await model.refresh() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Party Room Release Manager")
                    .font(.title3.bold())
                Text(model.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isBusy {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await model.refresh() }
            } label: {
                Label(model.L(.menuRefresh), systemImage: "arrow.clockwise")
            }
            .disabled(model.isBusy)
        }
        .padding(14)
    }

    private var leftPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox(model.L(.MainWindowViewGroupbox)) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(model.L(.MainWindowViewTextfield), text: $model.pathDraft)
                            .textFieldStyle(.roundedBorder)
                        TextField("GitHub owner/repo", text: $model.repoDraft)
                            .textFieldStyle(.roundedBorder)
                        TextField(model.L(.MainWindowViewTextfield_2), text: $model.versionDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                        HStack {
                            Button(model.L(.mainSaveConfig)) { model.applyConfigDrafts() }
                            Button("Finder") { Task { await model.openProject() } }
                        }
                        if let p = model.probe {
                            probeRow("pubspec", p.hasPubspec)
                            probeRow("android/", p.hasAndroid)
                            probeRow("macos/", p.hasMacOS)
                            probeRow("windows/", p.hasWindows)
                            probeRow("ios/", p.hasIOS)
                            probeRow("release.sh", p.hasReleaseScript)
                            probeRow("flutter", p.flutterOnPath)
                            probeRow("gh", p.ghOnPath)
                        }
                    }
                    .padding(4)
                }

                GroupBox(model.L(.MainWindowViewGroupbox_2)) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(PartyRoomPlatform.allCases) { platform in
                            let art = model.probe?.artifacts.first { $0.platform == platform }
                            HStack {
                                Image(systemName: platform.systemImage)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(platform.displayName).font(.callout.weight(.semibold))
                                    Text(art?.note ?? "")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .frame(minWidth: 20)
                                        .frame(minWidth: 0)
                                }
                                Spacer()
                                if art?.ready == true {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                                Button(model.L(.platformBuild)) {
                                    Task { await model.build(platform) }
                                }
                                .disabled(model.isBusy)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        Button {
                            Task { await model.openArtifacts() }
                        } label: {
                            Label(model.L(.mainOpenArtifacts), systemImage: "folder")
                        }
                        .disabled(model.isBusy)
                    }
                    .padding(4)
                }

                GroupBox(model.L(.MainWindowViewGroupbox_3)) {
                    Text(model.L(.iosInstallHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(4)
                }
            }
            .padding(12)
        }
    }

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.L(.mainBuildLog))
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
            ScrollView {
                Text(model.lastLog.isEmpty ? model.L(.MainWindowViewMessage) : model.lastLog)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)

            GroupBox(model.L(.MainWindowViewGroupbox_4)) {
                Text(model.releaseHint)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }
            .padding(12)
        }
    }

    private func probeRow(_ title: String, _ ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? .green : .orange)
                .font(.caption)
            Text(title).font(.caption)
        }
    }
}
