# DNF Keyboard Mapping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Editable, persistent keyboard mappings in the existing TUI, applied only while the selected DNF game is focused, without Karabiner.

**Architecture:** A versioned profile and pure input-state engine feed a bundled native event-tap agent. The TUI edits profiles; the web bridge starts the agent when enabled. The agent verifies process mappings and passes through every other app.

**Tech Stack:** Swift, AppKit, CoreGraphics, Carbon, IOKit; existing universal macOS 14.6 helper.

**Spec:** `docs/superpowers/specs/2026-10-27-keyboard-mapping-design.md`

## Global Constraints

- No Karabiner, engine fork, global preferences, game binary modification or publication.
- No keyboard logging. Require permissions explicitly and fail open outside an attested DNF target.
- Keep the existing installer and terminal workflows.

## Review Focus

- Held keys during focus changes or agent shutdown must be released to the original PID.
- Two physical keys mapped to one target must not release each other prematurely.
- Repeats and Caps Lock releases must not repeatedly switch the input source.
- Invalid/mismatched profiles must leave input untouched.
- A different Wine application or different DNF wrapper must never receive a mapping.

### Task 1: Profiles and state machine
Files: `Sources/KeyMapping.swift`, `Tests/KeyMappingTests.swift`.
- [x] Write and run failing behavior tests for profile persistence/validation and state-machine transitions.
- [x] Implement `KeyProfile`, `KeyCatalog`, `KeyMappingState`, and scope predicate; re-run tests.

### Task 2: Scoped native agent
Files: `Sources/KeyboardAgent.swift`, `Sources/App.swift`, `Sources/Bridge.swift`.
- [x] Add failing scope/lifecycle tests where behavior can be exercised without system permission.
- [x] Implement permission checks, attestation, event tap, passive Caps monitoring, source guard, lease and configuration reload.
- [x] Integrate CLI and enabled-profile launch. Compile native runtime; do not synthesize input into the user's game during automated tests.

### Task 3: TUI editor
Files: `Sources/KeyboardUI.swift`, `Sources/TerminalUI.swift`, terminal tests.
- [x] Write failing tests for editor behavior and menu routing.
- [x] Implement two-pane pickers/editor, toggles, preset, restore and permission/status flow; run PTY tests.

### Task 4: Packaging and verification
Files: build/test scripts, README, validation document.
- [x] Include all new Swift sources/frameworks in universal builds and test harnesses.
- [x] Run full test suite, universal build/signature checks and a scoped integration probe.
- [x] Review the complete branch, fix findings, and record results and physical-keyboard limitations.

## Ledger

- User explicitly requested implementation after the Wine-native approach discussion; proceed inline without another design approval round.
- Managed worktree creation returned “Not a git repository” because the chat root is above the nested repository. Created a Git worktree at `../dnf-keyboard-mapping` on `feat/keyboard-mapping` instead.

- Ruling: use a separate nested `DNF Keyboard.app` with a stable bundle ID and Launch Services launch so input permission belongs to the mapper rather than Terminal; the installer also does not confuse the agent with the web bridge.
- Review fixes: adopt unmapped/initially held targets for shared key ownership; seed pre-held keys on focus entry; guard both HID/notification orderings; pass initial held remapped sources through until release. Regression tests added.

- Final checks: 12 Swift suites + 35 Python tests passed. Production universal helper menu/editor/Q PTY probe passed without changes to user settings. Clean extracted ZIP parent and nested helper strict signatures and arm64/x86_64 slices passed. Native read-only Caps state query succeeded. Reviewer found no remaining important issues after regressions were added.
- Manual gate remains explicit: user-granted keyboard permissions and physical-key tests in DNF chat, focus transitions and other apps. No claim of real-game keyboard verification or GitHub publication. The later explicit live-test request authorizes installing the helper and saving a real profile.

- Packaging follow-up: FileProvider attaches empty FinderInfo to copied app bundles. Installer now removes only FinderInfo/ResourceFork from its exact staged helper copy without following links, then performs strict deep verification. Signed nested-fixture regression proves metadata cleanup succeeds and real signed-content changes are still rejected.

- Authorized live test: production installer completed against the existing wrapper after helper/state backup; installed strict signatures passed. Real TUI saved/enabled the preset; missing permission failed open. Safari GAME START reached the real game loading screen and character selection. Waiting for user authorization for new input permissions and native Wine input fallback; no test keystrokes have been sent.

- Live runtime follow-up: native `CGEvent.tapEnable(false)` emits `tapDisabledByUserInput`; initial implementation therefore exited during its own intentional pause. Installed-agent opt-in regression failed in 0.26 s before fix. Added capture intent plus current tap-state guard; native mouse-only disable→enable→drain regression failed against the intent-only implementation then passed against the final predicate, retaining unexpected active-disable shutdown. Full suite passed (13 Swift + 35 Python; opt-in live test separately passed). Reviewer cleared the race fix.
- Actual game input: production TUI saved temporary A→B; unsent game chat showed b. Right Option switched Korean/ABC; I produced Korean ㅑ. Safari foreground paused the mapper and page-find received literal a. Temporary mapping was removed through the production TUI; original preset matches backup. Physical Caps test awaits user's hardware press; synthetic input cannot exercise its IOHID callback.
- Test-environment condition: existing Karabiner seized the internal keyboard (0xe00002c5), despite permission being granted. User authorized temporary quit; official quit UI released device and native HID open succeeded. Restart original Karabiner after the physical test. No global keyboard configuration was edited.
- Ad-hoc rebuild requires removing/re-adding the current nested app in both TCC permission lists; toggling stale entries did not work. README documents the actual path and the new macOS Accessibility label. Reapplying full installer while game ran timed out; helper-only staged/signature-verified replacement preserved Wine/game and kept a rollback copy.

- User-assisted hardware check completed: physical Caps→I→Caps→I yielded unsent Ii with ABC retained. Cleared text/closed chat; native emergency Ctrl+Option+Escape stopped agent (zero matching processes). Hardware Caps off and original Korean input source restored. Restarted original Karabiner. Verified original profile unchanged and current installed helper strict signature valid. Removed temporary old helper from app discovery after preserving verified rollback ZIP; neople handler resolves to current installed helper.
