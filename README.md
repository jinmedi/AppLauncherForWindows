# AppLauncherForWindows

Windows용 경량 앱 런처입니다. 전역 단축키(기본 `Alt+Space`)로 검색창을 띄우고, 설치된 앱을 빠르게 찾아 실행하는 것을 목표로 합니다.

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
    Search/AppSearcher.cs          이름 + 키워드 랭킹, 다중 단어 질의
    Services/AppIndex.cs           소스 병합, 백그라운드 갱신
    Services/IAppLauncher.cs       ShellExecute로 .lnk 실행
    Services/SettingsStore.cs      %APPDATA%\AppLauncherForWindows\settings.json
tests/
  AppLauncher.Core.Tests/          xUnit
```

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
- `Esc` 또는 포커스 이탈: 창 숨김
- 트레이 아이콘 왼쪽 클릭: 창 열기/닫기, 오른쪽 클릭: 메뉴(열기, 종료)

## 설정

첫 실행 때 `%APPDATA%\AppLauncherForWindows\settings.json`이 기본값으로 만들어집니다. 수정 후 런처를 다시 시작하면 적용됩니다.

```json
{
  "Hotkey": "Alt+Space",
  "StartWithWindows": false,
  "FolderRoots": [
    "C:\\Users\\<이름>\\Desktop",
    "C:\\Users\\<이름>\\Documents",
    "C:\\Users\\<이름>\\Downloads",
    "C:\\Users\\<이름>"
  ],
  "FolderScanDepth": 2
}
```

- `Hotkey`: 예 `"Ctrl+Shift+Space"`, `"Win+K"`
- `FolderRoots`: 인덱싱할 폴더. `%USERPROFILE%` 같은 환경 변수를 쓸 수 있고, 빈 배열이면 폴더 검색을 끕니다
- `FolderScanDepth`: 각 루트 아래로 몇 단계까지 내려갈지. `0`이면 루트만
- 숨김·시스템 폴더, `.`으로 시작하는 폴더, `AppData`, `node_modules`, `bin`, `obj`는 건너뜁니다. 필요하면 루트에 직접 추가하세요

## 로드맵

1. ~~솔루션 스캐폴딩, 빈 창, 전역 단축키 토글~~
2. ~~시작 메뉴 스캐너, 아이콘 추출, 퍼지 검색, 결과 목록 표시와 실행~~
   ~~폴더 인덱싱과 Explorer로 열기~~
3. 사용 빈도 랭킹, 실행 기록, 한글 초성 검색
4. 자동 시작, 설정 화면
5. 스토어 앱(UWP) 스캐너, 즐겨찾기, 라이트/다크 테마
6. GitHub Actions 빌드와 릴리스
