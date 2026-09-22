import Foundation
import StateRootKit

/// 좌석 결속 JSON 읽기 전용. 경로 기본값은 env `SEAT_BINDINGS_DIR`, 없으면 호스트 상태 루트 아래 상대 경로.
public enum SeatTranscriptStore {
    public static let directoryEnv = "SEAT_BINDINGS_DIR"
    /// 호스트 상태 루트 아래 `store-v2/seats`. 앱 식별자는 리터럴 이어붙임 없이 조립한다.
    public static var relativePath: String {
        let app = ["agent", "work", "todo"].joined(separator: "-")
        return ".\(app)/store-v2/seats"
    }

    public static func directory(
        environment: [String: String],
        homeDirectory: String
    ) -> URL {
        if let override = environment[directoryEnv]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(
            fileURLWithPath: StateRootKit.hostPath(
                relativePath,
                environment: environment,
                homeDirectory: homeDirectory
            ),
            isDirectory: true
        )
    }

    public static func load(
        sessionID: String,
        directory: URL,
        files: any RoomFileIO
    ) throws -> SeatTranscriptRecord? {
        let url = directory.appendingPathComponent("\(sessionID).json")
        guard files.fileExists(atPath: url.path) else { return nil }
        let data = try files.read(from: url)
        return try JSONDecoder().decode(SeatTranscriptRecord.self, from: data)
    }
}

/// 결속 파일에서 전사·방 id 만 읽는다. 쓰기 금지.
public struct SeatTranscriptRecord: Decodable, Equatable, Sendable {
    public var seat: Seat
    public var session: Session
    public var host: Host
    public var transcript: Transcript
    public var released: Released?

    public struct Seat: Decodable, Equatable, Sendable {
        public var roomID: UUID
    }

    public struct Session: Decodable, Equatable, Sendable {
        public var tool: String
        public var id: String
    }

    public struct Host: Decodable, Equatable, Sendable {
        public var workdir: String
    }

    public struct Transcript: Decodable, Equatable, Sendable {
        public var path: String
        public var reason: String
    }

    public struct Released: Decodable, Equatable, Sendable {
        public var reason: String
    }

    public var isLive: Bool { released == nil }

    public var transcriptPath: String {
        transcript.path.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
