import Foundation
import RoomKit

/// profile-then-lock 으로 자동 도출된 방 벽 초안.
public struct RoomWallDraft: Codable, Equatable, Sendable {
    public var walls: RoomWalls
    public var suggestedPreset: RoomWallPreset
    public var violations: [TenantViolation]
    public var summary: String
    public var footprint: ExecutionFootprint

    public init(
        walls: RoomWalls,
        suggestedPreset: RoomWallPreset,
        violations: [TenantViolation] = [],
        summary: String = "",
        footprint: ExecutionFootprint
    ) {
        self.walls = walls
        self.suggestedPreset = suggestedPreset
        self.violations = violations
        self.summary = summary
        self.footprint = footprint
    }

    /// 초안을 마크다운 문서로 변환한다.
    public func markdownReport() -> String {
        var doc = """
        # 방 벽 초안 (Profile-Then-Lock Draft)

        - 추천 프리셋: `\(suggestedPreset.rawValue)`
        - 관찰된 명령: `\(footprint.argv.joined(separator: " "))`
        - 실행 결과: exit code \(footprint.exitCode), \(footprint.durationMs)ms

        ## 파일 쓰기 허용 (\(walls.filesystem.allowWrite.count)개)
        """
        if walls.filesystem.allowWrite.isEmpty {
            doc += "\n- (없음: 읽기 전용)"
        } else {
            for path in walls.filesystem.allowWrite {
                doc += "\n- `\(path)`"
            }
        }

        doc += "\n\n## 네트워크 벽: `\(walls.network)`"

        switch walls.executables {
        case .hostPath:
            doc += "\n\n## 실행 도구: 호스트 PATH 전체"
        case .allowList(let list):
            doc += "\n\n## 실행 도구 허용 목록 (\(list.count)개)\n"
            for exe in list {
                doc += "- `\(exe)`\n"
            }
        }

        if !violations.isEmpty {
            doc += "\n## ⚠️ 정책/테넌트 위반 지점 (\(violations.count)건)\n"
            for v in violations {
                doc += "- [\(v.operation)] `\(v.path)`: \(v.reason)\n"
            }
        }

        return doc
    }
}
