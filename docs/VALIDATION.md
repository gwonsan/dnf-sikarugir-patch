# Validation — 0.1.0

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

Not yet verified: downloading fonts into a clean prefix through `WSS-winetricks fakekorean`, an Intel Mac, Korean text rendering after launcher restart, game login and actual play. No game download was stopped during validation.
