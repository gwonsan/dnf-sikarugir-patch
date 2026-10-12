# DNF Sikarugir Patch

맥에서 Sikarugir로 한국 던전앤파이터를 설치하고 홈페이지의 **GAME START**로 실행하기 위한 도구입니다. **D3DMetal, 한글 폰트, 홈페이지 실행 연결**을 함께 설정합니다.

2026-10-13 기준 Apple Silicon Mac · macOS 26.6.2 · Sikarugir Wine 11 환경에서 홈페이지 실행, 게임 다운로드, 한글 표시와 실제 플레이가 정상 작동한다고 사용자가 확인했습니다. 자세한 검증 기록은 [VALIDATION.md](docs/VALIDATION.md)에 있습니다.

## 시작하기

[Releases](https://github.com/gwonsan/dnf-sikarugir-patch/releases)에서 최신 패치 ZIP을 받아 압축을 풉니다. 릴리스 ZIP은 Xcode 없이 실행할 수 있습니다.

| 현재 상태 | 실행할 파일 |
| --- | --- |
| DNF.app부터 새로 만들기 | `처음설치.command` |
| 이미 만든 DNF.app에 패치 적용 | `설치.command` |
| Wine·폰트·홈페이지 연결 확인 | `진단.command` |
| 패치가 변경한 설정 복원 | `복원.command` |

필요한 환경은 macOS 14.6 이상과 인터넷 연결입니다. Apple Silicon에서는 Rosetta가 필요합니다. 게임용 저장공간은 [공식 다운로드 안내](https://df.nexon.com/data/client)를 확인하세요. 패치 앱은 임시 서명을 사용하며 Apple 공증은 되어 있지 않습니다. macOS가 명령 파일을 차단하면 **시스템 설정 → 개인정보 보호 및 보안 → 확인 없이 열기**에서 해당 파일을 허용하세요.

## 처음부터 설치

1. `처음설치.command`를 더블클릭합니다.
2. 공식 Sikarugir 템플릿과 Wine 11 엔진을 내려받아 `~/Applications/Sikarugir/DNF.app`을 생성합니다. **D3DMetal을 켜고**, Configure의 `fakejapanese`와 같은 Source Han Sans 폰트를 설치합니다. 다운로드와 초기화에는 시간이 걸립니다.
3. 공식 던파 다운로드 페이지가 열리면 약관을 확인하고 통합 플러그인 `NeopleCustomURLBuilder.exe`를 받습니다. 파일 선택 창에서 그 파일을 선택합니다.
4. **Wine에 뜬 네오플 설치 창에서 ‘설치’를 눌러 완료합니다.** 이 버튼은 직접 눌러야 합니다. 터미널은 플러그인 설치가 끝나기를 기다립니다.
5. 설치 확인 후 실행 위치와 한글 폰트 매핑, 홈페이지 연결이 자동 설정됩니다. 던파 홈페이지에 로그인하고 **GAME START**를 눌러 게임을 내려받습니다. 브라우저의 외부 앱 실행 확인은 허용합니다.

Sikarugir Creator를 별도로 조작하지 않아도 빈 앱을 만들 수 있습니다. 템플릿 `1.0.21`, 엔진 `WS12WineSikarugir11.0_1`, Sikarugir의 Winetricks 버전을 고정하고 다운로드의 SHA-256을 확인합니다. 게임·엔진·플러그인 파일은 이 패치 ZIP에 포함되지 않습니다.

기존 `DNF.app`을 덮어쓰지 않습니다. 처음 설치가 취소되거나 중단되면 새로 만든 앱을 보존하고, 같은 명령을 다시 실행하면 이어서 진행합니다. 다른 앱에 적용한 패치가 있다면 `복원.command`로 해당 패치를 복원한 뒤 새 앱에 연결하세요.

새 앱 경로와 이미 받은 플러그인 파일을 터미널에서 지정할 수도 있습니다.

```sh
bash 처음설치.command "$HOME/Applications/Sikarugir/DNF.app" "$HOME/Downloads/NeopleCustomURLBuilder.exe"
```

로그인, 약관 동의, Wine 설치 창의 ‘설치’ 버튼과 게임 다운로드는 공식 설치 절차에 따라 사용자가 진행합니다. 별도 빈 앱에서 앱 생성·폰트·플러그인을 검증하고, 로그인된 홈페이지의 GAME START로 실제 게임 파일이 내려받아지는 것까지 확인했습니다. 새 앱에서 전체 다운로드 완료와 플레이는 아직 검증하지 않았습니다.

## 기존 앱에 적용

1. `설치.command`를 더블클릭합니다. 기본 경로의 `DNF.app`을 찾고, 없으면 앱 선택 창이 뜹니다.
2. 설치가 완료되면 던파 홈페이지에서 로그인하고 **GAME START**를 누릅니다.
3. 폰트 설정을 바꿨다면 다운로드가 끝난 뒤 런처를 종료하고 다시 실행해 한글 표시를 반영합니다.

대상 앱에는 Sikarugir Wine 11과 공식 네오플 플러그인 `NeopleCustomURLStarter.exe`가 있어야 합니다. Source Han Sans 폰트가 없는 앱에는 Configure → Winetricks에서 `fakejapanese` 또는 `fakekorean`을 먼저 적용하세요. 현재 정상 작동하는 앱을 다시 만들 필요는 없습니다.

```sh
bash 설치.command "/path/to/DNF.app"
```

기존 앱 패치는 Info.plist와 실행 파일, 렌더러 선택을 유지합니다. 수동으로 만든 앱의 D3DMetal은 아래 순서대로 Configure에서 켜 주세요.

## Sikarugir Creator로 직접 설치하는 순서

1. [공식 Sikarugir Creator](https://github.com/Sikarugir-App/Sikarugir)에서 `WS12WineSikarugir11.0_1`을 선택하고 빈 `DNF.app`을 만듭니다.
2. 만든 앱 안의 **Configure**를 엽니다.
3. **Configuration → Direct3D to Metal translation layer (D3DMetal)**을 체크합니다.
4. **Winetricks → fonts → fakejapanese → Run**을 실행합니다. Source Han Sans에는 한글 글꼴도 들어 있습니다.
5. **Install Software → Choose Setup Executable**에서 공식 `NeopleCustomURLBuilder.exe`를 선택합니다.
6. **Wine 설치 창에서 ‘설치’를 누릅니다.** Configure가 대기 중이어도 Wine 창의 버튼을 눌러야 진행됩니다.
7. 설치 뒤 **Choose Executable**에서 `C:/Program Files (x86)/NeoplePlugin/NeopleCustomURLStarter.exe`를 선택합니다.
8. 이 패치의 `설치.command`를 실행하고 해당 `DNF.app`을 선택합니다. 홈페이지에서 로그인하고 **GAME START**를 누릅니다.

## 패치가 하는 일

- `~/Applications/DNF Web Launcher.app`을 설치하고 `neople://` 요청을 선택한 앱의 공식 네오플 플러그인에 전달합니다.
- 요청은 셸을 거치지 않고 한 개의 인자로 전달합니다. URL과 로그인·인증 인자를 로그로 남기지 않습니다.
- Sikarugir Wine 11 실행 환경과 `ko_KR.UTF-8`을 사용하고 기존 앱의 렌더러 설정을 반영합니다.
- 16개 한글 글꼴 대체 이름을 Source Han Sans K로 연결합니다. `fakejapanese`의 일본어 매핑도 유지합니다.
- 최초 백업을 `~/Library/Application Support/DNF Sikarugir Patch/state.plist`에 저장합니다. 재설치 시 백업을 덮어쓰지 않고, 사용자가 나중에 바꾸거나 삭제한 폰트 매핑은 유지합니다.
- 동시에 설치·복원·새 앱 생성이 겹치지 않도록 잠금을 사용합니다. 기존 게임이나 다운로드 프로세스를 종료하지 않습니다.

## 복원과 진단

DNF Web Launcher를 닫고 `복원.command`를 실행하면 패치가 변경한 폰트 매핑과 이전 홈페이지 연결을 복원합니다. 이후 사용자가 따로 바꾼 폰트 매핑은 유지합니다. 이전 URL 처리 앱이 없었다면 패치 앱을 제거하고 macOS가 연결을 정리하게 합니다.

새로 만든 `DNF.app`, 설치한 게임·플러그인·폰트와 내려받은 설치 자료는 복원 시 삭제하지 않습니다. 설치 도중 실패해도 복원용 백업은 남습니다. `진단.command`는 Wine 실행, 한글 매핑 수, URL 처리 앱을 확인합니다.

Intel용 실행 파일도 포함하지만 Intel Mac 실기기 검증은 하지 않았습니다. 현재의 작동 확인은 위에 기재한 환경 기준이며 게임·보안 모듈 업데이트 후에는 다시 확인해야 합니다.

## 소스에서 빌드

Xcode Command Line Tools가 설치된 Mac에서 실행합니다. 소스 ZIP의 명령 파일은 패치 앱을 자동으로 빌드합니다.

```sh
bash scripts/test.sh
bash scripts/build.sh
```

결과는 `dist/DNF-Sikarugir-Patch-v0.2.0.zip`이며 arm64와 x86_64를 포함합니다.

이 저장소에는 게임·Wine 바이너리, 사용자 레지스트리·백업, 인증 로그를 포함하지 않습니다. 패치 코드의 라이선스는 MIT입니다. Sikarugir, Wine, 네오플 플러그인과 폰트는 각 배포처의 라이선스를 따릅니다. 폰트 설정은 [공식 Winetricks의 fakekorean](https://github.com/Winetricks/winetricks)을 기준으로 하며, 처음 설치의 폰트 도구는 [Sikarugir의 Winetricks](https://github.com/Sikarugir-App/winetricks/tree/sikarugir)를 사용합니다.
