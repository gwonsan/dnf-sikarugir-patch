#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_build="$task_root/build"
task_name="DNF-Sikarugir-Patch-dev"
mkdir -p "$task_root/dist"
task_stage="$(mktemp -d "$task_root/dist/.patch-stage.XXXXXX")"
trap 'rm -rf "$task_stage"' EXIT
task_dist="$task_stage/$task_name"
task_app="$task_dist/설치 자료/DNF Web Launcher.app"
mkdir -p "$task_build/module-cache" "$task_app/Contents/MacOS"
cp "$task_root/Info.plist" "$task_app/Contents/Info.plist"
for task_arch in arm64 x86_64; do
  xcrun swiftc -O -target "$task_arch-apple-macos14.6" -module-cache-path "$task_build/module-cache" \
    "$task_root/Sources/Wine.swift" "$task_root/Sources/FontPatch.swift" \
    "$task_root/Sources/PatchLock.swift" "$task_root/Sources/Installer.swift" \
    "$task_root/Sources/WrapperFactory.swift" "$task_root/Sources/Bootstrap.swift" "$task_root/Sources/Prepared.swift" "$task_root/Sources/Bridge.swift" "$task_root/Sources/KeyMapping.swift" "$task_root/Sources/KeyboardAgent.swift" "$task_root/Sources/KeyboardUI.swift" "$task_root/Sources/TerminalUI.swift" "$task_root/Sources/InteractiveCommand.swift" "$task_root/Sources/TerminalSession.swift" "$task_root/Sources/App.swift" \
    -framework AppKit -framework CoreServices -framework Carbon -framework IOKit -o "$task_build/launcher-$task_arch"
done
xcrun lipo -create "$task_build/launcher-arm64" "$task_build/launcher-x86_64" -output "$task_app/Contents/MacOS/DNFWebLauncher"
# Give input permissions a stable, separate bundle identity, independent of Terminal.
task_keyboard="$task_app/Contents/Resources/DNF Keyboard.app"
mkdir -p "$task_keyboard/Contents/MacOS"
cp "$task_app/Contents/MacOS/DNFWebLauncher" "$task_keyboard/Contents/MacOS/DNFWebLauncher"
python3 - "$task_keyboard/Contents/Info.plist" <<'PYKEYBOARD'
import plistlib,sys
with open(sys.argv[1], 'wb') as file:
    plistlib.dump({'CFBundleIdentifier':'io.github.dnf-sikarugir-patch.keyboard',
                  'CFBundleName':'DNF Keyboard', 'CFBundleDisplayName':'DNF 키보드 보정',
                  'CFBundleExecutable':'DNFWebLauncher','CFBundlePackageType':'APPL',
                  'CFBundleShortVersionString':'0.3.3','CFBundleVersion':'6',
                  'LSUIElement':True,'LSMinimumSystemVersion':'14.6',
                  'NSInputMonitoringUsageDescription':'던파가 활성화된 동안 지정한 키 매핑을 적용합니다. 키 입력을 기록하지 않습니다.'},file)
PYKEYBOARD
# Strip only Finder metadata in our fresh staging bundle; preserve quarantine flags.
xattr -drs com.apple.FinderInfo "$task_app" 2>/dev/null || true
xattr -drs com.apple.ResourceFork "$task_app" 2>/dev/null || true
codesign --force --sign - "$task_keyboard"
xattr -drs com.apple.FinderInfo "$task_app" 2>/dev/null || true
codesign --force --sign - "$task_app"
codesign --verify --deep --strict "$task_app"
cp "$task_root/던파.command" "$task_root/README.md" "$task_root/LICENSE" "$task_root/THIRD_PARTY.md" "$task_dist/"
ditto "$task_root/docs/images" "$task_dist/docs/images"
chmod +x "$task_dist/"*.command
ditto -c -k --keepParent --norsrc --noextattr "$task_dist" "$task_stage/$task_name.zip"
# Only development outputs are replaced. Fresh staging excludes legacy commands.
rm -rf "$task_root/dist/$task_name"
mv "$task_dist" "$task_root/dist/$task_name"
mv -f "$task_stage/$task_name.zip" "$task_root/dist/$task_name.zip"
echo "개발 빌드 완료: dist/$task_name.zip"
