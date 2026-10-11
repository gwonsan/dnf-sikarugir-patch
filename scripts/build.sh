#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_build="$task_root/build"
task_dist="$task_root/dist/DNF-Sikarugir-Patch"
task_app="$task_dist/DNF Web Launcher.app"
mkdir -p "$task_build/module-cache" "$task_app/Contents/MacOS"
cp "$task_root/Info.plist" "$task_app/Contents/Info.plist"
for task_arch in arm64 x86_64; do
  xcrun swiftc -O -target "$task_arch-apple-macos14.6" -module-cache-path "$task_build/module-cache" \
    "$task_root/Sources/Wine.swift" "$task_root/Sources/FontPatch.swift" \
    "$task_root/Sources/PatchLock.swift" "$task_root/Sources/Installer.swift" "$task_root/Sources/App.swift" \
    -framework AppKit -framework CoreServices -o "$task_build/launcher-$task_arch"
done
xcrun lipo -create "$task_build/launcher-arm64" "$task_build/launcher-x86_64" -output "$task_app/Contents/MacOS/DNFWebLauncher"
# Finder may add this metadata to an existing build. Preserve quarantine flags.
xattr -d com.apple.FinderInfo "$task_app" 2>/dev/null || true
codesign --force --sign - "$task_app"
codesign --verify --deep --strict "$task_app"
cp "$task_root/설치.command" "$task_root/복원.command" "$task_root/진단.command" "$task_root/README.md" "$task_root/LICENSE" "$task_dist/"
chmod +x "$task_dist/"*.command
ditto -c -k --keepParent --norsrc --noextattr "$task_dist" "$task_root/dist/DNF-Sikarugir-Patch-v0.1.0.zip"
echo "빌드 완료: dist/DNF-Sikarugir-Patch-v0.1.0.zip"
