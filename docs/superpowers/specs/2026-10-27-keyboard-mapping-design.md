# DNF-only keyboard mapping

The user authorized implementation of a Karabiner-free TUI key mapper, scoped to DNF, with right Option switching Korean/English and Caps Lock delivered as Caps Lock. Other applications retain their existing behavior. Continue on the isolated `feat/keyboard-mapping` branch; do not publish or replace the installed app without a verified build.

## Approach

Use the project's existing Swift/AppKit helper as a bundled input agent. The Wine-only registry switches cannot express general key mappings. A custom Wine binary would require maintaining an engine fork and still does not solve macOS consuming Caps Lock. An application-scoped macOS event tap is the smallest independent capture layer, analogous to remote desktop keyboard capture, without a global key-remapping driver. Passive HID monitoring supplies physical Caps Lock transitions because ordinary flags events expose its lock state rather than physical presses. No game executable, Wine binary or system input-source preferences are edited.

## Behavior

- A disabled-by-default, versioned JSON profile belongs to the installed wrapper and contains one-to-one physical-key mappings, disable-key actions and a Korean/English action.
- TUI provides add/change/remove, enable/disable, the requested Korean preset, defaults, permissions and runtime status. Key lists are explicit so Terminal does not have to capture modifier keys.
- Native mapped-key output is delivered only to a foreground process that maps `DNF.exe` inside the selected wrapper's drive_c. Wine's existing Command/Option interpretation remains explicit in target labels.
- Focus loss, reload, timeout and shutdown release owned key states to their original process. An emergency Control+Option+Escape suspends mapping. No keystrokes or authentication URLs are logged or stored.
- Activation requires Accessibility and Input Monitoring; lack of permission fails visibly without intercepting input. Outside DNF the tap is disabled.
- Caps Lock suppresses the original macOS event and uses a local virtual lock state delivered to the Wine process. Input-source changes caused by a physical Caps press are restored only while that same game remains focused. Right Option intentionally selects the enabled Korean/Latin source.
- macOS-reserved shortcuts and keys not exposed by the engine are not promised as Windows input. Real game/IME verification requires granted permissions and physical keyboard input; automated tests must not claim that verification.

## Validation

Pure state-machine tests pin swaps, repeats, duplicate targets, modifier flags, Caps transitions and focus-loss releases. Storage tests pin invalid profiles and atomic wrapper-specific persistence. Scope tests reject other apps and other wrappers. PTY tests exercise the TUI editor. Build and sign universal helper, run the existing full suite, and report manual validation limits honestly.
