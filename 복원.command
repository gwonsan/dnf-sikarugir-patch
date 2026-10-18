#!/bin/bash
set -euo pipefail

# Close only this command's completed Terminal window; preserve active shells.
task_terminal_helper=""
task_terminal_finish() {
  local task_status=$?
  trap - EXIT
  if [[ "$task_status" -ne 0 && -t 0 ]]; then
    read -r -p "Enter를 누르면 종료합니다." || true
  fi
  if [[ "${TERM_PROGRAM:-}" == "Apple_Terminal" && -t 0 && -x "$task_terminal_helper" ]]; then
    local task_tty
    task_tty="$(/usr/bin/tty)"
    "$task_terminal_helper" --close-terminal "$task_tty" </dev/null >/dev/null 2>&1 &
  fi
  exit "$task_status"
}
trap task_terminal_finish EXIT
task_root="$(cd "$(dirname "$0")" && pwd)"
task_binary="$task_root/DNF Web Launcher.app/Contents/MacOS/DNFWebLauncher"
if [[ ! -x "$task_binary" ]]; then
  /bin/bash "$task_root/scripts/build.sh"
  task_binary="$task_root/dist/DNF-Sikarugir-Patch-dev/설치 자료/DNF Web Launcher.app/Contents/MacOS/DNFWebLauncher"
fi
task_terminal_helper="$task_binary"
task_code=0
"$task_binary" --uninstall "$@" || task_code=$?
exit "$task_code"
