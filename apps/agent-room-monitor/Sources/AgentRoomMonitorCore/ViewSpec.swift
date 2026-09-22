import Foundation
import LocalizationKit

/// 보드 뷰 정의 — 상황별 다각형 뷰를 코드가 아니라 **데이터(JSON)** 로 관리한다.
/// 정본 디렉터리: `~/.agent-room-monitor/views/*.json`. GUI 메뉴와 CLI(`views --json`)가
/// 같은 파일을 읽는다. 파일을 추가·수정하면 앱 재시작 없이 다음 새로고침에 반영된다.
public struct ViewSpec: Codable, Identifiable, Sendable, Equatable {
    /// 표시 필터 — 비운 필드는 제한 없음.
    public struct Filter: Codable, Sendable, Equatable {
        /// TwinKind rawValue 목록 (예: ["room","seat"]). zone 컨테이너에는 적용하지 않는다.
        public var kinds: [String]?
        /// TwinState rawValue 목록 (예: ["block","gate"]).
        public var states: [String]?
        /// 생성 시각이 이 시간 안쪽인 노드만. (활동 시각이 아니라 **생성** 기준 — 정직한 이름)
        public var bornWithinHours: Double?

        public init(kinds: [String]? = nil, states: [String]? = nil, bornWithinHours: Double? = nil) {
            self.kinds = kinds
            self.states = states
            self.bornWithinHours = bornWithinHours
        }
    }

    public var id: String
    /// 언어코드 → 표시명 (예: ["en": "Zone map"]). 시드 뷰는 영어만 담고 나머지 언어는
    /// L10n 카탈로그(`ViewSpec.seed.<id>`)가 댄다 — 화면 한글을 코드에 박지 않는다.
    public var title: [String: String]
    /// 묶음 축: "zone" | "harness" | "runtime".
    public var groupBy: String
    /// 이 뷰의 뿌리 노드 id — nil 이면 호스트 전체.
    public var rootID: String?
    public var filter: Filter?
    /// 메뉴 정렬 순서 (작을수록 위).
    public var order: Int?

    public init(
        id: String,
        title: [String: String],
        groupBy: String,
        rootID: String? = nil,
        filter: Filter? = nil,
        order: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.groupBy = groupBy
        self.rootID = rootID
        self.filter = filter
        self.order = order
    }

    /// 관용 디코딩 — id 만 필수. 손으로 쓴 JSON 이 필드를 빠뜨려도 살아남는다.
    /// 타입이 틀린 필드는 삼키지 않고 throw — 그 파일 하나만 `ViewSpecStore.load` 가 건너뛴다.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent([String: String].self, forKey: .title) ?? [:]
        groupBy = try c.decodeIfPresent(String.self, forKey: .groupBy) ?? "zone"
        rootID = try c.decodeIfPresent(String.self, forKey: .rootID)
        filter = try c.decodeIfPresent(Filter.self, forKey: .filter)
        order = try c.decodeIfPresent(Int.self, forKey: .order)
    }

    /// 표시명 — 파일에 적힌 언어 → 시드 L10n 키 → 영어 → 아무 언어 → id 순.
    public func displayTitle(language: String) -> String {
        if let explicit = title[language] { return explicit }
        if let seeded = Self.localizedSeedTitle(id: id) { return seeded }
        return title["en"] ?? title.values.sorted().first ?? id
    }

    /// 시드 뷰의 현재 언어 표시명. 카탈로그에 키가 없으면 nil(키 누락 시 키를 그대로 돌려주는
    /// LocalizationKit 계약을 이용한다) — 사용자가 만든 뷰 id 는 여기 걸리지 않는다.
    static func localizedSeedTitle(id: String) -> String? {
        let key = "ViewSpec.seed.\(id)"
        let value = CLILocalization.string(key)
        return value == key ? nil : value
    }
}

/// 뷰 정의 저장소 — 디렉터리가 비어 있으면 기본 뷰를 시드한다(이후 SSOT 는 디스크).
public struct ViewSpecStore: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        // 자기 상태 — 테넌트 컨텍스트가 있으면 `~/.tenants/<t>/.agent-room-monitor/views`.
        self.directory = directory ?? AppPaths.stateSubdirectory(AppPaths.viewsDirectoryName)
    }

    private var fm: FileManager { .default }

    /// 앱이 처음 심는 기본 뷰들 — 시드 후에는 사용자가 파일로 고쳐 쓴다.
    /// 제목은 영어 정본만 데이터로 두고, 한국어 등은 `ViewSpec.seed.<id>` L10n 키가 댄다.
    public static let seedSpecs: [ViewSpec] = [
        ViewSpec(id: "zone-map", title: ["en": "Zone map"], groupBy: "zone", order: 0),
        ViewSpec(id: "harness-threads", title: ["en": "Harness threads"], groupBy: "harness", order: 1),
        ViewSpec(id: "runtime-threads", title: ["en": "Runtime threads"], groupBy: "runtime", order: 2),
        ViewSpec(
            id: "born-48h", title: ["en": "Born in 48h"], groupBy: "zone",
            filter: .init(bornWithinHours: 48), order: 3
        ),
        ViewSpec(
            id: "problems", title: ["en": "Problems & gates"], groupBy: "zone",
            filter: .init(states: ["block", "gate"]), order: 4
        ),
        ViewSpec(id: "lobby", title: ["en": "Lobby"], groupBy: "zone", rootID: "lobby", order: 5),
        ViewSpec(id: "archive", title: ["en": "Archive"], groupBy: "zone", rootID: "archive", order: 6),
        ViewSpec(id: "facilities", title: ["en": "Host facilities"], groupBy: "zone", rootID: "host-facilities", order: 7),
        ViewSpec(id: "warehouse", title: ["en": "Skill warehouse"], groupBy: "zone", rootID: "skill-warehouse", order: 8),
    ]

    /// 디렉터리를 보장하고, 비어 있으면 시드한 뒤, 전체를 (order, id) 순으로 읽는다.
    /// 깨진 파일은 건너뛴다 — 파일 하나가 전체 메뉴를 죽이면 안 된다.
    public func loadOrSeed() -> [ViewSpec] {
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            // 디렉터리를 못 만들면 시드도 못 쓴다 — 메모리 시드로 메뉴는 살리되 이유를 남긴다.
            CoreDiagnostics.warn("ViewSpecStore: cannot create \(directory.path): \(error.localizedDescription)")
            return Self.seedSpecs
        }
        if specFiles().isEmpty {
            seed()
        }
        return load()
    }

    private func specFiles() -> [URL] {
        let files: [URL]
        do {
            files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch {
            CoreDiagnostics.warn("ViewSpecStore: cannot list \(directory.path): \(error.localizedDescription)")
            return []
        }
        return files.filter { $0.pathExtension == "json" }
    }

    private func seed() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for spec in Self.seedSpecs {
            let url = directory.appendingPathComponent("\(spec.id).json")
            do {
                try encoder.encode(spec).write(to: url)
            } catch {
                CoreDiagnostics.warn("ViewSpecStore: cannot seed \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    private func load() -> [ViewSpec] {
        let specs = specFiles().compactMap { url -> ViewSpec? in
            do {
                return try JSONDecoder().decode(ViewSpec.self, from: Data(contentsOf: url))
            } catch {
                CoreDiagnostics.warn("ViewSpecStore: skipping \(url.lastPathComponent): \(error.localizedDescription)")
                return nil
            }
        }
        return specs.sorted { ($0.order ?? .max, $0.id) < ($1.order ?? .max, $1.id) }
    }
}
