#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")" && pwd)"
task_binary="$task_root/DNF Web Launcher.app/Contents/MacOS/DNFWebLauncher"
if [[ ! -x "$task_binary" ]]; then
  /bin/bash "$task_root/scripts/build.sh"
  task_binary="$task_root/dist/DNF-Sikarugir-Patch/DNF Web Launcher.app/Contents/MacOS/DNFWebLauncher"
fi
echo "설치 명령 파일과 도우미의 다운로드 차단 표시 해제 중…"
if ! /usr/bin/xattr -drs com.apple.quarantine "$0" "${task_binary%/Contents/MacOS/DNFWebLauncher}"; then
  echo "실행 허용 준비에 실패했습니다. 압축 해제 폴더의 쓰기 권한과 위 오류를 확인하세요."
  if [[ -t 0 ]]; then read -r -p "Enter를 누르면 종료합니다."; fi
  exit 1
fi
if "$task_binary" --install "$@"; then
  echo "설치가 끝났습니다. 이 창을 닫아도 됩니다."
else
  echo "설치 실패. 위 오류를 확인하세요. 최초 백업은 유지됩니다."
  if [[ -t 0 ]]; then read -r -p "Enter를 누르면 종료합니다."; fi
  exit 1
fi
if [[ -t 0 ]]; then read -r -p "Enter를 누르면 종료합니다."; fi
