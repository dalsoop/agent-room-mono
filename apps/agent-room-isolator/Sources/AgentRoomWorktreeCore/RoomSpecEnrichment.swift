import Foundation

enum RoomSpecEnrichment {
    static func apply(_ bind: RoomWorktreeBind, environment: [String: String]) -> RoomWorktreeBind {
        let specURL = RoomWorktreePaths.roomDirectory(id: bind.roomID, tenantID: bind.tenantID, environment: environment)
            .appendingPathComponent("spec.json")
        let data: Data
        do {
            data = try Data(contentsOf: specURL)
        } catch {
            return bind
        }
        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return bind
            }
            json = parsed
        } catch {
            return bind
        }
        return applyTask(applyVerdict(applyWorkdir(bind, json: json), json: json), json: json)
    }

    static func applyWorkdir(_ bind: RoomWorktreeBind, json: [String: Any]) -> RoomWorktreeBind {
        guard let wd = json["workdir"] as? String, !wd.isEmpty else { return bind }
        var out = bind
        out.worktreePath = wd
        out.branch = URL(fileURLWithPath: wd).lastPathComponent
        return out
    }

    static func applyVerdict(_ bind: RoomWorktreeBind, json: [String: Any]) -> RoomWorktreeBind {
        guard let verdict = json["verdict"] as? String, !verdict.isEmpty else { return bind }
        var out = bind
        out.verify = verdict
        return out
    }

    static func applyTask(_ bind: RoomWorktreeBind, json: [String: Any]) -> RoomWorktreeBind {
        guard bind.task.isEmpty, let task = json["task"] as? String else { return bind }
        var out = bind
        out.task = task
        return out
    }
}
