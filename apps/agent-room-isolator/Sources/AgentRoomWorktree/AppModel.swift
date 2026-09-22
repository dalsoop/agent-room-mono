import Foundation
import Observation
import LocalizationKit
import AgentRoomWorktreeCore

@MainActor
@Observable
final class AppModel {
    let loc = LocalizationManager(baseBundle: ResourceBundle.localization())
    private let service = AgentRoomWorktreeService()

    var status: String = ""
    var errorMessage: String?
    var binds: [RoomWorktreeBind] = []
    var selectedRoomID: String?
    var documents: [RoomDocumentSnapshot] = []
    var worktreePresent = false
    var trace: RoomTrace?
    var showProvision = false
    var draftTask = ""
    var draftVerify = ""
    var draftRepo = ""
    var draftOccupant = OccupantIdentity.fromEnvironment() ?? ""
    var draftTenant = ""
    var draftDryRun = true

    var selectedBind: RoomWorktreeBind? {
        binds.first(where: { $0.roomID == selectedRoomID })
    }

    init() {
        Task { await self.refresh() }
    }

    func L(_ key: L10nKey) -> String { loc.string(key.rawValue) }

    func refresh() async {
        do {
            try service.ensureDurableStore()
            binds = try await service.list()
            if selectedRoomID == nil {
                selectedRoomID = binds.first?.roomID
            } else if selectedBind == nil {
                selectedRoomID = binds.first?.roomID
            }
            await loadSelection()
            status = try await service.status()
            errorMessage = nil
            StateMirrorAdoption.publish(bindCount: binds.count)
        } catch {
            let message = String(describing: error)
            errorMessage = message
            StateMirrorAdoption.publish(lastError: message)
        }
    }

    func emitSelectedMd() async {
        guard let id = selectedRoomID else { return }
        do {
            _ = try await service.emitMd(roomID: id)
            await loadSelection()
            errorMessage = nil
            StateMirrorAdoption.publish(bindCount: binds.count)
        } catch {
            let message = String(describing: error)
            errorMessage = message
            StateMirrorAdoption.publish(lastError: message)
        }
    }

    func provisionDraft() async {
        do {
            try service.ensureDurableStore()
            let result = try await service.provision(ProvisionRequest(
                task: draftTask,
                verify: draftVerify,
                repoPath: draftRepo,
                name: RoomConcept.slug(from: draftTask, fallback: "room"),
                occupant: draftOccupant,
                quote: draftTask,
                tenantID: draftTenant,
                dryRun: draftDryRun,
                spawn: !draftDryRun
            ))
            errorMessage = nil
            if !result.dryRun {
                binds = try await service.list()
                selectedRoomID = result.bind.roomID
                await loadSelection()
            }
            status = try await service.status()
            StateMirrorAdoption.publish(bindCount: binds.count)
        } catch {
            let message = String(describing: error)
            errorMessage = message
            StateMirrorAdoption.publish(lastError: message)
        }
    }

    private func loadSelection() async {
        guard let bind = selectedBind else {
            documents = []
            worktreePresent = false
            trace = nil
            return
        }
        do {
            let t = try await service.trace(roomID: bind.roomID)
            trace = t
            worktreePresent = t.worktree.pathExists
            documents = t.documents
        } catch {
            worktreePresent = service.worktreeExists(bind)
            do {
                documents = try service.documentSnapshots(roomID: bind.roomID, tenantID: bind.tenantID)
            } catch {
                documents = []
            }
            trace = nil
        }
    }
}
