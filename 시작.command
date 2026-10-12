#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")" && pwd)"
task_binary="$task_root/DNF Web Launcher.app/Contents/MacOS/DNFWebLauncher"
task_ready="$task_root/DNF.app"
if [[ ! -x "$task_binary" || ! -d "$task_ready" ]]; then
  echo "준비된 앱이 포함된 DNF-Ready ZIP을 압축 해제한 폴더에서 실행하세요."
  if [[ -t 0 ]]; then read -r -p "Enter를 누르면 종료합니다."; fi
  exit 1
fi
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" == "1" ]] && ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
  echo "Rosetta가 필요합니다. 아래 Apple 약관을 확인하고 동의하면 설치가 진행됩니다."
  /usr/sbin/softwareupdate --install-rosetta
  /usr/bin/arch -x86_64 /usr/bin/true
fi
if "$task_binary" --install-ready "$task_ready" "$@"; then
  echo "설정 완료. 열린 던파 홈페이지에서 로그인하고 GAME START를 눌러 주세요."
else
  echo "위 오류를 확인하고 시작.command를 다시 실행하세요. 기존 앱과 백업은 보존됩니다."
  if [[ -t 0 ]]; then read -r -p "Enter를 누르면 종료합니다."; fi
  exit 1
fi
if [[ -t 0 ]]; then read -r -p "Enter를 누르면 종료합니다."; fi
