import Foundation
import SessionKit
import AgentSessionKit

/// Gemini(agy) 세션 저장소로부터 사용량을 측정(추정)한다.
/// 목록 DB: `conversation_summaries.db`
/// 전사 DB: `conversations/<id>.db`
///
/// agy 는 세션 토큰 수가 별도 로깅되지 않으므로, 에이전트 발언 및 사용자 입력
/// step 의 바이트 수/step 수를 기반으로 토큰 추정치를 내고 `estimated: true` 로 표기한다.
/// 요청 수(requests)는 실제 사용자 발언 및 턴 수를 센다.
public struct AgyUsageAdapter: UsageAdapter, Sendable {
    public var tool: AgentRoomTool { .agy }
    public var workdir: String?

    public init(workdir: String? = nil) {
        self.workdir = workdir
    }

    public func measure(file: URL) -> UsageReading {
        guard let rootPath = resolveRoot(from: file) else {
            return .unknown(tool: tool)
        }
        let reader = AntigravitySessionReader(root: rootPath)
        guard FileManager.default.fileExists(atPath: reader.summariesDBPath) else {
            // summaries.db 가 없어도 단일 conversation db 파일이라면 그 파일을 직접 측정한다.
            if file.pathExtension == "db" && file.lastPathComponent != "conversation_summaries.db" {
                return measureSingleDB(file: file, reader: reader)
            }
            return .unknown(tool: tool)
        }

        let allSessions = reader.discover()
        let matchedSessions: [SessionRef]
        if let workdir {
            matchedSessions = allSessions.filter { session in
                Self.matchesWorkdir(sessionCWD: session.cwd, targetWorkdir: workdir)
            }
        } else {
            matchedSessions = allSessions
        }

        if matchedSessions.isEmpty {
            // DB 파일은 정상 존재하나 매칭되는 작업공간 세션이 없는 경우:
            // 0 으로 계측하되 unknown 은 아니다 (다른 workdir -> 0).
            return UsageReading(
                tool: tool,
                inputTokens: 0,
                outputTokens: 0,
                requests: 0,
                unknown: false,
                estimated: true
            )
        }

        var totalInputTokens = 0
        var totalOutputTokens = 0
        var totalRequests = 0

        for session in matchedSessions {
            let (input, output, reqs) = measureSession(session, reader: reader)
            totalInputTokens += input
            totalOutputTokens += output
            totalRequests += reqs
        }

        return UsageReading(
            tool: tool,
            inputTokens: totalInputTokens,
            outputTokens: totalOutputTokens,
            requests: totalRequests,
            unknown: false,
            estimated: true
        )
    }

    private func measureSession(_ session: SessionRef, reader: AntigravitySessionReader) -> (inputTokens: Int, outputTokens: Int, requests: Int) {
        let steps = reader.steps(session)
        let digest = reader.digest(session)

        let userCount = digest.userMessages.count
        let agentCount = digest.agentMessages.count

        let userBytes = digest.userMessages.reduce(0) { $0 + $1.utf8.count }
        let agentBytes = digest.agentMessages.reduce(0) { $0 + $1.utf8.count }

        let raw14Count = steps.filter { $0.type == 14 }.count
        let raw15Count = steps.filter { $0.type == 15 }.count
        let raw132Count = steps.filter { $0.type == 132 }.count

        // requests: 사용자 발언 횟수 또는 턴 수
        let requests: Int
        if userCount > 0 {
            requests = userCount
        } else if raw14Count > 0 {
            requests = max(1, raw14Count / 2) // type 14 는 실측상 2중 저장
        } else if agentCount > 0 {
            requests = agentCount
        } else if raw15Count > 0 {
            requests = raw15Count
        } else if !steps.isEmpty {
            requests = 1
        } else {
            requests = 0
        }

        // 토큰 추정치:
        // inputTokens: 사용자 발언 바이트 수 기반 (한글/영문 감안 바이트/4 및 최소 발언당 1)
        // outputTokens: 에이전트 발언 바이트 수 및 도구 호출 기반
        let inputTokens = max(requests, userBytes / 4)
        let outputTokens = max(max(agentCount, raw15Count), agentBytes / 4 + raw132Count * 10)

        return (inputTokens, outputTokens, requests)
    }

    private func measureSingleDB(file: URL, reader: AntigravitySessionReader) -> UsageReading {
        let ref = SessionRef(
            tool: .agy,
            id: file.deletingPathExtension().lastPathComponent,
            cwd: workdir ?? "",
            title: nil,
            lastActive: .now,
            path: file.path,
            messageCount: 0
        )
        let steps = reader.steps(ref)
        if steps.isEmpty {
            return .unknown(tool: tool)
        }
        let (input, output, reqs) = measureSession(ref, reader: reader)
        return UsageReading(
            tool: tool,
            inputTokens: input,
            outputTokens: output,
            requests: reqs,
            unknown: false,
            estimated: true
        )
    }

    private func resolveRoot(from file: URL) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue {
            return file.path
        }
        if file.lastPathComponent == "conversation_summaries.db" {
            return file.deletingLastPathComponent().path
        }
        if file.pathExtension == "db" {
            let parent = file.deletingLastPathComponent()
            if parent.lastPathComponent == "conversations" {
                return parent.deletingLastPathComponent().path
            }
            return parent.path
        }
        return nil
    }

    public static func matchesWorkdir(sessionCWD: String, targetWorkdir: String) -> Bool {
        let s = URL(fileURLWithPath: sessionCWD).standardized.path
        let t = URL(fileURLWithPath: targetWorkdir).standardized.path
        if s == t { return true }
        let sResolved = URL(fileURLWithPath: sessionCWD).resolvingSymlinksInPath().standardized.path
        let tResolved = URL(fileURLWithPath: targetWorkdir).resolvingSymlinksInPath().standardized.path
        return sResolved == tResolved
    }
}
