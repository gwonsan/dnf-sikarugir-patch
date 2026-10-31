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
  -framework AppKit -framework CoreServices -framework Carbon -framework IOKit -o "$task_root/build/BootstrapTests"
"$task_root/build/BootstrapTests"
xcrun swiftc -module-cache-path "$task_root/build/module-cache" \
  "$task_root/Sources/Wine.swift" "$task_root/Sources/FontPatch.swift" \
  "$task_root/Sources/PatchLock.swift" "$task_root/Sources/Installer.swift" \
  "$task_root/Sources/WrapperFactory.swift" "$task_root/Sources/Bootstrap.swift" "$task_root/Sources/Prepared.swift" "$task_root/Tests/PreparedTests.swift" \
  -framework AppKit -framework CoreServices -framework Carbon -framework IOKit -o "$task_root/build/PreparedTests"
"$task_root/build/PreparedTests"
for task_test in Recovery Bridge BridgeLifecycle; do
  xcrun swiftc -module-cache-path "$task_root/build/module-cache" \
    "$task_root/Sources/Wine.swift" "$task_root/Sources/FontPatch.swift" \
    "$task_root/Sources/PatchLock.swift" "$task_root/Sources/Installer.swift" \
    "$task_root/Sources/KeyMapping.swift" "$task_root/Sources/KeyEventDelivery.swift" "$task_root/Sources/Karabiner.swift" "$task_root/Sources/KarabinerDelivery.swift" "$task_root/Sources/KarabinerSocket.swift" "$task_root/Sources/KarabinerRuntime.swift" "$task_root/Sources/KeyboardAgent.swift" "$task_root/Sources/GameSettings.swift" "$task_root/Sources/Bridge.swift" "$task_root/Tests/${task_test}Tests.swift" \
    -framework AppKit -framework CoreServices -framework Carbon -framework IOKit -o "$task_root/build/${task_test}Tests"
  "$task_root/build/${task_test}Tests"
done
for task_test in TerminalTests TerminalHarness; do
  xcrun swiftc -module-cache-path "$task_root/build/module-cache" \
    "$task_root/Sources/Wine.swift" "$task_root/Sources/FontPatch.swift" \
    "$task_root/Sources/PatchLock.swift" "$task_root/Sources/Installer.swift" \
    "$task_root/Sources/KeyMapping.swift" "$task_root/Sources/KeyEventDelivery.swift" "$task_root/Sources/Karabiner.swift" "$task_root/Sources/KarabinerDelivery.swift" "$task_root/Sources/KarabinerSocket.swift" "$task_root/Sources/KarabinerRuntime.swift" "$task_root/Sources/KeyboardAgent.swift" "$task_root/Sources/GameSettings.swift" "$task_root/Sources/KeyboardUI.swift" "$task_root/Sources/GameSettingsUI.swift" "$task_root/Sources/TerminalUI.swift" "$task_root/Sources/InteractiveCommand.swift" "$task_root/Tests/$task_test.swift" \
    -framework AppKit -framework CoreServices -framework Carbon -framework IOKit -o "$task_root/build/$task_test"
done
"$task_root/build/TerminalTests"
xcrun swiftc -module-cache-path "$task_root/build/module-cache" \
  "$task_root/Sources/TerminalSession.swift" "$task_root/Tests/TerminalSessionTests.swift" \
  -framework AppKit -o "$task_root/build/TerminalSessionTests"
"$task_root/build/TerminalSessionTests"
xcrun swiftc -module-cache-path "$task_root/build/module-cache" \
  "$task_root/Sources/Wine.swift" "$task_root/Sources/FontPatch.swift" \
  "$task_root/Sources/PatchLock.swift" "$task_root/Sources/Installer.swift" \
  "$task_root/Sources/InteractiveCommand.swift" "$task_root/Tests/InteractiveHarness.swift" \
  -framework AppKit -framework CoreServices -framework Carbon -framework IOKit -o "$task_root/build/InteractiveHarness"
python3 -m unittest discover -s "$task_root/Tests" -p 'test_*.py'

xcrun swiftc -module-cache-path "$task_root/build/module-cache" "$task_root/Sources/KeyMapping.swift" "$task_root/Sources/KeyEventDelivery.swift" \
  "$task_root/Tests/KeyMappingTests.swift" -o "$task_root/build/KeyMappingTests"
"$task_root/build/KeyMappingTests"

xcrun swiftc -module-cache-path "$task_root/build/module-cache" \
  "$task_root/Sources/Wine.swift" "$task_root/Sources/FontPatch.swift" \
  "$task_root/Sources/PatchLock.swift" "$task_root/Sources/Installer.swift" "$task_root/Tests/BundleMetadataTests.swift" \
  -framework AppKit -framework CoreServices -o "$task_root/build/BundleMetadataTests"
"$task_root/build/BundleMetadataTests"

xcrun swiftc -module-cache-path "$task_root/build/module-cache" "$task_root/Sources/KeyMapping.swift" "$task_root/Sources/KeyEventDelivery.swift" \
  "$task_root/Tests/EventTapLifecycleTests.swift" -framework AppKit -o "$task_root/build/EventTapLifecycleTests"
"$task_root/build/EventTapLifecycleTests"

for task_test in Karabiner KarabinerRuntime KarabinerDelivery; do
  xcrun swiftc -module-cache-path "$task_root/build/module-cache" "$task_root/Sources/KeyMapping.swift" "$task_root/Sources/KeyEventDelivery.swift" "$task_root/Sources/Karabiner.swift" "$task_root/Sources/KarabinerDelivery.swift" "$task_root/Sources/KarabinerSocket.swift" "$task_root/Sources/KarabinerRuntime.swift" "$task_root/Tests/${task_test}Tests.swift" -o "$task_root/build/${task_test}Tests"
  "$task_root/build/${task_test}Tests"
done

xcrun swiftc -module-cache-path "$task_root/build/module-cache" "$task_root/Sources/Wine.swift" "$task_root/Sources/GameSettings.swift" "$task_root/Tests/GameSettingsTests.swift" -o "$task_root/build/GameSettingsTests"
"$task_root/build/GameSettingsTests"

xcrun swiftc -module-cache-path "$task_root/build/module-cache" "$task_root/Sources/KarabinerSocket.swift" "$task_root/Tests/KarabinerSocketTests.swift" -o "$task_root/build/KarabinerSocketTests"
"$task_root/build/KarabinerSocketTests"

xcrun swiftc -module-cache-path "$task_root/build/module-cache" "$task_root/Sources/KeyMapping.swift" "$task_root/Sources/KeyEventDelivery.swift" "$task_root/Tests/KeyEventDeliveryTests.swift" -o "$task_root/build/KeyEventDeliveryTests"
"$task_root/build/KeyEventDeliveryTests"
