import XCTest
@testable import AgentRoomTerminalCore

final class ByteRingBufferTests: XCTestCase {
    func testAppendAndTailBasic() {
        var ring = ByteRingBuffer(capacity: 16)
        XCTAssertTrue(ring.isEmpty)
        XCTAssertEqual(ring.count, 0)
        XCTAssertEqual(ring.tail(5), Data())

        ring.append(Data("hello".utf8))
        XCTAssertFalse(ring.isEmpty)
        XCTAssertEqual(ring.count, 5)
        XCTAssertEqual(ring.tail(5), Data("hello".utf8))
        XCTAssertEqual(ring.tail(3), Data("llo".utf8))
        XCTAssertEqual(ring.tail(10), Data("hello".utf8))
        XCTAssertEqual(ring.tail(0), Data())
        XCTAssertEqual(ring.snapshot(), Data("hello".utf8))
    }

    func testOverflowPreservesUpperLimitAndEvictsOldest() {
        var ring = ByteRingBuffer(capacity: 10)
        ring.append(Data("123456".utf8))
        XCTAssertEqual(ring.count, 6)
        XCTAssertEqual(ring.tail(6), Data("123456".utf8))

        // Append 7 more bytes: "ABCDEFG". Total ingested = 13, capacity = 10.
        // Oldest 3 bytes ("123") evicted. Remaining: "456ABCDEFG".
        ring.append(Data("ABCDEFG".utf8))
        XCTAssertEqual(ring.count, 10)
        XCTAssertEqual(ring.tail(10), Data("456ABCDEFG".utf8))
        XCTAssertEqual(ring.tail(7), Data("ABCDEFG".utf8))
        XCTAssertEqual(ring.tail(4), Data("DEFG".utf8))
    }

    func testAppendSliceDirectly() {
        var ring = ByteRingBuffer(capacity: 8)
        let array = [UInt8]("0123456789".utf8)
        ring.append(slice: array[2..<7]) // "23456" (5 bytes)
        XCTAssertEqual(ring.count, 5)
        XCTAssertEqual(ring.tail(5), Data("23456".utf8))
    }

    func testWriteLargerThanCapacityKeepsOnlyTail() {
        var ring = ByteRingBuffer(capacity: 5)
        ring.append(Data("0123456789".utf8)) // 10 bytes into capacity 5
        XCTAssertEqual(ring.count, 5)
        XCTAssertEqual(ring.tail(5), Data("56789".utf8))
        XCTAssertEqual(ring.tail(3), Data("789".utf8))
    }

    func testDynamicCapacityResize() {
        var ring = ByteRingBuffer(capacity: 10)
        ring.append(Data("0123456789".utf8))
        XCTAssertEqual(ring.count, 10)

        // Shrink capacity: trims oldest
        ring.setCapacity(6)
        XCTAssertEqual(ring.capacity, 6)
        XCTAssertEqual(ring.count, 6)
        XCTAssertEqual(ring.tail(6), Data("456789".utf8))

        // Expand capacity: preserves current data and allows appending more
        ring.setCapacity(12)
        XCTAssertEqual(ring.capacity, 12)
        XCTAssertEqual(ring.count, 6)
        XCTAssertEqual(ring.tail(6), Data("456789".utf8))

        ring.append(Data("ABCD".utf8))
        XCTAssertEqual(ring.count, 10)
        XCTAssertEqual(ring.tail(10), Data("456789ABCD".utf8))
    }
}
