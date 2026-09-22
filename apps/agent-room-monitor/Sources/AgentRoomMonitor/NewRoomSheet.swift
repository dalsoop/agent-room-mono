import SwiftUI
import AgentRoomMonitorCore

/// 방 만들기 — 도메인 경로 + 테넌트 + 입주 에이전트. 원장은 spawn-room.
struct NewRoomSheet: View {
    @Environment(AppModel.self) private var app
    let board: BoardModel
    @Environment(\.dismiss) private var dismiss

    @State private var handle = ""
    @State private var task = ""
    @State private var verify = ""
    @State private var workdir = ""
    @State private var occupant = ""
    @State private var tools = ""
    @State private var writes = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(app.L(.newRoomTitle)).font(.headline)
            Text(app.L(.newRoomHelp))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            field(app.L(.newRoomHandle), $handle)
            field(app.L(.newRoomTask), $task)
            field(app.L(.newRoomVerify), $verify)
            field(app.L(.newRoomWorkdir), $workdir)
            field(app.L(.newRoomOccupant), $occupant)
            field(app.L(.newRoomTools), $tools)
            field(app.L(.newRoomWrites), $writes)
            HStack {
                Spacer()
                Button(app.L(.newRoomCancel)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(app.L(.newRoomSubmit)) { Task { await submit() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || handle.trimmingCharacters(in: .whitespaces).isEmpty
                              || task.trimmingCharacters(in: .whitespaces).isEmpty
                              || verify.trimmingCharacters(in: .whitespaces).isEmpty
                              || workdir.trimmingCharacters(in: .whitespaces).isEmpty
                              || occupant.trimmingCharacters(in: .whitespaces).isEmpty
                              || resolvedTenant == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .onAppear {
            if occupant.isEmpty { occupant = board.defaultOccupant() }
            if workdir.isEmpty { workdir = board.defaultWorkdir() }
        }
    }

    private var resolvedTenant: String? {
        if let id = board.selectedTenantID, !id.isEmpty { return id }
        if let id = board.world.currentTenantID, !id.isEmpty { return id }
        return nil
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
        }
    }

    private func submit() async {
        busy = true
        defer { busy = false }
        guard let tenant = resolvedTenant else { return }
        let toolList = tools.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let writeList = writes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        await board.operate(.spawnRoom(
            task: task.trimmingCharacters(in: .whitespaces),
            verify: verify.trimmingCharacters(in: .whitespaces),
            handle: handle.trimmingCharacters(in: .whitespaces),
            occupant: occupant.trimmingCharacters(in: .whitespaces),
            workdir: workdir.trimmingCharacters(in: .whitespaces),
            tenant: tenant,
            tools: toolList,
            writes: writeList
        ))
        if board.lastOperateOK {
            let hid = handle.trimmingCharacters(in: .whitespaces)
            if let node = board.findNamed(hid) {
                board.enterRoom(node)
            }
            dismiss()
        }
    }
}
