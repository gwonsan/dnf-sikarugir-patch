#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$task_root/build/module-cache"
for task_test in Core Font Lock; do
  task_source=Wine
  if [[ "$task_test" == Font ]]; then task_source=FontPatch; fi
  if [[ "$task_test" == Lock ]]; then task_source=PatchLock; fi
  xcrun swiftc -module-cache-path "$task_root/build/module-cache" "$task_root/Sources/$task_source.swift" \
    "$task_root/Tests/${task_test}Tests.swift" -o "$task_root/build/${task_test}Tests"
  "$task_root/build/${task_test}Tests"
done
xcrun swiftc -module-cache-path "$task_root/build/module-cache" \
  "$task_root/Sources/Wine.swift" "$task_root/Sources/FontPatch.swift" \
  "$task_root/Sources/PatchLock.swift" "$task_root/Sources/Installer.swift" \
  "$task_root/Sources/WrapperFactory.swift" "$task_root/Sources/Bootstrap.swift" "$task_root/Tests/BootstrapTests.swift" \
  -framework AppKit -framework CoreServices -o "$task_root/build/BootstrapTests"
"$task_root/build/BootstrapTests"
xcrun swiftc -module-cache-path "$task_root/build/module-cache" \
  "$task_root/Sources/Wine.swift" "$task_root/Sources/FontPatch.swift" \
  "$task_root/Sources/PatchLock.swift" "$task_root/Sources/Installer.swift" \
  "$task_root/Sources/WrapperFactory.swift" "$task_root/Sources/Bootstrap.swift" "$task_root/Sources/Prepared.swift" "$task_root/Tests/PreparedTests.swift" \
  -framework AppKit -framework CoreServices -o "$task_root/build/PreparedTests"
"$task_root/build/PreparedTests"
python3 -m unittest discover -s "$task_root/Tests" -p test_package_ready.py
