import Foundation

/// 실제 방 폴더(`~/.tenants/<slug>/rooms/…`)를 방 요약 목록(`[RoomSummary]`)으로 바꾼다.
/// 지휘실 → 테넌트 → 상주 방(→ 자식 방) → 앱 타일(toolbelt) 순의 층위.
/// 입주 여부는 데몬 세션 표(roomDir → sessionID)로 판정한다 — 원장 CLI 를 부르지 않는다.
public enum RoomTreeSource {
    public static let commandRoomID = "command-room"

    public struct Snapshot: Sendable, Equatable {
        public var nodes: [RoomSummary]
        public var roomCount: Int
        public init(nodes: [RoomSummary], roomCount: Int) {
            self.nodes = nodes
            self.roomCount = roomCount
        }
    }

    /// `sessionsByRoomDir`: 표준화한 방 경로 → 세션 id.
    public static func snapshot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sessionsByRoomDir: [String: String] = [:],
        commandRoomTitle: String = "command-room"
    ) throws -> Snapshot {
        let folders = try RoomFolderLocator.allRooms(tenant: nil, environment: environment)
        let validFolders = TenantRoomFilterPolicy.filterDirectories(urls: folders)
        var documents: [(URL, RoomDocument)] = []
        for folder in validFolders {
            let doc = try RoomDocument.load(from: folder)
            let docID = doc.id.precomposedStringWithCanonicalMapping
            if TenantRoomFilterPolicy.isValidRoomIdentifier(docID) {
                documents.append((folder, doc))
            }
        }
        guard !documents.isEmpty else { return Snapshot(nodes: [], roomCount: 0) }
        var nodes: [RoomSummary] = [
            RoomSummary(
                id: commandRoomID,
                tenantID: "system",
                kind: .commandRoom,
                title: commandRoomTitle.precomposedStringWithCanonicalMapping,
                status: .occupied
            ),
        ]
        let knownRoomIDs = Set(documents.map { $0.1.id.precomposedStringWithCanonicalMapping })
        for tenant in Set(documents.map { $0.1.tenant.precomposedStringWithCanonicalMapping }).sorted() {
            nodes.append(RoomSummary(
                id: tenantNodeID(tenant),
                parentID: commandRoomID,
                tenantID: tenant,
                kind: .tenant,
                title: tenant,
                status: .occupied
            ))
        }
        let sortedDocs = documents.sorted {
            $0.1.slug.precomposedStringWithCanonicalMapping < $1.1.slug.precomposedStringWithCanonicalMapping
        }
        for (folder, document) in sortedDocs {
            let stdPath = SessionAuthorizer.standardized(folder.path).precomposedStringWithCanonicalMapping
            let session = sessionsByRoomDir[stdPath] ?? sessionsByRoomDir[SessionAuthorizer.standardized(folder.path)]
            nodes.append(roomNode(folder: folder, document: document, session: session, known: knownRoomIDs))
            nodes.append(contentsOf: appTiles(for: document))
        }
        return Snapshot(nodes: nodes, roomCount: documents.count)
    }

    static func tenantNodeID(_ tenant: String) -> String {
        let normalized = tenant.precomposedStringWithCanonicalMapping
        return "tenant:" + (normalized.hasPrefix("tenant:") ? String(normalized.dropFirst(7)) : normalized)
    }

    private static func resolveTenant(documentTenant: String, folderPath: String) -> String {
        let docTenant = documentTenant.precomposedStringWithCanonicalMapping
        guard docTenant.isEmpty || docTenant == "default" else { return docTenant }
        return RoomListFilter.extractTenant(fromPath: folderPath) ?? docTenant
    }

    private static func resolveProjectedStatus(events: [RoomEvent], session: String?) -> RoomStatus {
        guard events.isEmpty else {
            return RoomStatusProjection.reduce(events: events)
        }
        return session == nil ? .planned : .occupied
    }

    static func roomNode(
        folder: URL,
        document: RoomDocument,
        session: String?,
        known: Set<String>
    ) -> RoomSummary {
        let docID = document.id.precomposedStringWithCanonicalMapping
        let parentID = document.parentRoomID.precomposedStringWithCanonicalMapping
        let isKnownParent = known.contains(parentID) || known.contains(document.parentRoomID)
        let isChild = !parentID.isEmpty && isKnownParent
        let events = RoomEventLog(roomURL: folder).read(since: 0).events
        let projectedStatus = resolveProjectedStatus(events: events, session: session)
        let docTenant = resolveTenant(documentTenant: document.tenant, folderPath: folder.path)
        let docSlug = document.slug.precomposedStringWithCanonicalMapping
        var node = RoomSummary(
            id: docID,
            parentID: isChild ? parentID : tenantNodeID(docTenant),
            tenantID: docTenant,
            kind: isChild ? .childRoom : .standingRoom,
            title: docSlug,
            status: projectedStatus
        )
        node.path = folder.path
        node.wallPreset = document.preset.rawValue
        node.excludedToolCount = document.excludedTools.count
        node.sessionID = projectedStatus.sessionID ?? session
        node.isExample = false
        let bindings: [TranscriptBinding]
        do {
            bindings = try TranscriptRegistry.load(in: folder)
        } catch {
            bindings = []
        }
        let used: Int?
        do {
            used = try UsageLedger.inRoom(folder).totals().used
        } catch {
            used = nil
        }
        node.budget = TranscriptBudgetPresence.usage(
            bindings: bindings,
            used: used,
            handoffAt: document.budget.handoffAt,
            files: FoundationRoomFileIO()
        )
        node.roomMarkdown = (try? String(
            contentsOf: folder.appendingPathComponent("ROOM.md"), encoding: .utf8
        )) ?? ""
        node.bottles = bottleIDs(in: folder).map(HandoffNote.init(id:))
        if let occupant = projectedStatus.occupant {
            node.occupants = [RoomOccupant(handle: occupant, isSuccessor: false)]
        } else if let activeSession = node.sessionID {
            node.occupants = [RoomOccupant(handle: String(activeSession.prefix(8)), isSuccessor: false)]
        }
        if let sessionEvent = events.last(where: { $0.kind == RoomEventKind.sessionStarted }) {
            node.pid = sessionEvent.payload["pid"]?.int
        }
        return node
    }

    static func appTiles(for document: RoomDocument) -> [RoomSummary] {
        let docID = document.id.precomposedStringWithCanonicalMapping
        let docTenant = document.tenant.precomposedStringWithCanonicalMapping
        return document.toolbelt.map { tool in
            let normalizedTool = tool.precomposedStringWithCanonicalMapping
            var tile = RoomSummary(
                id: docID + "/" + normalizedTool,
                parentID: docID,
                tenantID: docTenant,
                kind: .appTile,
                title: normalizedTool,
                status: document.excludedTools.contains(tool) || document.excludedTools.contains(normalizedTool) ? .blocked : .done
            )
            tile.isExample = false
            return tile
        }
    }

    static func bottleIDs(in folder: URL) -> [String] {
        let dir = folder.appendingPathComponent("handoff", isDirectory: true)
        let names = (try? FileManager().contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)).precomposedStringWithCanonicalMapping }
            .sorted()
    }
}
