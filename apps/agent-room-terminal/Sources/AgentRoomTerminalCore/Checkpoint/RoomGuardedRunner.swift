import Foundation

/// 가드 러너 실행 결과 모델.
public struct RoomExecutionResult: Sendable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int
    public var violations: [String]

    public init(stdout: String = "", stderr: String = "", exitCode: Int = 0, violations: [String] = []) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.violations = violations
    }
}

/// 방 `work/` 체크포인트 보호 아래 작업을 실행하고, 실패/위반 시 롤백하며 `runs/<id>/` 증거를 보존하는 러너.
public final class RoomGuardedRunner: Sendable {
    public static let shared = RoomGuardedRunner()

    private let checkpointManager: RoomCheckpointManager

    public init(checkpointManager: RoomCheckpointManager = .shared) {
        self.checkpointManager = checkpointManager
    }

    /// 방 `runs/` 폴더 위치: `<roomURL>/runs/`
    public func runsDirectory(in roomURL: URL) -> URL {
        roomURL.appendingPathComponent("runs", isDirectory: true)
    }

    /// 보호된 실행을 수행한다.
    public func execute(
        roomURL: URL,
        argv: [String],
        runID: String? = nil,
        preCheckpointDescription: String? = "pre-run snapshot",
        verifyHook: (@Sendable () throws -> [String])? = nil,
        execution: () throws -> RoomExecutionResult
    ) throws -> RoomRunEvidence {
        let fm = FileManager()
        let id = runID ?? "run-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
        let runDir = runsDirectory(in: roomURL).appendingPathComponent(id, isDirectory: true)
        let evidenceDir = runDir.appendingPathComponent("evidence", isDirectory: true)

        try fm.createDirectory(at: evidenceDir, withIntermediateDirectories: true)

        let startedAt = Date()
        let preCkpt = try checkpointManager.createCheckpoint(
            roomURL: roomURL,
            checkpointID: "ckpt-before-\(id)",
            description: preCheckpointDescription
        )

        let execResult = try execution()
        let endedAt = Date()
        let durationMs = Int(endedAt.timeIntervalSince(startedAt) * 1000)

        var violations = execResult.violations
        let (verdict, passedVerifications) = determineVerdict(
            violations: &violations,
            exitCode: execResult.exitCode,
            verifyHook: verifyHook
        )

        let (rolledBack, postCkptID) = try handleCheckpointRollbackOrSave(
            verdict: verdict,
            roomURL: roomURL,
            preCkptID: preCkpt.id,
            id: id
        )

        saveRunEvidenceFiles(
            runDir: runDir,
            evidenceDir: evidenceDir,
            execResult: execResult,
            passedVerifications: passedVerifications
        )

        let evidence = RoomRunEvidence(
            runID: id,
            roomID: roomURL.lastPathComponent,
            startedAt: startedAt,
            endedAt: endedAt,
            durationMs: durationMs,
            argv: argv,
            exitCode: execResult.exitCode,
            verdict: verdict,
            checkpointIDBefore: preCkpt.id,
            checkpointIDAfter: postCkptID,
            rolledBack: rolledBack,
            stdoutSummary: String(execResult.stdout.prefix(500)),
            stderrSummary: String(execResult.stderr.prefix(500)),
            violations: violations,
            passedVerifications: passedVerifications
        )

        try saveMetadata(evidence: evidence, runDir: runDir)
        return evidence
    }

    private func determineVerdict(
        violations: inout [String],
        exitCode: Int,
        verifyHook: (@Sendable () throws -> [String])?
    ) -> (verdict: RunVerdict, passedVerifications: [String]) {
        if !violations.isEmpty {
            return (.policyViolated, [])
        }
        guard exitCode == 0 else {
            return (.failed, [])
        }
        guard let verifyHook else {
            return (.passed, [])
        }
        do {
            let passed = try verifyHook()
            return (.passed, passed)
        } catch {
            violations.append("verification failed: \(error.localizedDescription)")
            return (.failed, [])
        }
    }

    private func handleCheckpointRollbackOrSave(
        verdict: RunVerdict,
        roomURL: URL,
        preCkptID: String,
        id: String
    ) throws -> (rolledBack: Bool, postCkptID: String?) {
        guard verdict == .passed else {
            try checkpointManager.rollback(roomURL: roomURL, to: preCkptID)
            return (true, nil)
        }
        let postCkpt = try checkpointManager.createCheckpoint(
            roomURL: roomURL,
            checkpointID: "ckpt-after-\(id)",
            description: "post-run passed verification snapshot"
        )
        return (false, postCkpt.id)
    }

    private func saveRunEvidenceFiles(
        runDir: URL,
        evidenceDir: URL,
        execResult: RoomExecutionResult,
        passedVerifications: [String]
    ) {
        let stdoutURL = runDir.appendingPathComponent("stdout.log")
        let stderrURL = runDir.appendingPathComponent("stderr.log")

        do {
            try execResult.stdout.write(to: stdoutURL, atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("write stdout error: \(error)\n".utf8))
        }

        do {
            try execResult.stderr.write(to: stderrURL, atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("write stderr error: \(error)\n".utf8))
        }

        guard !passedVerifications.isEmpty else { return }
        let verifURL = evidenceDir.appendingPathComponent("passed_verifications.json")
        do {
            let verifData = try JSONEncoder().encode(passedVerifications)
            try verifData.write(to: verifURL, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("write verifications error: \(error)\n".utf8))
        }
    }

    private func saveMetadata(evidence: RoomRunEvidence, runDir: URL) throws {
        let metaURL = runDir.appendingPathComponent("meta.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metaData = try encoder.encode(evidence)
        try metaData.write(to: metaURL, options: .atomic)
    }

    /// 방의 모든 실행(runs) 증거 기록을 최신순으로 반환한다.
    public func listRuns(in roomURL: URL) throws -> [RoomRunEvidence] {
        let fm = FileManager()
        let runsDir = runsDirectory(in: roomURL)
        guard fm.fileExists(atPath: runsDir.path) else { return [] }

        let subdirs = try fm.contentsOfDirectory(at: runsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var results: [RoomRunEvidence] = []
        let decoder = JSONDecoder()

        for dir in subdirs {
            let metaURL = dir.appendingPathComponent("meta.json")
            guard fm.fileExists(atPath: metaURL.path) else { continue }
            do {
                let data = try Data(contentsOf: metaURL)
                let item = try decoder.decode(RoomRunEvidence.self, from: data)
                results.append(item)
            } catch {
                continue
            }
        }

        return results.sorted { $0.startedAt > $1.startedAt }
    }

    /// 특정 실행 증거를 읽는다.
    public func getRun(in roomURL: URL, runID: String) throws -> RoomRunEvidence? {
        let fm = FileManager()
        let metaURL = runsDirectory(in: roomURL)
            .appendingPathComponent(runID, isDirectory: true)
            .appendingPathComponent("meta.json")
        guard fm.fileExists(atPath: metaURL.path) else { return nil }
        let data = try Data(contentsOf: metaURL)
        return try JSONDecoder().decode(RoomRunEvidence.self, from: data)
    }
}
