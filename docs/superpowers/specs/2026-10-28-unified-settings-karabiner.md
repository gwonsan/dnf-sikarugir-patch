# Unified TUI settings with automatic Karabiner routing

The user approved the stated design and explicitly requested implementation plus actual installed-game tests. Continue on `feat/keyboard-mapping`; do not publish GitHub. The isolated worktree is based on c45d1ec and currently resides at `/Users/gwonsan/Documents/ChatGPT/dnf`.

## Requirements

- One TUI controls existing install/reapply, fonts/restore, diagnostics and launch, plus renderer options, DNF-only Command/Control separation and Option interpretation, all keyboard mappings, presets, backend choice and restoration. Previously applied local Wine values must become reproducible and reversible through the TUI.
- At game launch, auto-detect a usable installed Karabiner. Delegate ordinary one-to-one keys, disabled keys and supported standalone input-source switching to Karabiner; use native handling for functionality it cannot express correctly. Without usable Karabiner, retain the native backend. Show the selected backend and per-rule routing.
- No duplicate remapping. Karabiner selects the semantic target; native delivery must bypass the physical-source mapping lookup and share target ownership with identity keys.
- Existing Karabiner profiles/rules and non-DNF app behavior must be preserved. Merge/remove only an identifiable managed rule in the selected profile, atomically and with backup/concurrent-edit checks.
- Only the selected DNF.exe may be authorized: native foreground PID plus ps comm and mapped executable attestation, exact Wine executable file-path condition in Karabiner, short expiring activation lease, immediate focus-notification clear and generation checks. Do not identify Wine solely by bundle ID or a generic /wine suffix.
- Karabiner cannot expose a PID predicate. File-path plus lease has a bounded same-binary focus transition race; document it, minimize it and test switches to launcher/other apps. Never claim a mathematical PID isolation guarantee for delegated actions.
- Caps output must not trigger the macOS Korean Caps language switch. Karabiner intercepts physical Caps and sends a semantic command; native PID-only completion owns the virtual Caps state. Retain IOHID only in the native backend. Do not reserve user F-keys or Fn combinations as carriers.
- Save desired Wine/renderer settings and apply safely with backup before game launch or after game shutdown. Do not run hanging Wine registry commands while the game is active. Restore owned values only, preserving later user changes. Adopt the prior local Command backup when safe.
- Keep OS input-source preferences and Wine/game binaries unchanged. Never read/log/replay launch tokens or keystrokes. Authentication/password entry remains manual.

## Architecture

Existing Swift helper remains the scope/lifecycle controller. Karabiner 16.3+ uses exact path + leased generation conditions, with a persistent acknowledged CLI stream. Every supported key uses the same ordered semantic datagram channel, with explicit mappings taking precedence over identity bindings. Native completion validates targets, owns hold/repeat/release and posts only to the attested DNF PID. Without a usable Karabiner connection the native backend handles the full profile. Configuration is persisted per wrapper. Game settings have separate desired/applied/original state and an owned-value restoration mechanism.

## Verification contract

Pure tests cover legacy profile migration, semantic target delivery without remapping, generated rule scope and serialization, config merge preservation/removal/conflicts, lease invalidation and stale acknowledgment handling, Wine backup/reapply/restore ownership and renderer preservation. Real PTY tests cover backend/settings UI/save/discard/restore. Universal archive and installed signature checks follow. Live tests must use the real installed helper and DNF: physical Karabiner A→B, right Option Korean/ABC, physical Caps Ii, Control vs Command key names, focus to Safari and another Wine app, config restoration and restart. Also exercise native fallback in the real game with Karabiner temporarily stopped, then restore the user's original runtime/config state. User assistance may be needed for physical HID keys and OS authentication.

## Reviewed transport correction (2026-10-28)

Pinned Karabiner 16.3 source proves that a held `to.key_code` output survives focus/variable changes until physical release; removing its rule also retains the active manipulator. This exceeds the bounded initial focus race and cannot meet the DNF-only held/repeat requirement. The prior direct-HID/Caps-carrier implementation is therefore a development baseline, not the final design.

Use the supported `to.send_user_command` UNIX datagram endpoint instead. Karabiner rules select the **semantic target** (A→B sends B, not raw A), disabled/source-switch actions and down/up phase. The native agent validates the semantic target and sends it only to the attested DNF PID, owns shared-target counts/repeats and releases on focus loss. It must not apply the source mapping a second time. No shell-per-key, new driver, HID carrier, event log or OS keyboard preference change.

Each attested foreground entry owns a fresh private socket endpoint and random session token, embedded literally in the managed rule; close/unlink it immediately on invalidation. Old queued sends and retained key-up actions target the old endpoint/token and cannot affect the new session. All delayed messages retain scope guards. Gate generated rules with the current lease session/generation as well as exact Wine path/time. Preserve existing user config as before. Detect collisions for effective sources and adopted target keys, including implicit Caps and modifier identities.

Live baseline evidence: real installer succeeded, production TUI saved/applied Wine/renderer values, website launched DNF and entered town. User physical A produced b; Caps produced upper/lowercase I/i while global hardware Caps stayed off. Karabiner direct select_input_source did not switch Korean/ABC on this Mac; route this completion through the already-tested native TIS action. Raw captures remain local/ignored. Final socket transport still requires fresh actual physical tests, held-key/focus tests and native fallback verification.
