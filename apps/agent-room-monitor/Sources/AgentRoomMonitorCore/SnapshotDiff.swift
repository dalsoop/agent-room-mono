import Foundation

/// 비교 모드(C.12) — 두 스냅샷의 방 트리에서 생긴·사라진·상태가 바뀐 노드만.
public struct SnapshotDiff: Codable, Sendable, Equatable {
    public var added: [String]
    public var removed: [String]
    public var changed: [String]

    public init(added: [String] = [], removed: [String] = [], changed: [String] = []) {
        self.added = added
        self.removed = removed
        self.changed = changed
    }

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && changed.isEmpty }
}

public enum SnapshotDiffing {
    public static func flatten(_ node: TwinNode) -> [String: TwinNode] {
        var map: [String: TwinNode] = [node.id: node]
        for child in node.children {
            for (key, value) in flatten(child) { map[key] = value }
        }
        return map
    }

    public static func diff(old: TwinNode, new: TwinNode) -> SnapshotDiff {
        let a = flatten(old)
        let b = flatten(new)
        let oldIDs = Set(a.keys)
        let newIDs = Set(b.keys)
        let added = newIDs.subtracting(oldIDs).sorted()
        let removed = oldIDs.subtracting(newIDs).sorted()
        var changed: [String] = []
        for id in oldIDs.intersection(newIDs).sorted() {
            guard let lhs = a[id], let rhs = b[id] else { continue }
            if lhs.state != rhs.state || lhs.name != rhs.name
                || lhs.health.blocked != rhs.health.blocked
                || lhs.children.map(\.id) != rhs.children.map(\.id)
            {
                changed.append(id)
            }
        }
        return SnapshotDiff(added: added, removed: removed, changed: changed)
    }
}
