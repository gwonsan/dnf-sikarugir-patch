# Fresh DNF app setup

> Execute inline with `superpowers:executing-plans`; finish with independent review.

**Goal:** Add a first-install command that creates an empty Sikarugir Wine 11 app, opens the official Neople installer, sets its executable path, then applies the existing Korean/font and website patch.

**Design:** Download the official Template 1.0.21 and WS12WineSikarugir11.0_1 archives, pin SHA-256, assemble in a temporary sibling folder, then move without overwriting. Initialize with the template's own `WSS-wineprefixcreate`. Keep vendor installation and login interactive. Existing app patching remains `설치.command`.

**Constraints:** macOS 14.6+, Rosetta on Apple Silicon; no bundled vendor binaries or user data. Never overwrite an existing app or terminate an existing game's processes. Only resume apps marked as created by this setup. Preserve the first patch backup and existing URL handler until the user installs the patch.

**Files:** `Sources/Wine.swift` shares Wine environment construction; new `Sources/WrapperFactory.swift` verifies and assembles archives, while `Sources/Bootstrap.swift` handles download and setup; `Sources/App.swift` adds CLI dispatch; `처음설치.command` invokes it; build/test scripts package and verify it; README/VALIDATION document both routes.

- [x] Test generic Wine execution before a plugin is installed; preserve existing URL validation.
- [x] Test archive integrity, creation with spaces, existing destination preservation, and failed assembly cleanup using real temporary files/archives.
- [x] Implement bootstrap and resume checks, prefix initialization, Neople installer selection, executable path and existing patch application.
- [x] Test a fresh official wrapper and the supplied installer separately from the working DNF app; verify fonts, plugin, registry and Wine smoke without logging authentication URLs.
- [x] Rewrite README with user-confirmed Korean rendering and actual play on 2026-10-13; distinguish the fresh install test from the working app's gameplay confirmation.
- [x] Run full tests, universal build, archive signature check and independent review.
- [ ] Push source and publish the verified ZIP to the authorized private repository.

**Review focus:** Existing destinations and symlinks must stay untouched; failed downloads must never be executed; cancellation must leave a resumable owned app; vendor binaries stay out of Git; fresh setup must not change the working app's URL handler during validation.

**Observed integration details:** The template does not initially contain Winetricks; Configure downloads it into SharedSupport. The bootstrap pins the same official script and runs it with the selected Wine environment and bundled resource tools. Neople's builder relaunches a child process, so its parent exit is not proof of installation; setup waits for the installed starter. The user must press Install in the Wine dialog. Creator and automatic-wrapper probes were independent empty prefixes; only the original wrapper has user-confirmed gameplay.

**Recovery review:** A copied TTC alone does not prove Winetricks completed its registry changes. Resume requires a success marker plus a nonempty font, forces incomplete installs to rerun, and writes the marker only after success. Independent failure/retry/skip proof passed.

**Additional user-requested check:** GAME START from the already logged-in Safari session reached the fresh Creator wrapper's downloader and wrote game files into its own prefix. A temporary bridge forwarded with the production launch function and restored the original handler; the original patch state and app settings remained unchanged.
