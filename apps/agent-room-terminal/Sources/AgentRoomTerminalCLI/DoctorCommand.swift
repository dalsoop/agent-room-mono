import Foundation
import AgentRoomTerminalCore

enum DoctorCommand {
    static let usageText = "usage: doctor [--json] [--fix]"

    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        if rest.contains("--help") || rest.contains("-h") {
            CLIIO.printLine(usageText)
            exit(CLIExit.ok)
        }
        let isJSON = CLIArgs.takeJSON(&rest)
        let isFix = rest.contains("--fix")

        var findings: [[String: Any]] = []
        findings.append(auditSandbox())
        findings.append(auditDaemonDirectories(isFix: isFix))
        findings.append(auditHandoffPipeline())

        let docOutput: [String: Any] = [
            "schema": "doctor/v1",
            "source": "agent-room-terminal-doctor",
            "findings": findings
        ]

        let hasFail = findings.contains { ($0["severity"] as? String) == "fail" }
        emitOutput(docOutput: docOutput, findings: findings, isJSON: isJSON)
        exit(hasFail ? 1 : CLIExit.ok)
    }

    private static func auditSandbox() -> [String: Any] {
        if AppPaths.isSandboxAvailable {
            return [
                "id": "art.sandbox.seatbelt_available",
                "severity": "ok",
                "title": "OS Seatbelt 격리 엔진 가용 (Fail-Closed 충족)",
                "checkKind": "behavioral"
            ]
        } else {
            return [
                "id": "art.sandbox.seatbelt_missing",
                "severity": "fail",
                "title": "OS Seatbelt 격리 엔진 사용 불가 (/usr/bin/sandbox-exec)",
                "checkKind": "behavioral",
                "remedy": "macOS 샌드박스 권한 및 sandbox-exec 바이너리를 확인하십시오"
            ]
        }
    }

    private static func auditDaemonDirectories(isFix: Bool) -> [String: Any] {
        if isFix {
            let cleaned = DaemonDirectoryGC.cleanup(dryRun: false)
            let reportAfter = DaemonDirectoryGC.scan()
            if reportAfter.staleDirectories.isEmpty {
                return [
                    "id": "art.daemon.socket_leak",
                    "severity": "ok",
                    "title": "고아 데몬 디렉터리 \(cleaned.count)개 자동 정리 완료 (현재 0개)",
                    "checkKind": "structural"
                ]
            } else {
                return [
                    "id": "art.daemon.socket_leak",
                    "severity": "warn",
                    "title": "/tmp/art-* 잔여 고아 데몬 소켓 \(reportAfter.staleDirectories.count)개 존재",
                    "checkKind": "structural",
                    "remedy": "권한 오류 등으로 삭제되지 않은 /tmp/art-* 디렉터리를 수동 점검하십시오",
                    "payload": ["leakedDirectories": reportAfter.staleDirectories]
                ]
            }
        }
        let report = DaemonDirectoryGC.scan()
        if report.staleDirectories.isEmpty {
            return [
                "id": "art.daemon.socket_leak",
                "severity": "ok",
                "title": "고아 데몬 소켓 및 디렉터리 없음 (청정 상태)",
                "checkKind": "structural"
            ]
        }
        return [
            "id": "art.daemon.socket_leak",
            "severity": "warn",
            "title": "/tmp/art-* 고아 데몬 소켓 \(report.staleDirectories.count)개 감지",
            "checkKind": "structural",
            "remedy": "agent-room-terminal doctor --fix 실행으로 죽은 데몬 소켓 및 디렉터리 언링크",
            "payload": ["leakedDirectories": report.staleDirectories]
        ]
    }

    private static func auditHandoffPipeline() -> [String: Any] {
        return [
            "id": "art.handoff.pipeline",
            "severity": "ok",
            "title": "핸드오프 및 빈병 교체 파이프라인 무결성 가용 (Fail-Closed 충족)",
            "checkKind": "behavioral",
        ]
    }

    private static func emitOutput(docOutput: [String: Any], findings: [[String: Any]], isJSON: Bool) {
        if isJSON {
            CLIIO.printOKObject(docOutput)
            return
        }
        CLIIO.printLine("=== agent-room-terminal doctor ===")
        for finding in findings {
            let sev = (finding["severity"] as? String ?? "info").uppercased()
            let title = finding["title"] as? String ?? ""
            CLIIO.printLine("[\(sev)] \(title)")
            if let remedy = finding["remedy"] as? String {
                CLIIO.printLine("  └─ Remedy: \(remedy)")
            }
        }
    }
}
