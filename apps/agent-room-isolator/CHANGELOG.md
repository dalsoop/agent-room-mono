# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.3] - 2026-09-19
### Changed
- Customer-grade single room local storage adoption via StateRootKit.ensureCustomerRoomStorage(slug:).

## [1.0.2] - 2026-09-19
### Changed
- Customer-grade single-room storage migration and worktree service isolation.

## [1.0.1] - 2026-09-13
### Changed
- Native lint: kit products, L10n onboarding, required occupant/tenant, RoomFiles instead of FileManager.default.

## [1.0.0] - 2026-09-13

### Added
- Window app from `agent-cli-scaffold new`: room concept first, then git worktree bind, then ROOM.md / DESIGN.md / AGENTS.md in the room folder.
- CLI `provision` (`--dry-run`), `bind`, `emit-md`, `list`, `show`, `doctor`.
- Main window: sidebar of rooms, empty pane with concept/worktree/MD cards, detail with those three sections.
- `trace`: bind + work-todo placement + git worktree list + room MD. spawn-room JSON without roomID/planID is an error (no invented IDs).
- GUI/CLI `list` reads `agent-work-todo placement list` first. `binds.json` is fallback only.
- Delegates git to `agent-worktree-control-terminal create` and the ledger to `agent-work-todo spawn-room`.
