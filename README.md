# AppLauncherForWindows

Windows용 경량 앱 런처입니다. 전역 단축키(기본 `Alt+Space`)로 검색창을 띄우고, 설치된 앱을 빠르게 찾아 실행하는 것을 목표로 합니다.

같은 기능의 **macOS용 런처**는 [`mac/`](mac/README.md)에 있습니다 (Swift + AppKit, 기본 단축키 `⌥Space`, 릴리스마다 `AppLauncher-vX.Y.Z-mac-universal.zip`이 함께 첨부됩니다).

## 현재 상태

2단계 + 폴더. 시작 메뉴(사용자 + 공용)의 바로가기와 주요 폴더를 인덱싱하고, 퍼지 검색으로 찾아 Enter로 실행하거나 Explorer로 엽니다.
한글 이름("카카오톡")과 실행 파일 이름("kakao") 어느 쪽으로도 검색되고, 폴더는 "다운로드"처럼 Explorer의 한글 이름으로도 찾을 수 있습니다.
스토어 앱(메모장, 계산기 등 UWP)은 아직 목록에 없고 5단계에서 추가됩니다.

## 기술 스택

- .NET 9 / C# 13
- WPF (MVVM, CommunityToolkit.Mvvm)
- Microsoft.Extensions.DependencyInjection
- H.NotifyIcon.Wpf (트레이 아이콘)
- xUnit

## 구조

```
AppLauncherForWindows.sln
mac/                               macOS용 런처 (Swift 패키지, 자세한 내용은 mac/README.md)
Directory.Build.props              공통 빌드 설정 (Nullable, ImplicitUsings 등)
src/
  AppLauncher.App/                 WPF 실행 프로젝트 (UI 전용)
    App.xaml(.cs)                  시작, 단일 인스턴스, DI, 단축키/트레이 등록
    Views/MainWindow.xaml(.cs)     런처 창 (검색창, 결과 목록, 키보드 탐색)
    ViewModels/MainViewModel.cs    검색, 선택 이동, 실행
    ViewModels/SearchResultViewModel.cs
    Interop/GlobalHotkey.cs        RegisterHotKey 래퍼
    Interop/IconExtractor.cs       SHGetFileInfo로 셸 아이콘 추출 (캐시)
    Interop/NativeMethods.cs       Win32 P/Invoke
    app.manifest                   PerMonitorV2 DPI, asInvoker
  AppLauncher.Core/                UI 의존 없는 클래스 라이브러리
    Models/AppEntry.cs             인덱스 항목
    Models/HotkeySpec.cs           "Ctrl+Alt+K" 형식 파싱/직렬화
    Models/LauncherSettings.cs
    Indexing/StartMenuScanner.cs   시작 메뉴 .lnk 열거, 제거 프로그램/문서 링크 제외, 중복 제거
    Indexing/ShellLinkResolver.cs  IShellLinkW COM으로 .lnk 대상 해석
    Indexing/FolderScanner.cs      설정된 루트 폴더와 하위 폴더(기본 2단계) 인덱싱
    Search/FuzzyMatcher.cs         정확 > 접두 > 단어 시작 > 약어 > 포함 > 순서 일치 순 점수
    Search/AppSearcher.cs          이름 + 키워드 랭킹, 다중 단어 질의, 사용 기록 가산점
    Services/AppIndex.cs           소스 병합, 백그라운드 갱신
    Services/UsageHistory.cs       실행 횟수·최근 실행·검색어 기록 (history.json)
    Services/IAppLauncher.cs       ShellExecute로 .lnk 실행
    Services/SettingsStore.cs      %APPDATA%\AppLauncherForWindows\settings.json
tests/
  AppLauncher.Core.Tests/          xUnit
```

## 설치

[Releases](https://github.com/jinmedi/AppLauncherForWindows/releases)에서 `AppLauncher-vX.Y.Z-win-x64.exe`를 내려받아 원하는 폴더(예: `C:\Tools\AppLauncher\`)에 두고 실행하면 됩니다. .NET 설치가 필요 없는 단독 실행 파일입니다.

- 서명되지 않은 프로그램이라 첫 실행 때 SmartScreen 경고가 뜹니다. "추가 정보" → "실행"을 누르면 됩니다.
- Windows 시작 시 자동 실행은 아직 앱에 없습니다. `Win+R` → `shell:startup` 폴더에 exe 바로가기를 넣으세요.
- 업데이트는 exe만 덮어쓰면 됩니다. 설정은 `%APPDATA%`에 따로 있어 유지됩니다.
- 옆에 있는 `.sha256` 파일로 내려받은 파일을 검증할 수 있습니다: `certutil -hashfile AppLauncher-vX.Y.Z-win-x64.exe SHA256`

## 빌드와 실행

```bash
dotnet build
dotnet test
dotnet run --project src/AppLauncher.App
```

실행하면 런처 창이 한 번 표시되고 트레이에 상주합니다. 인덱싱은 백그라운드에서 돌고, 끝나면 하단에 "앱 N개 · 폴더 M개"가 표시됩니다.

- `Alt+Space`: 창 열기/닫기
- 글자 입력: 결과 최대 8개 표시, 첫 항목 자동 선택. 각 행 오른쪽에 "앱" 또는 "폴더" 표시
- `↑` `↓`: 선택 이동, `Enter` 또는 클릭: 앱 실행 또는 폴더 열기 후 창 숨김
- `Ctrl+1` ~ `Ctrl+7`: 선택을 옮기지 않고 2번째~8번째 결과를 바로 실행. 각 행 오른쪽에 해당 키가 표시됩니다 (1번째는 `Enter`)
- 자주 실행한 항목이 위로 올라옵니다. 실행 횟수(최대 +300), 최근 실행(하루 이내 +60, 일주일 +40, 한 달 +20), 같은 검색어로 실행한 적이 있으면 +400(검색어가 일부만 겹치면 +200)을 매칭 점수에 더합니다. 기록은 `%APPDATA%\AppLauncherForWindows\history.json`에 저장되며, 6개월간 실행하지 않은 항목은 정리됩니다. 파일을 지우면 초기화됩니다
- `Esc` 또는 포커스 이탈: 창 숨김
- 트레이 아이콘 왼쪽 클릭: 창 열기/닫기, 오른쪽 클릭: 메뉴(열기, 종료)

### 직접 배포 파일 만들기

```bash
dotnet publish src/AppLauncher.App -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=none -o publish/win-x64
```

`publish/win-x64/AppLauncher.exe` 하나가 나옵니다(약 146MB). `--self-contained false`로 바꾸면 25MB짜리가 나오지만 대상 PC에 .NET 9 Desktop Runtime이 있어야 합니다.

## CI와 릴리스

- **CI** (`.github/workflows/ci.yml`): PR과 main 푸시마다 빌드(경고를 오류로 처리), 테스트, publish까지 돌리고 exe를 워크플로 아티팩트로 14일간 보관합니다.
- **CI (macOS)** (`.github/workflows/ci-mac.yml`): 같은 트리거로 `macos-15` 러너에서 `mac/`의 Swift 패키지를 빌드·테스트하고 `.app` zip을 아티팩트로 보관합니다.
- **Release** (`.github/workflows/release.yml`): `v*` 태그를 푸시하면 태그 버전으로 빌드·테스트·publish한 뒤 GitHub Release를 만들고 exe와 `.sha256`을 첨부합니다. 이어서 `release-mac` 잡이 macOS 유니버설 `.app` zip과 `.sha256`을 같은 릴리스에 추가합니다. `v0.2.0-beta.1`처럼 하이픈이 있으면 pre-release로 표시됩니다.

릴리스 절차:

```bash
git tag v0.1.0
```

```bash
git push origin v0.1.0
```

## 설정

첫 실행 때 `%APPDATA%\AppLauncherForWindows\settings.json`이 기본값으로 만들어집니다. 수정 후 런처를 다시 시작하면 적용됩니다.

```json
{
  "Hotkey": "Alt+Space",
  "StartWithWindows": false,
  "IncludeKnownFolders": true,
  "IncludeCloudDrives": true,
  "FolderRoots": [],
  "FolderScanDepth": 2
}
```

- `Hotkey`: 예 `"Ctrl+Shift+Space"`, `"Win+K"`
- `IncludeKnownFolders`: 바탕 화면, 문서, 다운로드, 사진, 동영상, 음악, 사용자 홈 폴더
- `IncludeCloudDrives`: 실행할 때마다 자동 감지합니다. OneDrive(개인·회사, 환경 변수 기준), Google Drive(스트리밍 모드의 가상 드라이브 `G:\내 드라이브`, `공유 드라이브` 등과 미러 모드 폴더), Dropbox(`info.json` 기준), iCloud Drive
- `FolderRoots`: 위에 더해 인덱싱할 폴더. `%USERPROFILE%` 같은 환경 변수를 쓸 수 있습니다. 두 플래그를 끄고 여기만 채우면 원하는 폴더만 검색됩니다
- `FolderScanDepth`: 각 루트 아래로 몇 단계까지 내려갈지. `0`이면 루트만
- 숨김·시스템 폴더, `.`으로 시작하는 폴더, 심볼릭 링크·정션, `AppData`, `node_modules`, `bin`, `obj`는 건너뜁니다. 필요하면 `FolderRoots`에 직접 추가하세요
- 폴더 이름은 한글·영문 양쪽으로 검색됩니다. 예: "다운로드"/"Downloads", "내 드라이브"/"My Drive"/"구글 드라이브"

### 폴더가 안 보일 때

인덱싱이 끝날 때마다 `%APPDATA%\AppLauncherForWindows\index.log`가 다시 쓰입니다. 어떤 루트가 사용됐는지, 각 소스가 몇 개를 읽었는지, 실패했다면 어떤 오류였는지 적혀 있습니다. 찾는 폴더의 상위가 루트 목록에 없으면 `FolderRoots`에 추가하고, 너무 깊이 있으면 `FolderScanDepth`를 올리세요. 소스가 실패하면 런처 하단에 "일부 읽기 실패"가 표시됩니다.

## 로드맵

1. ~~솔루션 스캐폴딩, 빈 창, 전역 단축키 토글~~
2. ~~시작 메뉴 스캐너, 아이콘 추출, 퍼지 검색, 결과 목록 표시와 실행~~
   ~~폴더 인덱싱과 Explorer로 열기~~
3. ~~사용 빈도 랭킹, 실행 기록~~, 한글 초성 검색
4. 자동 시작, 설정 화면
5. 스토어 앱(UWP) 스캐너, 즐겨찾기, 라이트/다크 테마
6. ~~GitHub Actions 빌드와 릴리스~~
