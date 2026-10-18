#!/bin/bash
set -u

task_finish() {
  local task_status="$1"
  if [[ "$task_status" -ne 0 && -t 0 ]]; then
    read -r -p "Enter를 누르면 종료합니다." || true
  fi
  exit "$task_status"
}

task_root="$(cd "$(dirname "$0")" && pwd)" || task_finish 1
task_helper="$task_root/설치 자료/DNF Web Launcher.app"
task_binary="$task_helper/Contents/MacOS/DNFWebLauncher"

# Package components must be actual extracted files, never links to another app.
for task_component in "$task_root/설치 자료" "$task_helper" "$task_helper/Contents" "$task_helper/Contents/MacOS" "$task_binary"; do
  if [[ -L "$task_component" ]]; then
    echo "설치 자료에 잘못된 링크가 있습니다. ZIP 전체를 새 폴더에 다시 압축 해제하세요."
    task_finish 1
  fi
done
if [[ ! -f "$task_binary" || ! -x "$task_binary" ]]; then
  echo "설치 자료의 DNF Web Launcher.app을 찾을 수 없습니다. ZIP 전체를 압축 해제하고 던파.command와 설치 자료 폴더를 함께 두세요."
  task_finish 1
fi

# -s keeps recursive removal from following links outside this exact helper.
if ! /usr/bin/xattr -drs com.apple.quarantine "$0" "$task_helper"; then
  echo "실행 허용 준비에 실패했습니다. 압축 해제 폴더의 쓰기 권한과 위 오류를 확인하세요."
  task_finish 1
fi

"$task_binary" --menu "$task_root"
task_status=$?
if [[ "$task_status" -ne 0 ]]; then
  echo "던파 메뉴가 종료되었습니다. 위 오류를 확인한 뒤 다시 실행하세요."
fi
task_finish "$task_status"
