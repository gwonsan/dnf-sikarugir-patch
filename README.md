# DNF Sikarugir Patch

맥의 기존 Sikarugir 던파 앱에 **홈페이지 GAME START 연결**과 **한글 폰트 설정**을 함께 적용하는 실험적 패치입니다.

## 설치

1. Releases에서 `DNF-Sikarugir-Patch-v0.1.0.zip`을 받아 압축을 풉니다.
2. `설치.command`를 더블클릭합니다. 기본 경로의 `DNF.app`을 찾고, 없으면 앱 선택 창이 뜹니다.
3. 던파 홈페이지에서 로그인하고 GAME START를 누릅니다. 브라우저에서 외부 앱 실행 확인이 뜨면 허용합니다.

다운로드 중에도 이미 설치된 폰트 설정은 적용할 수 있습니다. **한글 변경은 다운로드가 끝난 뒤 런처를 종료하고 다시 실행해야 반영됩니다.** Source Han Sans 폰트가 없는 첫 설치에서는 게임/다운로드를 끝낸 뒤 실행하세요. 설치 프로그램이 Sikarugir의 `fakekorean`으로 폰트를 내려받습니다.

macOS가 다운로드한 명령 파일을 차단하면 **시스템 설정 → 개인정보 보호 및 보안 → 확인 없이 열기**에서 해당 파일을 허용하세요. 패치 앱은 임시 서명만 사용하며 Apple 공증은 되어 있지 않습니다.

## 필요한 환경

- macOS 14.6 이상, 기존 Sikarugir Wine 11 앱. Apple Silicon에서는 Rosetta가 필요합니다.
- 선택한 앱 안에 네오플 공식 플러그인 `NeopleCustomURLStarter.exe`가 이미 설치돼 있어야 합니다.
- Sikarugir와 던파의 설치 파일은 각각 [Sikarugir 공식 저장소](https://github.com/Sikarugir-App/Sikarugir), [던파 공식 다운로드](https://df.nexon.com/data/client)에서 받으세요.

게임, Wine 엔진, 네오플 플러그인을 새로 설치하는 패키지는 아닙니다. 기존 던파 앱을 연결합니다. 여러 앱을 사용한다면 터미널에서 대상 경로를 지정할 수 있습니다.

```sh
bash 설치.command "/path/to/DNF.app"
```

## 변경 내용과 복원

- `~/Applications/DNF Web Launcher.app`을 설치하고 `neople://` 실행 요청을 기존 Wine의 네오플 플러그인으로 전달합니다.
- 요청 URL은 셸을 거치지 않고 한 개의 인자로 전달합니다. URL, 로그인 정보, 인증 인자를 로그로 저장하지 않습니다.
- Sikarugir Wine 11 실행 환경, 기존 앱의 렌더러 선택, `ko_KR.UTF-8`을 사용합니다.
- `fakekorean`과 동일한 16개 한글 글꼴 대체 이름을 Source Han Sans K로 연결합니다. 기존 `fakejapanese`의 일본어 이름은 유지합니다.
- 원래 Sikarugir 앱의 Info.plist 및 실행 파일을 수정하지 않습니다. 다운로드/게임 프로세스를 종료하지 않습니다.
- 최초 백업은 `~/Library/Application Support/DNF Sikarugir Patch/state.plist`에 저장합니다. 같은 앱에 다시 설치해도 백업을 덮어쓰지 않고, 이후 사용자가 바꾼 폰트 이름은 재설치에서도 유지합니다. 동시에 두 번 설치/복원할 수 없도록 잠금을 사용합니다.

패치를 되돌리려면 DNF Web Launcher를 닫고 `복원.command`를 실행하세요. 패치가 바꾼 폰트 이름만 최초 상태로 되돌립니다. 설치 후 별도로 바꾼 폰트 이름은 유지합니다. 이전 URL 처리 앱이 있으면 복원합니다. 이전 앱이 없었다면 패치 앱을 제거하고 macOS가 연결을 정리하게 합니다. 자동으로 받은 폰트 파일은 삭제하지 않습니다.

설치가 중간에 실패해도 복원용 백업은 남습니다. `진단.command`는 Wine 실행, 한글 매핑 수, 홈페이지 연결 상태를 확인합니다.

## 확인 범위

Apple Silicon Mac의 Sikarugir Wine 11에서 홈페이지 요청으로 네오플 런처가 열리고 게임 파일 다운로드가 진행되는 것을 확인했습니다. 패키지의 Wine 실행과 16개 한글 레지스트리 매핑을 검증합니다. **패치 적용 후 화면의 한글 표시, 게임 접속 및 실제 플레이는 아직 확인하지 않았습니다.** Intel용 바이너리도 포함하지만 Intel Mac 실기기에서는 검증하지 않았습니다. 게임 업데이트나 보안 모듈에 따라 추가 문제가 있을 수 있습니다.

## 소스에서 빌드

Xcode Command Line Tools가 설치된 Mac에서 실행합니다. 소스 ZIP으로 받은 경우에도 `설치.command`가 자동으로 빌드합니다. 릴리스 ZIP은 컴파일러 없이 실행할 수 있습니다.

```sh
bash scripts/test.sh
bash scripts/build.sh
```

결과: `dist/DNF-Sikarugir-Patch-v0.1.0.zip` (arm64 + x86_64).

이 저장소에는 게임 파일, Wine, 제삼자 아이콘, 사용자 레지스트리, 진단 로그를 포함하지 않습니다. 패치 코드의 라이선스는 MIT입니다. 폰트 설정의 기준은 [공식 Winetricks](https://github.com/Winetricks/winetricks)의 `fakekorean`이며, 폰트는 Sikarugir가 제공하는 Winetricks를 통해 설치합니다.
