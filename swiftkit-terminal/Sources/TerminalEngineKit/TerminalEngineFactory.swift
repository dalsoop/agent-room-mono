import Foundation

/// 지원하는 터미널 렌더러 엔진 종류
public enum TerminalEngineKind: String, Sendable, CaseIterable {
    case swiftTerm
    case ghostty
    case mock
}

/// 터미널 엔진 인스턴스를 선택 및 생성하는 중앙 팩토리.
@MainActor
public final class TerminalEngineFactory {
    public typealias Kind = TerminalEngineKind
    public typealias Creator = @MainActor (TerminalLaunch) -> any TerminalEngine

    private static var creators: [TerminalEngineKind: Creator] = [
        .mock: { _ in MockTerminalEngine() }
    ]

    public static var defaultKind: TerminalEngineKind = .ghostty

    /// 특정 엔진 종류의 생성 클로저를 등록한다.
    public static func register(_ kind: TerminalEngineKind, creator: @escaping Creator) {
        creators[kind] = creator
    }

    /// 엔진 종류가 등록되어 있는지 확인한다.
    public static func isRegistered(_ kind: TerminalEngineKind) -> Bool {
        creators[kind] != nil
    }

    /// 지정된 엔진 종류 및 실행 설정으로 터미널 엔진을 생성한다.
    public static func make(kind: TerminalEngineKind = defaultKind, launch: TerminalLaunch) -> any TerminalEngine {
        if let creator = creators[kind] {
            return creator(launch)
        }
        return MockTerminalEngine()
    }

    /// `make(kind:launch:)` 별칭
    public static func create(kind: TerminalEngineKind = defaultKind, launch: TerminalLaunch) -> any TerminalEngine {
        make(kind: kind, launch: launch)
    }
}
