import Foundation
import RoomKit
import StateRootKit

/// 성공한 실행의 발자국을 관찰하여 방 벽 초안을 자동 생성하고, 테넌트 미준수 위반 지점을 진단한다.
public enum ProfileThenLock {
    /// 발자국을 분석하여 방 벽 초안을 생성한다.
    public static func generateDraft(
        footprint: ExecutionFootprint,
        roomURL: URL? = nil,
        tenantBoundary: String? = nil,
        stateRoot: String? = nil,
        homeDirectory: String = StateRootKit.resolveHost(environment: [:])
    ) -> RoomWallDraft {
        let violations = diagnoseViolations(
            footprint: footprint,
            roomURL: roomURL,
            tenantBoundary: tenantBoundary,
            stateRoot: stateRoot,
            homeDirectory: homeDirectory
        )

        let (allowedWrites, deniedWrites) = filterAllowedAndDeniedWrites(
            footprint: footprint,
            roomURL: roomURL,
            violations: violations
        )

        let networkWall = determineNetworkWall(from: footprint.networkOutbound)
        let executablesWall = determineExecutablesWall(from: footprint.childProcesses)

        let suggestedPreset = recommendPreset(
            writes: allowedWrites,
            childProcesses: footprint.childProcesses,
            network: networkWall,
            roomURL: roomURL
        )

        let filesystem = FilesystemWall(
            denyRead: [],
            allowRead: footprint.fileReads,
            allowWrite: Array(Set(allowedWrites)).sorted(),
            denyWrite: Array(Set(deniedWrites)).sorted()
        )

        let walls = RoomWalls(
            filesystem: filesystem,
            network: networkWall,
            unixSockets: [],
            executables: executablesWall,
            shell: suggestedPreset == .open ? .normal : .restricted
        )

        let summary = "관찰된 실행 발자국 기반 벽 초안 (쓰기 \(allowedWrites.count)개, 도구 \(footprint.childProcesses.count)개, 위반 \(violations.count)건)"

        return RoomWallDraft(
            walls: walls,
            suggestedPreset: suggestedPreset,
            violations: violations,
            summary: summary,
            footprint: footprint
        )
    }

    private static func filterAllowedAndDeniedWrites(
        footprint: ExecutionFootprint,
        roomURL: URL?,
        violations: [TenantViolation]
    ) -> (allowed: [String], denied: [String]) {
        var allowedWrites: [String] = []
        var deniedWrites = RoomWalls.mandatoryDenyWrite

        for rawPath in footprint.fileWrites {
            let normalized = (rawPath as NSString).standardizingPath

            let isMandatoryDeny = RoomWalls.mandatoryDenyWrite.contains { deny in
                normalized.hasSuffix("/" + deny) || normalized == deny
            }
            if isMandatoryDeny {
                appendDeniedIfMissing(&deniedWrites, normalized: normalized)
                continue
            }

            guard !violations.contains(where: { $0.path == normalized && $0.operation == "write" }) else {
                continue
            }
            allowedWrites.append(normalized)
        }

        appendRoomWorkPathIfMissing(&allowedWrites, roomURL: roomURL)

        return (allowedWrites, deniedWrites)
    }

    private static func appendDeniedIfMissing(_ deniedWrites: inout [String], normalized: String) {
        guard !deniedWrites.contains(normalized) else { return }
        deniedWrites.append(normalized)
    }

    private static func appendRoomWorkPathIfMissing(_ allowedWrites: inout [String], roomURL: URL?) {
        guard let roomURL else { return }
        let workPath = roomURL.appendingPathComponent("work").path
        guard !allowedWrites.contains(workPath) else { return }
        allowedWrites.append(workPath)
    }

    private static func determineNetworkWall(from outbound: [String]) -> NetworkWall {
        guard !outbound.isEmpty else {
            return .closed
        }
        let domains = extractDomains(from: outbound)
        guard !domains.isEmpty else {
            return .open
        }
        return .allow(domains: domains)
    }

    private static func determineExecutablesWall(from childProcesses: [String]) -> ExecutablesWall {
        guard !childProcesses.isEmpty else {
            return .hostPath
        }
        let tools = Array(Set(childProcesses)).sorted()
        return .allowList(tools)
    }

    /// 테넌트 경계 밖 쓰기나 상태 루트 오염을 진단한다.
    public static func diagnoseViolations(
        footprint: ExecutionFootprint,
        roomURL: URL? = nil,
        tenantBoundary: String? = nil,
        stateRoot: String? = nil,
        homeDirectory: String = StateRootKit.resolveHost(environment: [:])
    ) -> [TenantViolation] {
        var violations = diagnoseSensitiveWrites(writes: footprint.fileWrites)
        guard let boundary = resolveEffectiveBoundary(tenantBoundary: tenantBoundary, roomURL: roomURL) else {
            return violations
        }
        violations.append(contentsOf: diagnoseBoundaryViolations(
            writes: footprint.fileWrites,
            boundary: boundary,
            stateRoot: stateRoot
        ))
        return violations
    }

    private static func diagnoseSensitiveWrites(writes: [String]) -> [TenantViolation] {
        var violations: [TenantViolation] = []
        for path in writes {
            let normalized = (path as NSString).standardizingPath
            for deny in RoomWalls.mandatoryDenyWrite {
                guard normalized.hasSuffix("/" + deny) || normalized == deny else { continue }
                violations.append(TenantViolation(
                    path: normalized,
                    operation: "write",
                    reason: "시스템 민감 파일(\(deny))에 대한 무단 쓰기 시도"
                ))
            }
        }
        return violations
    }

    private static func resolveEffectiveBoundary(tenantBoundary: String?, roomURL: URL?) -> String? {
        if let tenantBoundary {
            return tenantBoundary
        }
        guard let roomURL else { return nil }
        let comps = roomURL.pathComponents
        guard let tenantsIdx = comps.firstIndex(of: ".tenants"), tenantsIdx + 1 < comps.count else {
            return nil
        }
        let tenantRoot = comps[0...(tenantsIdx + 1)].joined(separator: "/")
        return tenantRoot.isEmpty ? nil : tenantRoot
    }

    private static let osTemporaryPrefixes: [String] = [
        "/tmp", "/private/tmp", "/var/folders", "/private/var/folders"
    ]

    private static func isIgnoredPath(_ normalized: String) -> Bool {
        if osTemporaryPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return true
        }
        if normalized.contains("Library/Caches/org.swift.swiftpm") || normalized.contains(".swiftpm") {
            return true
        }
        return false
    }

    private static func diagnoseBoundaryViolations(
        writes: [String],
        boundary: String,
        stateRoot: String?
    ) -> [TenantViolation] {
        var violations: [TenantViolation] = []
        for path in writes {
            let normalized = (path as NSString).standardizingPath
            guard !isIgnoredPath(normalized) else { continue }
            guard !normalized.hasPrefix(boundary) else { continue }
            if let stateRoot, normalized.hasPrefix(stateRoot) {
                continue
            }
            violations.append(TenantViolation(
                path: normalized,
                operation: "write",
                reason: "테넌트 경계(\(boundary)) 외부 쓰기 — 테넌트 격리 미준수"
            ))
        }
        return violations
    }

    private static func recommendPreset(
        writes: [String],
        childProcesses: [String],
        network: NetworkWall,
        roomURL: URL?
    ) -> RoomWallPreset {
        // 쓰기가 전혀 없으면 readOnly
        if writes.isEmpty {
            return .readOnly
        }

        // 도구 개수가 6개 이하이고, 컴파일러(swift/clang)나 대규모 빌드가 아니며,
        // 쓰기가 방/workdir로 한정되는 경우 -> toolbelt
        let isBuildTool = childProcesses.contains { proc in
            ["swift", "swiftc", "clang", "cargo", "go", "npm"].contains(proc)
        }
        if isBuildTool || childProcesses.count > 6 {
            return .open
        }

        return .toolbelt
    }

    private static func extractDomains(from endpoints: [String]) -> [String] {
        var domains = Set<String>()
        for ep in endpoints {
            var host = ep
            if let portIdx = host.firstIndex(of: ":") {
                host = String(host[..<portIdx])
            }
            host = host.trimmingCharacters(in: .whitespacesAndNewlines)
            if !host.isEmpty && !isNumericIP(host) {
                domains.insert(host)
            } else if !host.isEmpty {
                domains.insert(host)
            }
        }
        return Array(domains).sorted()
    }

    private static func isNumericIP(_ str: String) -> Bool {
        let parts = str.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0) != nil }
    }
}
