import Foundation

/// PTY 출력 원시 바이트를 정해진 용량(기본 512 KiB)까지 보관하는 바이트 링 버퍼.
public struct ByteRingBuffer: Sendable {
    public private(set) var capacity: Int
    private var storage: [UInt8]
    private var head: Int = 0
    private var storedBytes: Int = 0

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.storage = [UInt8](repeating: 0, count: self.capacity)
    }

    public var count: Int {
        storedBytes
    }

    public var isEmpty: Bool {
        storedBytes == 0
    }

    public mutating func append(_ data: Data) {
        guard !data.isEmpty else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            append(pointer: baseAddress, count: data.count)
        }
    }

    public mutating func append(slice: ArraySlice<UInt8>) {
        guard !slice.isEmpty else { return }
        slice.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            append(pointer: baseAddress, count: slice.count)
        }
    }

    private mutating func append(pointer: UnsafePointer<UInt8>, count: Int) {
        if count >= capacity {
            let offset = count - capacity
            storage.withUnsafeMutableBufferPointer { dest in
                guard let destBase = dest.baseAddress else { return }
                destBase.update(from: pointer.advanced(by: offset), count: capacity)
            }
            head = 0
            storedBytes = capacity
            return
        }

        let firstChunk = min(count, capacity - head)
        storage.withUnsafeMutableBufferPointer { dest in
            guard let destBase = dest.baseAddress else { return }
            destBase.advanced(by: head).update(from: pointer, count: firstChunk)
            let secondChunk = count - firstChunk
            if secondChunk > 0 {
                destBase.update(from: pointer.advanced(by: firstChunk), count: secondChunk)
            }
        }
        head = (head + count) % capacity
        storedBytes = min(capacity, storedBytes + count)
    }

    public func tail(_ count: Int) -> Data {
        let n = min(max(0, count), storedBytes)
        guard n > 0 else { return Data() }

        let start = (head - n + capacity) % capacity
        if start < head {
            return Data(storage[start..<head])
        } else {
            var data = Data()
            data.reserveCapacity(n)
            data.append(contentsOf: storage[start..<capacity])
            data.append(contentsOf: storage[0..<head])
            return data
        }
    }

    public func snapshot() -> Data {
        tail(storedBytes)
    }

    public mutating func setCapacity(_ newCapacity: Int) {
        let newCap = max(1, newCapacity)
        guard newCap != capacity else { return }
        let currentTail = tail(newCap)
        self.capacity = newCap
        self.storage = [UInt8](repeating: 0, count: newCap)
        self.head = 0
        self.storedBytes = 0
        if !currentTail.isEmpty {
            append(currentTail)
        }
    }
}
