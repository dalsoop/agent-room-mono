import CommandKit
import Foundation
import RoomKit

struct RoomBinPlan: Sendable {
    var links: [(name: String, destination: String)]
    var excluded: [String]
    var staleTools: [String]

    var names: Set<String> { Set(links.map { $0.name }) }
}

enum RoomBinPlanner {
    static var toolbeltLimit: Int { PathPlanner.toolbeltLimit }
    static var agentHelpers: [String: [String]] { PathPlanner.agentHelpers }

    static func plan(spec: RoomAssemblySpec, baseBin: URL) throws -> RoomBinPlan {
        let walls = spec.blueprint.makeWalls()
        switch spec.blueprint.preset {
        case .open:
            var excluded: [String] = []
            try collectExcluded(from: spec, into: &excluded)
            return RoomBinPlan(links: [], excluded: excluded, staleTools: [])
        case .readOnly, .toolbelt:
            return try basePlan(spec: spec, baseBin: baseBin, walls: walls, includeToolbelt: spec.blueprint.preset == .toolbelt)
        }
    }

    private static func basePlan(
        spec: RoomAssemblySpec,
        baseBin: URL,
        walls: RoomWalls,
        includeToolbelt: Bool
    ) throws -> RoomBinPlan {
        let selfName = BaseBinFolder.selfCLIName
        var availableTools = try initialTools(baseBin: baseBin, selfName: selfName, spec: spec)

        var complianceExcluded: [String] = []
        if includeToolbelt {
            let pathEnv = BinaryLocator.pathValue(from: spec.environment)
            try populateToolbeltAndHelpers(
                spec: spec,
                pathEnv: pathEnv,
                selfName: selfName,
                availableTools: &availableTools,
                complianceExcluded: &complianceExcluded
            )
        } else {
            try collectExcluded(from: spec, into: &complianceExcluded, skipSelf: true)
        }

        let planned = PathPlanner.plan(
            walls: walls,
            availableTools: availableTools,
            posixNames: BaseBinFolder.posixNames,
            selfCLIName: selfName
        )

        var finalExcluded = planned.excluded
        for ex in complianceExcluded where !finalExcluded.contains(ex) {
            finalExcluded.append(ex)
        }

        let (freshLinks, staleTools) = filterFreshLinks(plannedLinks: planned.links, spec: spec, finalExcluded: &finalExcluded)

        return RoomBinPlan(links: freshLinks, excluded: finalExcluded, staleTools: staleTools)
    }

    private static func initialTools(baseBin: URL, selfName: String, spec: RoomAssemblySpec) throws -> [String: String] {
        var tools: [String: String] = [:]
        for name in BaseBinFolder.posixNames {
            tools[name] = baseBin.appendingPathComponent(name).path
        }
        if try spec.compliance.isCompliant(cli: selfName) {
            tools[selfName] = baseBin.appendingPathComponent(selfName).path
        }
        return tools
    }

    private static func filterFreshLinks(
        plannedLinks: [(name: String, destination: String)],
        spec: RoomAssemblySpec,
        finalExcluded: inout [String]
    ) -> (fresh: [(name: String, destination: String)], stale: [String]) {
        var freshLinks: [(name: String, destination: String)] = []
        var staleTools: [String] = []

        for link in plannedLinks {
            if BaseBinFolder.posixNames.contains(link.name) {
                freshLinks.append(link)
                continue
            }
            evaluateLinkStaleness(link: link, spec: spec, freshLinks: &freshLinks, staleTools: &staleTools, finalExcluded: &finalExcluded)
        }
        return (freshLinks, staleTools)
    }

    private static func evaluateLinkStaleness(
        link: (name: String, destination: String),
        spec: RoomAssemblySpec,
        freshLinks: inout [(name: String, destination: String)],
        staleTools: inout [String],
        finalExcluded: inout [String]
    ) {
        let checkResult = spec.sourceHashGate.checkSourceHash(cli: link.name, destination: link.destination)
        guard checkResult.isStale else {
            freshLinks.append(link)
            return
        }
        appendStaleTool(link.name, staleTools: &staleTools, finalExcluded: &finalExcluded)
    }

    private static func appendStaleTool(_ name: String, staleTools: inout [String], finalExcluded: inout [String]) {
        if !staleTools.contains(name) { staleTools.append(name) }
        if !finalExcluded.contains(name) { finalExcluded.append(name) }
    }

    private static func collectExcluded(
        from spec: RoomAssemblySpec,
        into excluded: inout [String],
        skipSelf: Bool = false
    ) throws {
        if !skipSelf {
            try appendIfNonCompliant(cli: BaseBinFolder.selfCLIName, spec: spec, into: &excluded)
        }
        for name in spec.blueprint.toolbelt where name != BaseBinFolder.selfCLIName {
            try appendIfNonCompliant(cli: name, spec: spec, into: &excluded)
        }
    }

    private static func appendIfNonCompliant(cli: String, spec: RoomAssemblySpec, into excluded: inout [String]) throws {
        guard try !spec.compliance.isCompliant(cli: cli), !excluded.contains(cli) else { return }
        excluded.append(cli)
    }

    private static func populateToolbeltAndHelpers(
        spec: RoomAssemblySpec,
        pathEnv: String,
        selfName: String,
        availableTools: inout [String: String],
        complianceExcluded: inout [String]
    ) throws {
        try populateToolbelt(
            spec: spec,
            pathEnv: pathEnv,
            selfName: selfName,
            availableTools: &availableTools,
            complianceExcluded: &complianceExcluded
        )
        populateAgentToolsAndHelpers(spec: spec, pathEnv: pathEnv, availableTools: &availableTools)
    }

    private static func populateToolbelt(
        spec: RoomAssemblySpec,
        pathEnv: String,
        selfName: String,
        availableTools: inout [String: String],
        complianceExcluded: inout [String]
    ) throws {
        for name in spec.blueprint.toolbelt {
            if name == selfName { continue }
            guard try spec.compliance.isCompliant(cli: name) else {
                if !complianceExcluded.contains(name) { complianceExcluded.append(name) }
                continue
            }
            guard let dest = BinaryLocator.find(name, path: pathEnv) else {
                throw RoomAssemblyError.toolNotFound(name)
            }
            availableTools[name] = dest
        }
    }

    private static func populateAgentToolsAndHelpers(
        spec: RoomAssemblySpec,
        pathEnv: String,
        availableTools: inout [String: String]
    ) {
        for name in spec.blueprint.agentTools {
            guard let dest = BinaryLocator.find(name, path: pathEnv) else { continue }
            availableTools[name] = dest
        }
        let allHelpers = PathPlanner.agentHelpers.values.flatMap { $0 }
        for helper in allHelpers {
            guard let dest = BinaryLocator.find(helper, path: pathEnv) else { continue }
            availableTools[helper] = dest
        }
    }
}

public enum TimingConfig {
    public static let defaultProbeTimeout: TimeInterval = 5.0
}

public enum StaleInstallProbe {
    public static let warningMarker = "설치본이 소스보다 낡았습니다"
    public static let timeout: TimeInterval = TimingConfig.defaultProbeTimeout

    public static func isStaleByProbe(destination: String) -> Bool {
        let result = CommandKitSync.run(
            destination,
            ["capabilities", "--json"],
            timeout: timeout
        )
        guard result.ok else { return false }
        return hasWarning(in: result.stdout) || hasWarning(in: result.stderr)
    }

    public static func names(in links: [(name: String, destination: String)]) -> [String] {
        var stale: [String] = []
        for link in links {
            if isStaleByProbe(destination: link.destination) {
                if !stale.contains(link.name) {
                    stale.append(link.name)
                }
            }
        }
        return stale
    }

    public static func hasWarning(in output: String) -> Bool {
        let head: Substring
        if let jsonStart = output.firstIndex(where: { $0 == "{" || $0 == "[" }) {
            head = output[..<jsonStart]
        } else {
            head = output.prefix(512)
        }
        return head.contains(warningMarker)
    }
}

enum RoomBinFolder {
    static func apply(plan: RoomBinPlan, at binURL: URL) throws {
        let fm = FileManager()
        try fm.createDirectory(at: binURL, withIntermediateDirectories: true)
        let desired = Set(plan.links.map(\.name))
        let existing = try fm.contentsOfDirectory(atPath: binURL.path)
        for name in existing where !desired.contains(name) {
            try fm.removeItem(at: binURL.appendingPathComponent(name))
        }
        for link in plan.links {
            try replaceSymlink(
                at: binURL.appendingPathComponent(link.name),
                destination: link.destination
            )
        }
    }
}
