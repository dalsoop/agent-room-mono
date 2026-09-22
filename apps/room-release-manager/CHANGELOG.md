# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.9] - 2026-09-17

### Changed
- Migrate raw bash -lc execution to CommandKit.ShellCommand.run to comply with NoRawShellExecutionRule.

## [1.0.8] - 2026-09-09

### Added
- MenuBarPopoverUIKit·MoneyInflowUIKit 기계 치환 (bb0db93)
- **ai-agent-config,ai-cli-account**: Antigravity 에이전트 통합 및 Package.resolved v2 정규화 (e08571f)
- **i18n**: 삼항·보간 한글 UI를 L10n으로 이동 (2d9cb92)
- **i18n**: 함대 L10n 전환과 영문 카탈로그 번역 (2b9276f)
- **fleet**: 188개 GUI 앱 FleetDesk 정책 채택 — App.init에 applyFleetDeskPolicy (c053c40)
- **identity**: backfill agent_surface on 165 apps (c152bda)
- adopt app.sqlite layout on scaffold-shaped fleet apps (df0d265)
- **fleet**: surface translation-coverage under Settings language picker (f97ee0c)
- **apps**: remaining apps에 Telemetry trait 추가 (4b93c08)
- **store**: fill remaining gujo-product manifests (b911038)
- HealthPulse 배치 연결 169개 앱 (9a7dcb7)
- **app-fleet-quality-auditor**: quality-contract 채택 aspect — 367앱 미채택을 3건으로 (30e6034)
- **party-room-release-manager**: 파티룸 멀티 플랫폼 배포 매니저 (d543e1a)

### Changed
- **fleet**: backfill package-identity UUIDs across 480 apps (afc33b8)
- **store**: drop per-app pricing.json for Gujo Pass (f953a00)
- **party-room-release-manager-swift**: package-identity purpose·state_root_env (5f2d2ad)
- **fleet**: CI 지적 122앱 마케팅 버전 bump — marketing-version-bump 차단 해소 (115f759)
- **i18n**: 소스 변경 앱 396종 marketing version patch bump (73681b8)
- **fleet**: 차단 위반 전수 해소 — lineLimit frame 318건 + gujo-managed-gate + package-manifest-static (dc73663)
- **fleet**: HealthPulseAdoption 복제 제거 W2 (53278c3)
- 설정 씬 전환 앱 마케팅 버전 patch (58f03cf)
- app-distribution-manager → app-build-manager (f9cc928)
- messy_bool_mixed 혼합연산자 일괄 리팩토링 — 132앱 Grok AWO (90c7c3f)
- **apps**: /opt/homebrew hardcode 292파일 추가 HostPlatform SSOT 이관 (db5d0bd)
- **apps**: /opt/homebrew hardcode 일괄 HostPlatform SSOT 이관 (df75835)
- Sparkle SSOT — SelfUpdating trait로 통일 (324cd99)
- **fleet**: 출시 버전 1.0.0 — 0.x 앱 154개 + set-version 도달 불가 수정 (cc46035)
- **fleet**: 계약 채택 36앱 — pulse/state-mirror/interop 골격 (43af60d)
- **fleet**: CLI GujoManaged gate for 20 dual-entry apps (97e4614)
- PRRM ↔ OSAP 관계와 party-room 공개 릴리스 포인터 (b330a2e)

### Fixed
- **hosts**: rewrite retired Gujo domains in product json and docs (fe1234e)
- **lint**: 워커 1차 위반 수리분 적재 — import deps·하드코딩 카탈로그 추출 (2e2519e)
- **i18n**: CLILocalization 앞에 잘못 붙은 model. 수신자를 전량 걷어낸다 (cb50c47)
- **sparkle**: 다창 앱 설정 Window를 Settings 씬으로 옮긴다 (a6406b6)
- app.sqlite 함대 배치(df0d2656a1)의 ensureDurableStore 오삽입 19앱 정정 (76aedf1)
- **party-room-release-manager**: clear i18n hard/errors (hard=0) (6eddf15)
- **fleet**: version/capabilities 리터럴을 CLIMarketingVersion 으로 교체 (e5fa001)
- **party-room-release-manager**: clear native lint warnings (afc4c78)
- **fleet**: package-level .product() 오삽입 62앱 제거 + Package.resolved 79앱 생성 (7065066)
- **fleet**: InteropKit 의존 누락 227앱 일괄 수정 (v2) (934b144)
- **fleet**: version policy + audit appsDir + distribution marking (62435b5)
