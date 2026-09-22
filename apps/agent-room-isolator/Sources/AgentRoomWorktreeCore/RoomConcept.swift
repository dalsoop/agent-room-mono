import Foundation

/// 방 개념 최소 검증 — work-todo 헌법의 task·verdict 규칙과 같은 뜻.
public enum RoomConcept {
    static let trivialVerify: Set<String> = ["true", ":", "exit 0", "echo ok"]

    public static func validate(task: String, verify: String) throws {
        let taskTrim = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !taskTrim.isEmpty else { throw AgentRoomWorktreeError.taskEmpty }
        let verifyTrim = verify.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = verifyTrim.lowercased()
        if verifyTrim.isEmpty || trivialVerify.contains(normalized) {
            throw AgentRoomWorktreeError.trivialVerify(verifyTrim)
        }
    }

    /// 워크트리·브랜치 이름. 한글 task 는 fallback 으로 떨어진다.
    public static func slug(from task: String, fallback: String) -> String {
        let lowered = task.lowercased()
        var chars: [Character] = []
        var dash = false
        for ch in lowered {
            let asciiLetter = ch.isLetter && ch.isASCII
            if asciiLetter || ch.isNumber {
                chars.append(ch)
                dash = false
            } else if !dash && !chars.isEmpty {
                chars.append("-")
                dash = true
            }
        }
        while chars.last == "-" { chars.removeLast() }
        let raw = String(chars)
        if raw.count >= 2 { return String(raw.prefix(48)) }
        let fb = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return fb.isEmpty ? "room" : fb
    }
}
