# Validation

## Source cleanup and installation permission — 0.3.3 (2026-10-16)

- On 2026-10-16, the user directly confirmed that v0.3.3 works normally.

- Ready installation permanently deletes the validated, prefix-free source bundle without moving it to Trash only after the patch installer succeeds. Installed games, overlapping source/destination paths, source symlinks and incomplete destinations are protected; cleanup failures are reported without failing the successful installation. Preparation-only mode does not clean up.
- Regression tests exercise actual deletion of an isolated source fixture, verify its open asset has zero filesystem links (not moved to Trash), and cover overlapping paths, missing source, an injected deletion failure and preservation of the ready installed fixture. The start-command regression first failed on its old missing-source check, then passed after allowing the installer to decide whether an existing installation can be reused.
- Six Swift suites and four Python tests passed locally. The sandboxed AppKit test emitted the existing OS notification registration warning; its assertions passed. No real game, patch state or URL handler was changed.
- The three installation commands clear quarantine on themselves and their helper before starting it. Installation clears quarantine on the selected Sikarugir wrapper before initializing or running Wine, including incomplete-app recovery. `xattr -drs` preserves external symlink targets and unrelated attributes; failure stops installation. Regression tests first failed with quarantined fixtures, then passed after the permission steps were added. The actual game is never used for these tests.
- README explains that the first blocked command must still be opened explicitly (Open Anyway or `/bin/bash`), and includes a separate installed-DNF recovery command. This is not Developer ID signing, notarization, a global Gatekeeper change or a guarantee against every launch warning.
- The user confirmation did not specify the device, macOS version or individual test steps. Independent new-Mac Gatekeeper and full UTM install/source-deletion/gameplay tests were not performed for this version.

## Fresh local assembly — 0.3.2 (2026-10-15)

- In UTM, the user reported that execution works but the `.command` warning remains. They also reported a dangling `drive_c` link and confirmed they were inspecting the DNF.app in the extracted download folder, not the installed app. That source is intentionally prefix-free. Guest macOS details, final installation checks, missing-Rosetta coverage and game download/gameplay in the VM were not independently established.
- The extracted v0.3.2 release helper also passed an isolated legacy-recovery test: it backed up a quarantined incomplete v0.3.1 app (including a sentinel user file), assembled a replacement and completed Windows/plugin initialization.

- Confirmed the official Template archive contains only a relative `Contents/drive_c` link; Wine creates its target and the Windows files during initialization. A separate no-prefix baseline completed this operation. Missing `drive_c` alone is not proof of an incorrect link.
- Confirmed v0.3.1 DNF.app fails strict bundle signature validation. The v0.3.1 signature claim below applies to the **DNF Web Launcher helper only**, not the Sikarugir wrapper.
- Ready installation now assembles native code from the pinned official template and engine locally, then copies only the ready data/licensing. It does not execute the downloaded ready app or remove quarantine attributes. This is not Developer ID signing or Apple notarization.
- Regression test failed against the old bundle-copy implementation, then passed after local assembly. Tests cover partial prefixes, a zero launcher exit without Windows files, diagnostic output, nonzero exit, timeout, complete-prefix preservation, and backing up an incomplete old app.
- Real integration check started with no destination app/prefix and a quarantined input ready app. Production preparation assembled a fresh wrapper, created both Program Files directories, system.reg/user.reg and cmd.exe, installed both Neople starter EXEs, and imported/exported all 16 Korean font replacements. cmd.exe exited successfully. Only isolated test apps were changed; the installed game, state and URL handler were not changed.
- Reproduction command: `bash scripts/test-fresh-install.sh /path/to/prepared/DNF.app`. This opt-in test runs real Wine in a newly created temporary directory and preserves logs. It does not install the URL handler or launch a game download.
- [GitHub Actions run 38595656441](https://github.com/gwonsan/dnf-sikarugir-patch/actions/runs/38595656441) passed for implementation commit `2183db0cc6280ba47e9d76e4b4a72ac4b7115497`. Six Swift suites and two Python tests passed locally. Sandboxed AppKit tests emitted an OS notification registration warning but their startup/error-window assertions passed.
- This was an isolated new prefix on the existing Mac, **not a separate macOS account or second physical Mac**. Existing Rosetta and verified download caches were available. The later UTM user report is recorded above. Absent-Rosetta setup, a second physical Mac, full game download and gameplay with v0.3.2 remain unverified.

## Quiet web launch bridge — 0.3.1 (2026-10-13)

- Reproduced the original instruction window through the real AppKit delegate: the new no-window regression test failed before the fix.
- Removed the startup window and foreground activation. The helper uses accessory activation and `LSUIElement`; it creates a window only for a launch failure or nonzero Wine exit.
- Native AppKit regression checks passed for silent startup, actionable launch errors and reusing one error window. All five existing Swift suites and both Python packaging tests also passed. Existing request forwarding and Wine arguments are unchanged.
- Built arm64/x86_64 helpers in both ZIPs. Archive integrity, extracted strict code signatures, version 0.3.1, accessory metadata and the redacted gameplay image passed. The prepared app retains the pinned assets and contains no initialized prefix, engine or launcher logs.
- Updated only the local DNF Web Launcher, with a recoverable backup. The game app's Info.plist and patch state hashes stayed unchanged. The installed helper executable matches both verified distribution ZIPs; launching the updated helper starts its process without the original instruction window.
- This update does not repeat full game download or gameplay testing. The user's earlier gameplay confirmation applies to v0.3.0 on the tested Mac.

## Prepared app package — 0.3.0 (2026-10-13)

- Built the prepared app from the SHA-256-pinned official Template 1.0.21, with D3DMetal enabled. Only Source Han Sans and the two verified official Neople starter EXEs were added. No prefix, engine, user registry, game folder or launcher logs are in the distribution. Preserved template license notices and included the complete Source Han Sans SIL OFL notice.
- Ran production `--prepare-ready` into an independent directory. It installed the pinned engine, initialized a fresh local prefix, copied the three assets and registered fonts without running the Neople installer UI. Wine smoke passed. Korean mappings verified 16/16; both Windows NT and legacy Windows font sections contain the Korean font face.
- Tested Safari GAME START with this prepared app using a temporary request bridge built around the production Wine launch function. The user confirmed download progress; an independent file sample showed 363 files totaling 1,029,876,351 bytes. No authentication request was read or logged. The bridge restored the original URL handler immediately after forwarding.
- After the v0.3.0 release, the user directly confirmed full game download completion and normal gameplay on 2026-10-13. This extends the prepared app's validation beyond the earlier agent-observed partial download; the complete download and gameplay are user-confirmed.
- Stopped only the independent test downloader and moved its game files to Trash after verification, as requested. The earlier Creator test's downloaded game folder was also moved to Trash. The working app was not used as a packaging source.
- Working Info.plist and patch state hashes stayed unchanged during independent preparation and website testing. The original URL handler remained `io.github.dnf-sikarugir-patch.launcher` after forwarding.
- Five Swift suites and two Python packaging tests cover clean copying, tampering, symlink assets/destinations, missing or empty starter recovery, both font registration sections, ownership, locking, launch forwarding, font rollback and publication without replacing a newly created destination.
- Independent review reproduced and fixed missing/empty starter recovery and the already-installed prepared-app bypass. Font registration now matches the two sections used by pinned Winetricks. The packaged README's validation link points to the repository.
- Both v0.3.0 ZIPs passed archive integrity and packaged README/command/version checks. Extracted helper code signature and arm64/x86_64 architectures passed. The only bundled `.reg` file is the unchanged official Configure default-reset resource, verified byte-for-byte against the pinned template; no user registry is included.
- `DNF-Sikarugir-Patch-v0.3.0.zip`: 191,164 bytes; SHA-256 `d76a9e5dbcb9c5c4ba2eb3944194b8d5f9a894074f0b49a0fd21c38209e64fa9`.
- `DNF-Ready-v0.3.0.zip`: 258,193,916 bytes; SHA-256 `27cab7857ddf8edeb660882f651a5181ee964cfa00801bfac74751e3ef9fbfcd`.
- Published [v0.3.0](https://github.com/gwonsan/dnf-sikarugir-patch/releases/tag/v0.3.0) from commit `8fd6ed98cf27a1bdd23145ddfbe8a9bc6ec6287c` in the verified private repository. Both GitHub asset sizes and SHA-256 digests match the local records above. [GitHub Actions run 38279096948](https://github.com/gwonsan/dnf-sikarugir-patch/actions/runs/38279096948) passed the five Swift suites, two Python tests and universal build for that commit.
- Rosetta installation is interactive when needed; automatic acceptance is not used. Existing Rosetta was available on the test Mac, so the missing-Rosetta flow has not been executed on a clean Mac.
- An Intel Mac and a second machine remain unverified. Full download completion and normal gameplay in the prepared app are user-confirmed on the tested Apple Silicon Mac.

## User confirmation — 2026-10-13

On the existing Apple Silicon Mac (macOS 26.6.2, Sikarugir Wine 11), the user initially confirmed that website launch, downloading, Korean text and actual gameplay all work normally. After the v0.3.0 release, the user also confirmed the prepared app's full download completion and normal gameplay. These are user confirmations on this environment, not a guarantee for every Mac or future game update.

## Fresh setup — 0.2.0 (2026-10-13)

- Created an independent empty `DNF.app` through the installed official Sikarugir Creator, using Template 1.0.21 and WS12WineSikarugir11.0_1. Enabled D3DMetal in its Configure UI and completed `fakejapanese` font installation.
- The supplied `NeopleCustomURLBuilder.exe` matched the file downloaded from the official DNF page (SHA-256 `d97c313e5e284b0665dd267828d5571551c706c2be2d712e461cc68ccfa7c109`).
- Chose that installer in Configure. The Wine dialog required the user to press **Install**; it did not proceed merely by launching the EXE. After the user completed installation, both official Neople starter executables were present. Selected `NeopleCustomURLStarter.exe` in Configure's Choose Executable dialog.
- The fresh Creator wrapper passed the production Wine smoke check and Korean font registry import/export verification (16/16). The working wrapper's Info.plist and patch state checksums stayed unchanged during these tests.
- Separately tested the production `--create-wrapper` command in a new directory. It downloaded and verified the pinned official template, engine and Winetricks script; assembled a fresh wrapper; initialized its prefix; enabled D3DMetal; and installed Source Han Sans through `fakejapanese`.
- Four automated suites cover generic Wine before plugin installation, URL forwarding, font ownership/rollback, locking, SHA-256 rejection, fresh archive assembly, D3DMetal, executable path, existing destinations, dangling symlinks and failed extraction cleanup.
- Independent review reproduced an interrupted font copy that incorrectly skipped registration on resume. Bootstrap now requires a completion marker and a nonempty font file, reruns incomplete installation with `--force`, and writes the marker atomically only after success. The temporary failure/retry/skip proof and production resume check passed.
- At the user's request, used the already logged-in Safari homepage to test GAME START with the fresh Creator wrapper. A separate temporary bridge used the production Wine launch function and restored the original URL handler after forwarding; the existing patch state was never rewritten. The user confirmed download progress, and actual game files appeared under the fresh prefix's `Program Files (x86)/DNF`. No authentication URL or launcher log was read or published.
- The first file sample contained 971 files totaling 2,114,073,052 bytes; a later sample confirmed continued growth. Existing-wrapper diagnostics still passed Wine, 16/16 Korean mappings and the original patch handler.
- Universal v0.2.0 ZIP extracted successfully; strict code signature, arm64/x86_64 architectures, version, all four command permissions and packaged README were verified. SHA-256: `13e9541d565280ff571a017c472757c5db376787c71850be6965149afa93ecc3`.
- Published v0.2.0 from commit `ae6cdafeb5d2f96cc72a790cb71d5004f79621ff` to the private repository. GitHub's uploaded asset size (157,172 bytes) and SHA-256 digest match the verified local ZIP.
- [GitHub Actions run 38275664242](https://github.com/gwonsan/dnf-sikarugir-patch/actions/runs/38275664242) passed all four suites and the universal build on macOS 15 for the released source commit.
- No working game prefix was copied into the new wrappers. At the end of v0.2.0 validation, full download completion and gameplay in the fresh wrappers had not been verified; the later prepared-app confirmation is recorded above.

## Existing patch validation — 0.1.0

Local checks on Apple Silicon macOS with an existing Sikarugir Wine 11 prefix:

- `bash scripts/test.sh`: three suites passed. URL forwarding uses a temporary wrapper with spaces in its path. Font tests cover selective snapshots, Japanese aliases, UTF-16, case-insensitive registry names, later edits/deletions and reinstall. Lock tests cover concurrent entry and release after errors.
- `bash scripts/build.sh`: arm64 and x86_64 universal executable built successfully.
- ZIP extracted into a fresh directory: `codesign --verify --deep --strict` passed.
- Real install → reinstall → uninstall → install completed successfully.
- State checksum stayed identical across reinstall, preserving the first backup.
- Real diagnostics: Wine smoke passed; Korean mappings 16/16; Neople URL handler points to the installed patch.
- Original Sikarugir `Info.plist` matched the pre-repair backup byte for byte.
- Separate earlier URL bridge test reached the Neople launcher and active game download.
- GitHub Actions on macOS 15 completed the three suites and universal build successfully for the released source commit.
- Private repository visibility verified; the uploaded release ZIP's GitHub digest matches the local SHA-256.

Independent static review found three recovery issues: case-sensitive font names, overwriting later font edits on reinstall, and concurrent operations. Each was reproduced with a failing test and fixed; the full suite then passed.

At the end of v0.1.0 validation, an Intel Mac, first installation on a second machine, and full download completion and gameplay in fresh wrappers were unverified. Later prepared-app confirmation is recorded above. No game download was stopped during the v0.1.0 validation.
