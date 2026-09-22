import Foundation

public enum DaemonFrameError: Error, Equatable, Sendable {
    case zeroLengthFrame
    case frameTooLarge
    case truncated
}

public enum DaemonFraming {
    public static let maximumFrameBytes = 8 * 1024 * 1024
    public static let headerByteCount = MemoryLayout<UInt32>.size

    public static func encode(_ payload: Data) throws -> Data {
        guard payload.count > 0 else {
            throw DaemonFrameError.zeroLengthFrame
        }
        guard payload.count <= maximumFrameBytes else {
            throw DaemonFrameError.frameTooLarge
        }
        var payloadLength = UInt32(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &payloadLength) { Data($0) }
        frame.append(payload)
        return frame
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encode(try encoder.encode(value))
    }

    public static func decodeRequest(_ payload: Data) throws -> DaemonRequest {
        try JSONDecoder().decode(DaemonRequest.self, from: payload)
    }

    public static func decodeResponse(_ payload: Data) throws -> DaemonResponse {
        try JSONDecoder().decode(DaemonResponse.self, from: payload)
    }
}

public struct DaemonFrameDecoder: Sendable {
    private let maxFrameBytes: Int
    private var header: [UInt8] = []
    private var payload = Data()
    private var expectedPayloadBytes: Int?

    public init(maxFrameBytes: Int = DaemonFraming.maximumFrameBytes) {
        self.maxFrameBytes = maxFrameBytes
        header.reserveCapacity(DaemonFraming.headerByteCount)
    }

    public mutating func append(_ bytes: Data) throws -> [Data] {
        var frames: [Data] = []
        var offset = 0
        let raw = [UInt8](bytes)
        while offset < raw.count {
            if expectedPayloadBytes == nil {
                offset = try consumeHeader(raw: raw, offset: offset)
                if expectedPayloadBytes == nil {
                    continue
                }
            }
            guard let expected = expectedPayloadBytes else { continue }
            let count = min(expected - payload.count, raw.count - offset)
            payload.append(contentsOf: raw[offset..<(offset + count)])
            offset += count
            guard payload.count == expected else { continue }
            frames.append(payload)
            payload = Data()
            expectedPayloadBytes = nil
        }
        return frames
    }

    private mutating func consumeHeader(raw: [UInt8], offset: Int) throws -> Int {
        let need = DaemonFraming.headerByteCount - header.count
        let count = min(need, raw.count - offset)
        header.append(contentsOf: raw[offset..<(offset + count)])
        let next = offset + count
        guard header.count == DaemonFraming.headerByteCount else {
            return next
        }
        let frameLength = header.reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
        header.removeAll(keepingCapacity: true)
        guard frameLength > 0 else {
            throw DaemonFrameError.zeroLengthFrame
        }
        guard frameLength <= UInt32(maxFrameBytes) else {
            throw DaemonFrameError.frameTooLarge
        }
        expectedPayloadBytes = Int(frameLength)
        payload.reserveCapacity(Int(frameLength))
        return next
    }
}
