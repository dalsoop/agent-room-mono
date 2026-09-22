import Foundation

/// 옛 이름. 정본은 `HandoffDigest`.
public typealias HandoffDigestDocument = HandoffDigest

/// 핸드오프가 원장 큐에 내는 요청. 순서는 digest → occupy successor.
public enum HandoffLedgerOp: Sendable, Equatable {
    case digest(HandoffDigestDocument)
    case occupySuccessor(
        planID: String,
        roomID: String,
        occupant: String,
        handle: String?,
        wallMode: String
    )
}

public protocol LedgerSubmitting: Sendable {
    func submit(
        _ request: LedgerRequest,
        by authority: LedgerAuthority
    ) async -> LedgerReply
}

extension LedgerQueue: LedgerSubmitting {}

public protocol HandoffLedgerPort: Sendable {
    func submit(
        _ op: HandoffLedgerOp,
        by authority: LedgerAuthority
    ) async -> LedgerReply
}

/// LedgerQueue 로 occupy --successor 를 보낸다. digest 는 방 빈병 파일이 정본이다.
public struct HandoffLedgerQueue: HandoffLedgerPort {
    private let queue: any LedgerSubmitting

    public init(queue: any LedgerSubmitting) {
        self.queue = queue
    }

    public func submit(
        _ op: HandoffLedgerOp,
        by authority: LedgerAuthority
    ) async -> LedgerReply {
        switch op {
        case .digest:
            return .success(#"{"ok":true,"kind":"digest"}"#)
        case let .occupySuccessor(planID, roomID, occupant, handle, wallMode):
            return await queue.submit(
                .occupy(
                    planID: planID,
                    roomID: roomID,
                    occupant: occupant,
                    handle: handle,
                    successor: true,
                    wallMode: wallMode
                ),
                by: authority
            )
        }
    }
}
