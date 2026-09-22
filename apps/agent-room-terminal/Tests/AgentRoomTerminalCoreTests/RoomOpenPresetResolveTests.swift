import Testing
@testable import AgentRoomTerminalCore

@Suite("RoomOpenPipeline.resolvePreset — 설계도 open 을 toolbelt 로 강등하지 않는다")
struct RoomOpenPresetResolveTests {
    @Test func blueprintOpenStaysOpen() {
        #expect(RoomOpenPipeline.resolvePreset(flag: nil, blueprint: "open") == .open)
    }

    @Test func flagWinsOverBlueprint() {
        #expect(RoomOpenPipeline.resolvePreset(flag: "readOnly", blueprint: "open") == .readOnly)
        #expect(RoomOpenPipeline.resolvePreset(flag: "open", blueprint: "toolbelt") == .open)
    }

    @Test func unknownBlueprintDefaultsToToolbelt() {
        #expect(RoomOpenPipeline.resolvePreset(flag: nil, blueprint: "mystery") == .toolbelt)
    }
}
