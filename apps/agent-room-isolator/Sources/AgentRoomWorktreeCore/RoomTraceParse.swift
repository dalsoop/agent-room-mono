import Foundation

enum SpawnRoomJSON {
    static func parse(_ stdout: String) -> (roomID: String, planID: String)? {
        guard let payload = jsonObject(stdout) else { return nil }
        let room = stringID(payload["roomID"])
        let plan = stringID(payload["planID"])
        guard let room, let plan else { return nil }
        return (room, plan)
    }

    static func jsonObject(_ stdout: String) -> [String: Any]? {
        guard let data = stdout.data(using: .utf8) else { return nil }
        let obj: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            obj = parsed
        } catch {
            return nil
        }
        if let payload = obj["payload"] as? [String: Any] { return payload }
        if let result = obj["result"] as? [String: Any] { return result }
        return obj
    }

    static func stringID(_ value: Any?) -> String? {
        if let s = value as? String, !s.isEmpty { return s }
        return nil
    }
}

enum PlacementShowJSON {
    static func parse(stdout: String, expectedRoomID: String, planID: String) -> LedgerTrace {
        let missing = LedgerTrace(
            ok: false, planID: planID, roomID: expectedRoomID,
            state: "", occupant: "", error: "placement-missing"
        )
        guard let payload = SpawnRoomJSON.jsonObject(stdout) else { return missing }
        if let err = payload["error"] as? [String: Any], payload["ok"] as? Bool == false {
            return LedgerTrace(
                ok: false, planID: planID, roomID: expectedRoomID,
                state: "", occupant: "",
                error: SpawnRoomJSON.stringID(err["message"]) ?? "placement-error"
            )
        }
        let id = SpawnRoomJSON.stringID(payload["planID"]) ?? SpawnRoomJSON.stringID(payload["id"]) ?? planID
        let state = SpawnRoomJSON.stringID(payload["state"]) ?? ""
        let rooms = payload["rooms"] as? [[String: Any]] ?? []
        let match = roomMatch(rooms, expectedRoomID: expectedRoomID)
        let occupant = match.occupant
        let roomHit = expectedRoomID.isEmpty || match.hit
        let ok = !id.isEmpty && roomHit && state != ""
        return LedgerTrace(
            ok: ok,
            planID: id,
            roomID: expectedRoomID,
            state: state,
            occupant: occupant,
            error: ok ? "" : "placement-room-mismatch"
        )
    }

    static func roomID(_ room: [String: Any]) -> String? {
        SpawnRoomJSON.stringID(room["roomID"]) ?? SpawnRoomJSON.stringID(room["id"])
    }

    static func roomMatch(_ rooms: [[String: Any]], expectedRoomID: String) -> (occupant: String, hit: Bool) {
        let preferred = rooms.first(where: { roomID($0) == expectedRoomID }) ?? rooms.first
        guard let match = preferred else { return ("", false) }
        let occupant = SpawnRoomJSON.stringID(match["occupant"])
            ?? SpawnRoomJSON.stringID(match["occupantHandle"])
            ?? ""
        return (occupant, roomID(match) == expectedRoomID)
    }
}

enum PlacementListJSON {
    static let terminalStates: Set<String> = ["abandoned", "rejected", "completed", "done"]

    static func parse(_ stdout: String) -> [RoomWorktreeBind] {
        guard let data = stdout.data(using: .utf8) else { return [] }
        let obj: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return []
            }
            obj = parsed
        } catch {
            return []
        }
        let payload = obj["payload"] as? [[String: Any]]
            ?? obj["result"] as? [[String: Any]]
            ?? []
        var out: [RoomWorktreeBind] = []
        for plan in payload {
            let state = (plan["state"] as? String ?? "").lowercased()
            if terminalStates.contains(state) { continue }
            let planID = plan["id"] as? String ?? plan["planID"] as? String ?? ""
            let tenant = plan["tenantID"] as? String ?? ""
            let rooms = plan["rooms"] as? [[String: Any]] ?? []
            for room in rooms {
                let roomID = room["roomID"] as? String ?? room["id"] as? String ?? ""
                guard !roomID.isEmpty else { continue }
                let slug = room["blueprintSlug"] as? String ?? roomID
                let task = room["task"] as? String ?? (plan["title"] as? String ?? "")
                out.append(RoomWorktreeBind(
                    roomID: roomID,
                    planID: planID,
                    slug: slug,
                    task: task,
                    verify: "",
                    worktreePath: "",
                    branch: "",
                    repoPath: "",
                    tenantID: tenant,
                    createdAt: Date()
                ))
            }
        }
        return out
    }
}

enum GitWorktreeList {
    static func lists(path: String, porcelain: String) -> (listed: Bool, branch: String) {
        let needle = (path as NSString).standardizingPath
        var currentPath = ""
        var currentBranch = ""
        var found = false
        var foundBranch = ""
        for line in porcelain.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            applyPorcelainLine(line, currentPath: &currentPath, currentBranch: &currentBranch)
            guard line.isEmpty else { continue }
            applyMatch(path: currentPath, branch: currentBranch, needle: needle, found: &found, foundBranch: &foundBranch)
        }
        applyMatch(path: currentPath, branch: currentBranch, needle: needle, found: &found, foundBranch: &foundBranch)
        return (found, foundBranch)
    }

    static func applyPorcelainLine(_ line: String, currentPath: inout String, currentBranch: inout String) {
        guard !line.hasPrefix("worktree ") else {
            currentPath = String(line.dropFirst("worktree ".count))
            currentBranch = ""
            return
        }
        guard line.hasPrefix("branch ") else { return }
        let ref = String(line.dropFirst("branch ".count))
        currentBranch = ref.split(separator: "/").last.map(String.init) ?? ref
    }

    static func applyMatch(
        path: String, branch: String, needle: String, found: inout Bool, foundBranch: inout String
    ) {
        guard (path as NSString).standardizingPath == needle else { return }
        found = true
        foundBranch = branch
    }
}
