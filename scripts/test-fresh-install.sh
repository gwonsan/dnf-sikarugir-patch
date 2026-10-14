#!/bin/bash
# Opt-in integration test. Uses real Wine and pinned downloads; keeps logs in a new temp directory.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -ne 1 ]]; then
  echo "Usage: bash scripts/test-fresh-install.sh /path/to/prepared/DNF.app" >&2
  exit 2
fi
task_source="$(cd "$1" && pwd)"
task_probe="$(mktemp -d "${TMPDIR:-/tmp/}dnf-fresh-install.XXXXXX")"
mkdir -p "$task_root/build/module-cache"
xcrun swiftc -module-cache-path "$task_root/build/module-cache" \
  "$task_root/Sources/Wine.swift" "$task_root/Sources/FontPatch.swift" \
  "$task_root/Sources/PatchLock.swift" "$task_root/Sources/Installer.swift" \
  "$task_root/Sources/WrapperFactory.swift" "$task_root/Sources/Bootstrap.swift" \
  "$task_root/Sources/Prepared.swift" "$task_root/Tests/FreshInstallSmoke.swift" \
  -framework AppKit -framework CoreServices -o "$task_probe/fresh-install-check"
echo "Fresh installation test and logs: $task_probe"
"$task_probe/fresh-install-check" "$task_source" "$task_probe/DNF.app"
