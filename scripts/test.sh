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
