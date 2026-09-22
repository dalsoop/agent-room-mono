import Foundation

/// 세션 시작 시 터미널에 보여줄 4줄 안내문 (+ 종료 안내 줄).
public enum RoomBriefing {
    public static let exitNotice = "종료하려면 exit 를 입력하세요"

    public static func text(
        task: String,
        verdict: String,
        writePaths: [String],
        toolbelt: [String]
    ) -> String {
        let lines: [String] = [
            "작업: \(task)",
            "완료 조건: \(verdict)",
            "쓰기 가능: \(writePaths.joined(separator: ", "))",
            "도구: \(toolbelt.joined(separator: ", "))",
            exitNotice
        ]
        return lines.joined(separator: "\n")
    }

    public static func text(spec: RoomAssemblySpec) -> String {
        text(
            task: spec.blueprint.task,
            verdict: spec.blueprint.verdict,
            writePaths: spec.blueprint.walls.writePaths,
            toolbelt: spec.blueprint.toolbelt
        )
    }

    public static func text(node: RoomSummary) -> String {
        let task = node.title.isEmpty ? node.id : node.title
        let verdict = (node.status == .done) ? "완료됨" : "진행 중"
        let paths = [node.id]
        let tools = [node.wallPreset]
        return text(
            task: task,
            verdict: verdict,
            writePaths: paths,
            toolbelt: tools
        )
    }
}
