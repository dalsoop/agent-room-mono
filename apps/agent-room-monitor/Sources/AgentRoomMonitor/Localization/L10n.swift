import Foundation

/// 앱의 사용자 노출 문자열 키. `CaseIterable` 이라 누락 검증 테스트가 전 키를 순회할 수 있다.
// 새 케이스를 추가하면 en.lproj / ko.lproj 의 Localizable.strings 에도 같은 키를 추가할 것.
enum L10nKey: String, CaseIterable {
    case menuRefresh = "menu.refresh"
    case menuSettings = "menu.settings"
    case menuQuit = "menu.quit"
    case settingsTitle = "settings.title"
    case settingsLanguage = "settings.language"
    case settingsLaunchAtLogin = "settings.launch_at_login"

    // 모드
    case modeNow = "mode.now"
    case modeTrace = "mode.trace"
    case modeDiff = "mode.diff"

    // 상태
    case stateExec = "state.exec"
    case stateDone = "state.done"
    case stateBlock = "state.block"
    case stateSleep = "state.sleep"
    case stateGate = "state.gate"
    case stateQueue = "state.queue"
    case stateNeutral = "state.neutral"

    // HUD
    case hudTitle = "hud.title"
    case hudSubtitle = "hud.subtitle"          // %@ = 스냅샷 시각
    case hudRunning = "hud.running"
    case hudBlocked = "hud.blocked"
    case hudGates = "hud.gates"
    case hudCPU = "hud.cpu"
    case hudCores = "hud.cores"                // %@ / %@코어
    case hudRAM = "hud.ram"
    case hudNet = "hud.net"
    case hudIntNet = "hud.int_net"
    case hudExtNet = "hud.ext_net"
    case hudReachFail = "hud.reach_fail"

    // 범례·하단 바
    case legendLine1 = "legend.line1"
    case legendLine2 = "legend.line2"
    case refreshBusy = "refresh.busy"
    case demoTitle = "demo.title"
    case demoAdd = "demo.add"
    case demoRemove = "demo.remove"

    // 시점(trace)
    case traceEmptyTitle = "trace.empty.title"
    case traceEmptyBody = "trace.empty.body"
    case traceScrubHint = "trace.scrub.hint"
    case traceTime = "trace.time"              // 시점 %@ / %@

    // 비교
    case compareTitle = "compare.title"
    case compareBody = "compare.body"

    // 레인
    case laneSpeech = "lane.speech"
    case laneTool = "lane.tool"
    case laneSubagent = "lane.subagent"
    case laneArtifact = "lane.artifact"
    case laneUncalled = "lane.uncalled"

    // 상세 패널
    case panelOccupant = "panel.occupant"
    case panelAppView = "panel.app_view"
    case panelNet = "panel.net"
    case panelNetExt = "panel.net.ext"
    case panelNetInt = "panel.net.int"
    case panelFlows = "panel.flows"
    case panelHealth = "panel.health"
    case panelSkills = "panel.skills"          // %d
    case panelAttachments = "panel.attachments"  // %d
    case panelCalls = "panel.calls"              // %d
    case lensZone = "lens.zone"
    case lensHarness = "lens.harness"
    case lensRuntime = "lens.runtime"
    case lensUnknown = "lens.unknown"
    // VIEW-SPEC-RESTORE-MARKER
    case viewMenu = "view.menu"
    case breadcrumbAll = "breadcrumb.all"
    case boardEnter = "board.enter"
    case boardEnterHelp = "board.enter_help"
    case chainRelay = "chain.relay"              // %@ = 노드, %d = 개수
    case panelChildren = "panel.children"      // %d
    case panelDecisions = "panel.decisions"
    case panelVerify = "panel.verify"
    case panelBlockedTimes = "panel.blocked_times"  // %d
    case panelHumanGate = "panel.human_gate"
    case panelContextNote = "panel.context_note"
    case panelHandoffTitle = "panel.handoff.title"
    case panelHandoffCmd = "panel.handoff.cmd"      // %@ = tool
    case panelPending = "panel.pending"
    case panelVault = "panel.vault"
    case panelCuratedArtifacts = "panel.curated_artifacts"
    case panelPromotionReceipt = "panel.promotion_receipt"
    case panelLocalSkills = "panel.local_skills"
    case panelVaultCurated = "panel.vault_curated"  // %d
    case panelVaultSkills = "panel.vault_skills"    // %d
    case panelVaultRaw = "panel.vault_raw"          // %lld

    // span 상세
    case spanUncalled = "span.uncalled"
    case spanDetail = "span.detail"
    case spanRealTitle = "span.real.title"
    case spanRealBody = "span.real.body"
    case spanTranscript = "span.transcript"

    case panelOperate = "panel.operate"
    case panelOccupy = "panel.occupy"
    case cardEmpty = "card.empty"
    case floorEmptyTitle = "floor.empty.title"
    case floorEmptyBody = "floor.empty.body"
    case isolationWho = "isolation.who"
    case isolationRoom = "isolation.room"
    case isolationTenant = "isolation.tenant"
    case isolationDomain = "isolation.domain"
    case isolationTools = "isolation.tools"
    case isolationWrites = "isolation.writes"
    case isolationNet = "isolation.net"
    case isolationNetOn = "isolation.net.on"
    case isolationNetOff = "isolation.net.off"
    case isolationNone = "isolation.none"
    case panelTick = "panel.tick"
    case panelDemolish = "panel.demolish"
    case panelOpenSkill = "panel.open_skill"
    case panelHandoffPack = "panel.handoff.pack"
    case panelHandoffResume = "panel.handoff.resume"
    case panelAX = "panel.ax"
    case panelAXLoad = "panel.ax.load"
    case panelDropSkill = "panel.drop_skill"
    case skillDragHelp = "skill.drag.help"

    case compareAdded = "compare.added"
    case compareRemoved = "compare.removed"
    case compareChanged = "compare.changed"

    case viewpointFirst = "viewpoint.first"
    case viewpointThird = "viewpoint.third"
    case tenantMenu = "tenant.menu"
    case tenantAll = "tenant.all"
    case tenantCurrent = "tenant.current"

    case boardZoomHelp = "board.zoom.help"
    case boardTiltHelp = "board.tilt.help"
    case boardYawHelp = "board.yaw.help"

    case newRoomTitle = "new_room.title"
    case newRoomHelp = "new_room.help"
    case newRoomHandle = "new_room.handle"
    case newRoomTask = "new_room.task"
    case newRoomVerify = "new_room.verify"
    case newRoomWorkdir = "new_room.workdir"
    case newRoomOccupant = "new_room.occupant"
    case newRoomTools = "new_room.tools"
    case newRoomWrites = "new_room.writes"
    case newRoomCancel = "new_room.cancel"
    case newRoomSubmit = "new_room.submit"

    case onboardingTitle = "onboarding.title"
    case onboardingSubtitle = "onboarding.subtitle"
    case onboardingSkip = "onboarding.skip"
    case onboardingFinish = "onboarding.finish"
    case onboardingFinishBlocked = "onboarding.finish_blocked"
    case onboardingDefaultsTitle = "onboarding.defaults.title"
    case onboardingDefaultsBody = "onboarding.defaults.body"
    case onboardingRequiredTitle = "onboarding.required.title"
    case onboardingRequiredBody = "onboarding.required.body"
    case onboardingRequiredAction = "onboarding.required.action"
    case SnapshotBuilder_ZonesName = "SnapshotBuilder+Zones.name"
    case SnapshotBuilder_ZonesName_2 = "SnapshotBuilder+Zones.name-2"
    case SnapshotBuilder_ZonesName_3 = "SnapshotBuilder+Zones.name-3"
    case SnapshotBuilder_ZonesName_4 = "SnapshotBuilder+Zones.name-4"
    case SnapshotBuilder_ZonesName_5 = "SnapshotBuilder+Zones.name-5"
    case SnapshotBuilder_ZonesName_6 = "SnapshotBuilder+Zones.name-6"
    case SnapshotBuilder_ZonesName_7 = "SnapshotBuilder+Zones.name-7"
    case SnapshotBuilder_ZonesName_8 = "SnapshotBuilder+Zones.name-8"
    case SnapshotBuilder_ZonesName_9 = "SnapshotBuilder+Zones.name-9"
    case TraceStoreDetail = "TraceStore.detail"
    case TraceStoreDetail_2 = "TraceStore.detail-2"
    case RoomHandleGateReturn = "RoomHandleGate.return"
    case RoomHandleGateReturn_2 = "RoomHandleGate.return-2"
    case SnapshotBuilder_FlowsLabel = "SnapshotBuilder+Flows.label"
    case SnapshotBuilder_FlowsLabel_2 = "SnapshotBuilder+Flows.label-2"
    case SnapshotBuilder_FlowsLabel_3 = "SnapshotBuilder+Flows.label-3"
    case SnapshotBuilder_WorkRoomsName = "SnapshotBuilder+WorkRooms.name"
    case SnapshotBuilderName = "SnapshotBuilder.name"
    case SnapshotBuilderName_2 = "SnapshotBuilder.name-2"
    case mainString = "main.string"
    case mainString_2 = "main.string-2"
    case mainString_3 = "main.string-3"
    case mainString_4 = "main.string-4"
    case mainString_5 = "main.string-5"
    case mainString_6 = "main.string-6"
    case mainString_7 = "main.string-7"
    case mainString_8 = "main.string-8"
    case mainString_9 = "main.string-9"
    case mainString_10 = "main.string-10"
    case mainString_11 = "main.string-11"
    case mainString_12 = "main.string-12"
    case mainString_13 = "main.string-13"

    // 교차 메모리 검색 & 볼트 영수증
    case menuSearchMemory = "menu.search_memory"
    case memorySearchTitle = "memory_search.title"
    case memorySearchPlaceholder = "memory_search.placeholder"
    case memorySearchEmpty = "memory_search.empty"
    case memorySearching = "memory_search.searching"
    case memorySearchScore = "memory_search.score"
    case vaultAutoBumped = "vault.auto_bumped"
}
