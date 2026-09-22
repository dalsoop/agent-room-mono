import XCTest
import AppKit
import Foundation
import os
@testable import TerminalEngineKit
@testable import TerminalEngineGhostty

@MainActor
final class GhosttyInMemoryStreamTests: XCTestCase {
    func testInMemoryStreamBidirectionalRoundTrip() async throws {
        let stream = TerminalByteStream()
        let receivedData = OSAllocatedUnfairLock(initialState: Data())
        let inputExpectation = expectation(description: "Input callback called")

        stream.onInput = { data in
            receivedData.withLock { $0.append(data) }
            inputExpectation.fulfill()
        }

        let engine = GhosttyTerminalEngine(stream: stream)

        // NSWindow 에 얹어 서피스 빌드 및 이벤트 루프 트리거
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = engine.view
        engine.startIfNeeded()

        // 1. 호스트 -> 터미널 바이트 전송 (receive)
        let message = "Hello Ghostty In-Memory Stream"
        stream.receive(message + "\r\n")
        engine.waitForPendingOutput()

        // readViewportText() 로 뷰포트에 렌더링된 텍스트 확인
        let viewport = engine.readViewportText()
        XCTAssertNotNil(viewport, "readViewportText() should not be nil when surface is attached")
        XCTAssertTrue(viewport?.contains("Hello Ghostty In-Memory Stream") == true, "Viewport text should contain the received text: \(viewport ?? "nil")")

        // 2. 터미널 -> 호스트 입력 전달 (send -> onInput)
        engine.send(text: "A")
        await fulfillment(of: [inputExpectation], timeout: 2.0)
        XCTAssertFalse(receivedData.withLock { $0.isEmpty }, "Input data should have been received by stream.onInput")
    }
}
