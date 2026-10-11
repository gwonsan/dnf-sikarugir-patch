#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")" && pwd)"
task_binary="$task_root/DNF Web Launcher.app/Contents/MacOS/DNFWebLauncher"
if [[ ! -x "$task_binary" ]]; then
  /bin/bash "$task_root/scripts/build.sh"
  task_binary="$task_root/dist/DNF-Sikarugir-Patch/DNF Web Launcher.app/Contents/MacOS/DNFWebLauncher"
fi
task_code=0
"$task_binary" --diagnose "$@" || task_code=$?
if [[ -t 0 ]]; then read -r -p "Enter를 누르면 종료합니다."; fi
exit "$task_code"
