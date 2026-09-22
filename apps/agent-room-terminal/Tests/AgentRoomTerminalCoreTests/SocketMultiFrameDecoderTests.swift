import Darwin
import Foundation
import XCTest
@testable import AgentRoomTerminalCore

final class SocketMultiFrameDecoderTests: XCTestCase {
    func testSocketStreamDecodesMultipleFramesWithoutLoss() throws {
        var fds: [Int32] = [0, 0]
        guard Darwin.socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else {
            XCTFail("socketpair failed: \(errno)")
            return
        }
        let readerFd = fds[0]
        let writerFd = fds[1]
        defer {
            Darwin.close(readerFd)
            Darwin.close(writerFd)
        }

        let stream = UnixSocketIO.SocketStream(fd: readerFd)

        let payload1 = Data("frame-alpha".utf8)
        let payload2 = Data("frame-beta".utf8)
        let payload3 = Data("frame-gamma".utf8)

        let frame1 = try DaemonFraming.encode(payload1)
        let frame2 = try DaemonFraming.encode(payload2)
        let frame3 = try DaemonFraming.encode(payload3)

        // 3개의 프레임을 단일 버퍼로 묶어서 한번에 소켓에 전송
        var combined = Data()
        combined.append(frame1)
        combined.append(frame2)
        combined.append(frame3)

        combined.withUnsafeBytes { raw in
            _ = Darwin.write(writerFd, raw.baseAddress, raw.count)
        }

        // 스트림에서 순차적으로 3개 프레임 읽기
        let decoded1 = try stream.readFrame()
        let decoded2 = try stream.readFrame()
        let decoded3 = try stream.readFrame()

        XCTAssertEqual(decoded1, payload1)
        XCTAssertEqual(decoded2, payload2)
        XCTAssertEqual(decoded3, payload3)
    }
}
