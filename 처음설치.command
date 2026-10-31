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
echo "설치 명령 파일과 도우미의 다운로드 차단 표시 해제 중…"
if ! /usr/bin/xattr -drs com.apple.quarantine "$0" "${task_binary%/Contents/MacOS/DNFWebLauncher}"; then
  echo "실행 허용 준비에 실패했습니다. 압축 해제 폴더의 쓰기 권한과 위 오류를 확인하세요."
  exit 1
fi
task_terminal_helper="$task_binary"
if "$task_binary" --setup "$@"; then
  echo "처음 설치가 끝났습니다. 홈페이지에서 로그인하고 GAME START를 눌러 주세요."
else
  echo "설치가 중단됐습니다. 위 오류를 확인하세요. 새 앱과 최초 백업은 보존됩니다."
  exit 1
fi
