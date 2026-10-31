# Unified Settings and Karabiner Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline; independent subsystem work may use the explicitly applicable dispatching-parallel-agents skill. Use one whole-branch review at completion.

**Goal:** All previously applied user settings are controlled from the TUI; game launch automatically uses Karabiner for supported mappings, native fallback otherwise, verified in the real installed game.

**Architecture:** Per-wrapper desired settings and reversible Wine settings; generated owned Karabiner rule + acknowledged short lease; existing attested native controller with validated semantic completion and native fallback.

**Tech Stack:** Swift/AppKit/CoreGraphics/Carbon/IOKit, Karabiner JSON/CLI, existing universal build.

**Spec:** `docs/superpowers/specs/2026-10-28-unified-settings-karabiner.md`

## Constraints

No GitHub publication. No game/Wine binary modification, auth/key logging, global input preferences, unrelated Karabiner edits or false claims that synthetic events exercise physical Karabiner/HID paths.

## Tasks

- [x] 1. Reversible game settings: test backup/migration/apply/restore ownership; implement per-wrapper desired/applied/original storage, Command/Option app defaults, D3DMetal/CNC settings, pending application. Files GameSettings.swift + GameSettingsTests.swift.
- [x] 2. Karabiner configuration/routing: write failing tests, implement key catalog names, profile backend migration, explicit/identity semantic target selection, scoped rule generation, atomic owned-rule merge/remove, collision handling. Files KeyMapping.swift, Karabiner.swift + tests.
- [x] 3. Runtime controller: acknowledged bounded CLI lease stream, focus invalidation, game-launch auto detection/start, fresh per-focus semantic socket sessions + native PID-only completion, lifecycle cleanup/emergency. Integrate App/Bridge/KeyboardAgent; test runtime pieces and actual rule lint.
- [x] 4. Unified TUI: settings editor, backend/routing/status, Wine settings apply/restore, existing install/font flows preserved. PTY regressions before production changes; build scripts include all modules.
- [x] 5. Live install/game verification: backup existing helper/config, install signed final dev build, grant current own-agent permissions when required, test actual physical Karabiner path plus native fallback, restore temporary game bindings and user config/runtime state. Record evidence and limitations.
- [x] 6. Review, fix regressions, final suite/archive checks, local commits. Audit every requirement before marking goal complete.

## Ledger

- User's explicit “진행하고 … 실제 … 게임 … 테스트” authorizes implementation and live installation/settings tests; no additional design approval round.
- Recon verified installed Karabiner 16.3.0, CLI acknowledged stdin stream works, and existing selected profile has one user rule. Research agents read only; no live mapping was changed. A harmless capability variable was set to zero.
- Ruling: do not substitute a Caps-only Karabiner shim for requested delegation; supported ordinary maps/source switching must actually be Karabiner rules. Caps-to-native fallback must avoid double application.
- Native renderer investigation remains separate: expose existing supported flags, do not ship unverified binary/graphics experiments.

## Final audit — 2026-10-31

All six tasks completed locally. Actual installed-game checks covered physical Karabiner and native mapping/Caps/Korean, held-key Command+Tab, expired-lease release, same-Wine non-game rejection, Control/Command distinction, running-game renderer deferral and original-profile restoration. Final `scripts/test.sh` passed in the authorized socket/PTY environment (Python38, one opt-in skip; all Swift suites and actual Karabiner linter). The final documentation-only archive refresh retained the exact installed/tested executable bytes; extracted strict signatures and arm64/x86_64 checks passed. No GitHub push or release. Long sessions, Intel hardware and fresh-Mac unified-menu installation remain outside current verification. Details: `docs/VALIDATION.md`; private evidence is ignored under `build/`.
