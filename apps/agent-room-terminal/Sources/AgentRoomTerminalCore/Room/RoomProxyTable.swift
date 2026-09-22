import Foundation

/// 방 디렉터리당 localhost allowlist 프록시 하나.
public final class RoomProxyTable {
    private let lock = NSLock()
    private var items: [String: RoomAllowlistProxy] = [:]

    public init() {}

    public func ensure(roomDir: String, domains: [String]) throws -> RoomAllowlistProxy {
        let key = (roomDir as NSString).standardizingPath
        lock.lock()
        if let existing = items[key], existing.allowedDomains == domains {
            lock.unlock()
            return existing
        }
        let stale = items[key]
        items[key] = nil
        lock.unlock()
        stale?.stop()
        let log = URL(fileURLWithPath: key, isDirectory: true)
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("network-denied.jsonl")
        let proxy = try RoomAllowlistProxy.start(allowedDomains: domains, deniedLogURL: log)
        lock.lock()
        items[key] = proxy
        lock.unlock()
        return proxy
    }

    public func stopAll() {
        lock.lock()
        let all = Array(items.values)
        items = [:]
        lock.unlock()
        for proxy in all {
            proxy.stop()
        }
    }
}
