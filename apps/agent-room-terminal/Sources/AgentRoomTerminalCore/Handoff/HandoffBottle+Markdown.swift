import Foundation

extension HandoffBottle {
    /// 후임이 빈병을 사람 눈으로 읽기 위한 요약. 결론 → 문서 → 산출물 → 명령 → 함정 → 습관.
    public func markdownSummary() -> String {
        let conclusion: String
        if lastAssistantText.isEmpty {
            conclusion = note.isEmpty ? "없음" : note
        } else {
            conclusion = lastAssistantText
        }
        var lines: [String] = []
        lines.append("## 결론")
        lines.append("")
        lines.append(conclusion)
        lines.append("")
        lines.append("## 읽은 문서")
        lines.append("")
        lines.append(contentsOf: bullets(readDocuments))
        lines.append("")
        lines.append("## 만든 파일")
        lines.append("")
        lines.append(contentsOf: bullets(producedFiles))
        lines.append("")
        lines.append("## 실행한 명령")
        lines.append("")
        lines.append(contentsOf: bullets(executedCommands))
        lines.append("")
        lines.append("## 함정")
        lines.append("")
        lines.append(contentsOf: bullets(pitfalls))
        lines.append("")
        lines.append("## 습관 후보")
        lines.append("")
        lines.append(contentsOf: bullets(habitCandidates.map(\.invocation)))
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func bullets(_ items: [String]) -> [String] {
        if items.isEmpty { return ["- 없음"] }
        return items.map { "- \($0)" }
    }
}
