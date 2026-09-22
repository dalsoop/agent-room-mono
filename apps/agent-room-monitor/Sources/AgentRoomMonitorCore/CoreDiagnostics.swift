import Foundation

/// Core 저장소들이 실패를 **삼키지 않고** 알리는 한 줄 출구. 파일 조작이 실패하면 후속
/// 로직이 없는 파일을 전제로 돌기 쉬워, 빈 결과를 돌려주더라도 stderr 에 이유를 남긴다.
/// GUI·CLI 어느 표면에서 돌든 같은 채널이다(stdout 은 CLI `--json` 계약이라 건드리지 않는다).
enum CoreDiagnostics {
    static func warn(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
