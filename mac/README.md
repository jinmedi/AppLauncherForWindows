# AppLauncher for macOS

Windows용 런처와 같은 기능을 가진 macOS 메뉴 막대 앱입니다. 전역 단축키(기본 **오른쪽 `⌥` + `Return`**)로 검색창을 띄우고, 설치된 앱과 주요 폴더를 퍼지 검색으로 찾아 Enter로 실행하거나 Finder로 엽니다.

Swift + AppKit로 작성되어 .NET이 필요 없고, 결과물은 몇 MB짜리 `.app` 하나입니다.

## 기능 (Windows판과 동일)

- 오른쪽 `⌥` + `Return`: 창 열기/닫기. 다른 앱의 포커스를 빼앗지 않는 떠 있는 패널로 열립니다. 왼쪽 Option은 그대로 두므로 다른 앱의 `⌥Return` 단축키와 충돌하지 않습니다. 설정 파일에 다른 `Hotkey`가 있어도 오른쪽 `⌥Return`은 함께 등록됩니다(`AdditionalHotkeys`)
- 창이 열리면 키보드가 영어 자판(ABC/U.S.)으로 바뀌고, 닫히면 원래 입력 소스로 돌아갑니다. 한글로 검색하려면 창 안에서 평소처럼 한/영을 바꾸면 됩니다 (`ForceEnglishInput`으로 끌 수 있음)
- 글자 입력: 결과 최대 8개, 첫 항목 자동 선택. 각 행 오른쪽에 "앱" 또는 "폴더" 표시
- `↑` `↓` 선택 이동, `Enter` 또는 클릭: 앱 실행 또는 폴더를 Finder로 열고 창 숨김
- `⌘1` ~ `⌘7`: 선택을 옮기지 않고 2번째~8번째 결과를 바로 실행 (`⌃1`~`⌃7`도 됩니다). 각 행 오른쪽에 해당 키가 표시됩니다
- 한글 이름("카카오톡")과 영어 이름·실행 파일 이름("kakao") 어느 쪽으로도 검색됩니다. 앱 번들의 한국어·영어 `InfoPlist.strings`를 모두 읽으므로 시스템 언어와 무관합니다
- 폴더는 Finder가 보여주는 이름("다운로드")과 실제 이름("Downloads") 양쪽으로 검색됩니다
- 자주 실행한 항목이 위로 올라옵니다. 실행 횟수(최대 +300), 최근 실행(하루 이내 +60, 일주일 +40, 한 달 +20), 같은 검색어로 실행한 적이 있으면 +400(일부만 겹치면 +200). Windows판과 같은 `history.json` 형식입니다
- `Esc` 또는 포커스 이탈: 창 숨김
- 메뉴 막대 아이콘 왼쪽 클릭: 창 열기/닫기, 오른쪽 클릭: 메뉴(열기, 종료)
- 앱이 이미 실행 중일 때 다시 실행하면 기존 창을 보여주고 종료합니다

### 인덱싱 대상

- 앱: `~/Applications`, `/Applications`, `/System/Applications`, `/System/Library/CoreServices/Applications`와 그 하위 폴더(3단계). `Uninstall`, `제거`, `삭제`가 이름에 든 번들은 제외
- 폴더: 데스크탑, 문서, 다운로드, 사진, 동영상, 음악, 홈 폴더와 그 하위 2단계
- 클라우드: iCloud Drive, `~/Library/CloudStorage` 아래의 Google Drive(내 드라이브·공유 드라이브·다른 컴퓨터), OneDrive, Dropbox, Box 등, 예전 클라이언트가 홈 폴더에 만든 `Google Drive`/`Dropbox`/`OneDrive`, `~/.dropbox/info.json`에 적힌 경로
- 숨김 폴더(`~/Library` 포함), `.`으로 시작하는 폴더, 심볼릭 링크, 패키지(.app, 사진 보관함 등), `node_modules`, `bin`, `obj`는 건너뜁니다

## 설치

[Releases](https://github.com/jinmedi/AppLauncherForWindows/releases)에서 `AppLauncher-vX.Y.Z-mac-universal.zip`을 내려받아 풀고 `AppLauncher.app`을 `/Applications`(또는 `~/Applications`)에 넣습니다. Apple Silicon과 Intel 모두 지원하는 유니버설 바이너리입니다.

- 애플 개발자 인증서로 서명되지 않았으므로 처음 열 때 "확인되지 않은 개발자" 경고가 뜹니다. Finder에서 앱을 **오른쪽 클릭 → 열기**, 또는 시스템 설정 → 개인정보 보호 및 보안에서 "확인 없이 열기"를 누르면 됩니다. 터미널에서 `xattr -dr com.apple.quarantine /Applications/AppLauncher.app`을 실행해도 됩니다
- **손쉬운 사용 권한**: 오른쪽 Option처럼 왼쪽/오른쪽을 구분하는 단축키는 macOS가 기본 제공하는 단축키 API로는 등록할 수 없어 키보드 이벤트 탭을 씁니다. 첫 실행 때 권한 요청 창이 뜨면 시스템 설정 → 개인정보 보호 및 보안 → **손쉬운 사용**에서 App Launcher를 켜고 앱을 다시 실행하세요. 권한이 없는 동안은 양쪽 `⌥Return` 모두로 동작합니다. 앱을 새로 빌드하면(ad-hoc 서명이 바뀌어) 권한을 다시 켜야 할 수 있습니다. `Hotkey`를 `"Cmd+Shift+Space"`처럼 좌우 구분 없는 조합으로 바꾸면 권한이 필요 없습니다
- 로그인 시 자동 실행: `settings.json`의 `StartAtLogin`을 `true`로 바꾸거나 시스템 설정 → 일반 → 로그인 항목에 추가하세요
- 업데이트는 `.app`만 바꾸면 됩니다. 설정과 기록은 `~/Library/Application Support/AppLauncherForMac/`에 따로 있습니다
- 옆에 있는 `.sha256` 파일로 검증할 수 있습니다: `shasum -a 256 -c AppLauncher-vX.Y.Z-mac-universal.zip.sha256`

## 빌드와 실행

Xcode 15 이상(또는 Command Line Tools)과 macOS 13 이상이 필요합니다. `mac/` 폴더에서:

```bash
swift build
```

```bash
swift test
```

```bash
swift run AppLauncher
```

`swift run`으로 띄우면 번들이 없어 로그인 항목 등록과 단일 인스턴스 확인은 건너뜁니다. 실제 `.app`을 만들려면:

```bash
Scripts/build-app.sh
```

`build/AppLauncher.app`이 나옵니다(유니버설, ad-hoc 서명). 개발 중에는 `UNIVERSAL=0 Scripts/build-app.sh`가 더 빠릅니다.

## 구조

```
mac/
  Package.swift                       SwiftPM 매니페스트 (macOS 13+)
  Resources/Info.plist                번들 메타데이터 (LSUIElement = 메뉴 막대 전용)
  Scripts/build-app.sh                .app 번들 조립 + ad-hoc 서명
  Sources/LauncherCore/               UI 의존 없는 라이브러리 (Linux에서도 빌드·테스트 가능)
    Models/AppEntry.swift             인덱스 항목
    Models/HotkeySpec.swift           "RightOption+Return" 파싱, Carbon 키 코드·CGEvent 플래그 매칭
    Models/LauncherSettings.swift     설정 (Windows판과 같은 JSON 키)
    Search/FuzzyMatcher.swift         정확 > 접두 > 단어 시작 > 약어 > 포함 > 순서 일치 (NFC 정규화)
    Search/AppSearcher.swift          이름 + 키워드 랭킹, 다중 단어, 사용 기록 가산점
    Services/AppIndex.swift           소스 병합, 동시 갱신
    Services/UsageHistory.swift       실행 횟수·최근 실행·검색어 기록 (history.json)
    Services/SettingsStore.swift      settings.json 읽기/쓰기
    Services/AppPaths.swift           Application Support 경로, ~/$VAR 확장, 원자적 쓰기
    Indexing/ApplicationScanner.swift .app 번들 열거, Info.plist·InfoPlist.strings 읽기
    Indexing/FolderScanner.swift      루트 폴더와 하위 폴더 인덱싱, Finder 표시 이름
    Indexing/FolderRootResolver.swift 홈 폴더·클라우드 루트 감지
  Sources/AppLauncher/                AppKit 실행 파일
    main.swift / AppDelegate.swift    시작, 단일 인스턴스, 단축키·메뉴 막대 등록
    LauncherPanel.swift               비활성화 패널 (포커스를 빼앗지 않음), ⌘숫자 가로채기
    LauncherWindowController.swift    표시 위치, 토글, 포커스 이탈 시 숨김
    LauncherView.swift                검색창, 결과 표, 상태·힌트 줄
    ResultRowView.swift               행 하이라이트, 아이콘·이름·경로·배지
    MainViewModel.swift               검색, 선택 이동, 실행
    GlobalHotkey.swift                Carbon RegisterEventHotKey 래퍼 (좌우 구분 없는 조합)
    EventTapHotkey.swift              CGEvent 탭 (오른쪽 Option 등 좌우 구분 조합, 손쉬운 사용 권한)
    InputSourceSwitcher.swift         창 열 때 영어 자판으로, 닫을 때 원래대로 (TIS API)
    StatusBarController.swift         NSStatusItem (좌클릭 토글, 우클릭 메뉴)
    WorkspaceLauncher.swift           NSWorkspace로 앱 실행 / Finder로 폴더 열기
    IconCache.swift                   NSWorkspace 아이콘 캐시
    IndexLogWriter.swift              index.log
    LoginItem.swift                   SMAppService 로그인 항목
  Tests/LauncherCoreTests/            XCTest
```

## 설정

첫 실행 때 `~/Library/Application Support/AppLauncherForMac/settings.json`이 기본값으로 만들어집니다. 수정 후 런처를 다시 시작하면 적용됩니다.

```json
{
  "Hotkey": "RightOption+Return",
  "AdditionalHotkeys": ["RightOption+Return"],
  "StartAtLogin": false,
  "IncludeKnownFolders": true,
  "IncludeCloudDrives": true,
  "FolderRoots": [],
  "FolderScanDepth": 2,
  "ForceEnglishInput": true
}
```

- `Hotkey`: 예 `"Cmd+Shift+Space"`, `"Ctrl+Option+K"`, `"⌘+⇧+Space"`, `"LeftCmd+Return"`. 수식어는 `Ctrl`, `Option`(`Alt`), `Shift`, `Cmd`(`Win`)와 좌우 구분형 `LeftOption`/`RightOption`(`RAlt`), `LeftCmd`/`RightCmd`. 좌우 구분형은 손쉬운 사용 권한이 필요합니다. Windows판 파일의 `Alt`는 Option으로, `Win`은 Cmd로 읽습니다
- `AdditionalHotkeys`: `Hotkey`와 함께 등록할 조합의 목록으로, 형식은 `Hotkey`와 같습니다. 기본값이 `["RightOption+Return"]`이어서 예전 설정 파일에 `"Hotkey": "Cmd+Shift+Space"`가 남아 있어도 두 조합 모두로 열립니다. 중복이나 해석할 수 없는 항목은 건너뛰고, `[]`로 두면 `Hotkey`만 등록합니다
- `StartAtLogin`: `true`면 시작할 때 로그인 항목으로 등록합니다 (`.app`으로 실행한 경우만)
- `ForceEnglishInput`: `true`(기본)면 창이 열릴 때 사용 가능한 영어 자판(ABC, U.S. 우선)으로 바꾸고 닫힐 때 되돌립니다. 영어 자판이 입력 소스 목록에 없으면 아무 것도 하지 않습니다
- `IncludeKnownFolders`, `IncludeCloudDrives`, `FolderRoots`, `FolderScanDepth`: Windows판과 같습니다. `FolderRoots`에는 `~/Projects`, `$HOME/Work`처럼 쓸 수 있습니다

### 폴더가 안 보일 때

인덱싱이 끝날 때마다 같은 폴더의 `index.log`가 다시 쓰입니다. 어떤 루트가 사용됐는지, 각 소스가 몇 개를 읽었는지, 실패했다면 어떤 오류였는지 적혀 있습니다.

## CI와 릴리스

- **CI (macOS)** (`.github/workflows/ci-mac.yml`): PR과 main 푸시마다 `macos-15` 러너에서 `swift build`, `swift test`, 번들 조립까지 돌리고 zip을 아티팩트로 14일간 보관합니다.
- **Release** (`.github/workflows/release.yml`): `v*` 태그를 푸시하면 Windows exe 릴리스가 만들어진 뒤 `release-mac` 잡이 유니버설 `.app`을 zip으로 묶어 같은 릴리스에 `.sha256`과 함께 첨부합니다.
