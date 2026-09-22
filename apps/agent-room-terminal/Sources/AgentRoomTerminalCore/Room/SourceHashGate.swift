import Foundation
import CommandKit
import InstallHealthKit
import StateRootKit
#if canImport(CryptoKit)
import CryptoKit
#endif

public struct SourceHashCheckResult: Sendable, Equatable {
    public var isStale: Bool
    public var reason: String?

    public init(isStale: Bool, reason: String? = nil) {
        self.isStale = isStale
        self.reason = reason
    }

    public static let fresh = SourceHashCheckResult(isStale: false)
    public static func stale(_ reason: String) -> SourceHashCheckResult {
        SourceHashCheckResult(isStale: true, reason: reason)
    }
}

public protocol SourceHashChecking: Sendable {
    func checkSourceHash(cli: String, destination: String) -> SourceHashCheckResult
}

/// 방에 도구를 링크하기 전 설치본 sourceHash 일치 여부를 검사하는 게이트.
/// stale 설치본이 방 안의 판정을 오염시키지 않도록 방어한다.
public struct DefaultSourceHashGate: SourceHashChecking, Sendable {
    public var environment: [String: String]
    public var homeDirectory: String
    public var customStampDirectory: URL?

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = StateRootKit.resolveHost(),
        customStampDirectory: URL? = nil
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.customStampDirectory = customStampDirectory
    }

    public var stampDirectory: URL {
        if let custom = customStampDirectory { return custom }
        return StateRootKit.url(
            ".agent-ops/install-stamps",
            environment: environment,
            homeDirectory: homeDirectory
        )
    }

    private static func sha256Hex(_ data: Data) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return ""
        #endif
    }

    public func checkSourceHash(cli: String, destination: String) -> SourceHashCheckResult {
        let fm = FileManager()
        if let stampResult = checkStampFile(cli: cli, destination: destination, fileManager: fm) {
            return stampResult
        }
        return checkFallbackProbes(cli: cli, destination: destination)
    }

    private func checkFallbackProbes(cli: String, destination: String) -> SourceHashCheckResult {
        let indexURL = stampDirectory.appendingPathComponent("stale-index.json")
        if let reason = StaleInstallIndex.reason(for: cli, at: indexURL) {
            return .stale(reason)
        }
        if StaleInstallProbe.isStaleByProbe(destination: destination) {
            return .stale("설치본이 소스보다 낡았습니다")
        }
        return .fresh
    }

    private func checkStampFile(cli: String, destination: String, fileManager: FileManager) -> SourceHashCheckResult? {
        let stampFile = stampDirectory.appendingPathComponent("\(cli).json")
        guard fileManager.fileExists(atPath: stampFile.path) else { return nil }
        guard let data = try? Data(contentsOf: stampFile) else { return nil }

        let rawObj: Any
        do {
            rawObj = try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
        guard let obj = rawObj as? [String: Any] else { return nil }

        if let binaryCheck = checkBinarySHA(obj: obj, destination: destination, fileManager: fileManager) {
            return binaryCheck
        }

        return checkSourceHashMatch(obj: obj, fileManager: fileManager)
    }

    private func checkBinarySHA(obj: [String: Any], destination: String, fileManager: FileManager) -> SourceHashCheckResult? {
        guard let expectedSHA = obj["binarySHA256"] as? String, !expectedSHA.isEmpty,
              let binData = fileManager.contents(atPath: destination) else {
            return nil
        }
        let actualSHA = Self.sha256Hex(binData)
        guard actualSHA != expectedSHA else { return nil }
        return .stale("제3자가 덮어씀(해시 불일치)")
    }

    private func checkSourceHashMatch(obj: [String: Any], fileManager: FileManager) -> SourceHashCheckResult? {
        guard let installedHash = obj["sourceHash"] as? String, !installedHash.isEmpty,
              let appPath = obj["appPath"] as? String, !appPath.isEmpty,
              let repo = obj["repo"] as? String, !repo.isEmpty,
              fileManager.fileExists(atPath: repo) else {
            return nil
        }
        guard let currentHash = InstallProvenance.sourceHash(appPath: appPath, root: repo),
              !currentHash.isEmpty else {
            return nil
        }
        guard installedHash != currentHash else {
            return .fresh
        }
        return .stale("소스 콘텐츠가 바뀜(sourceHash 불일치)")
    }
}

public struct FixtureSourceHashGate: SourceHashChecking, Sendable {
    public var staleTools: [String: String]

    public init(staleTools: [String: String] = [:]) {
        self.staleTools = staleTools
    }

    public func checkSourceHash(cli: String, destination: String) -> SourceHashCheckResult {
        if let reason = staleTools[cli] {
            return .stale(reason)
        }
        return .fresh
    }
}
