# Validation — 0.2.0

## User confirmation — 2026-10-13

On the existing Apple Silicon Mac (macOS 26.6.2, Sikarugir Wine 11), the user confirmed that website launch, downloading, Korean text and actual gameplay all work normally. This is user confirmation on this environment, not a guarantee for every Mac or future game update.

## Fresh setup — 2026-10-13

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
- No working game prefix was copied into the new wrappers. Full download completion and gameplay have not yet been verified in the fresh wrappers.

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

Not yet verified: an Intel Mac, the complete first-install flow on a second machine, or full game download completion and gameplay in the fresh wrappers. Korean rendering and gameplay on the existing wrapper are user-confirmed as stated above. No game download was stopped during validation.
