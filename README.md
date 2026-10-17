# AppLauncherForWindows

Windows용 경량 앱 런처입니다. 전역 단축키(기본 `Alt+Space`)로 검색창을 띄우고, 설치된 앱을 빠르게 찾아 실행하는 것을 목표로 합니다.

## 현재 상태

1단계 스캐폴딩. 솔루션 구조, 빈 런처 창, 전역 단축키 토글, 트레이 아이콘까지 동작합니다.
앱 인덱싱과 검색은 다음 단계에서 추가됩니다.

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
    Views/MainWindow.xaml(.cs)     런처 창 (표시/숨김/토글)
    ViewModels/MainViewModel.cs
    Interop/GlobalHotkey.cs        RegisterHotKey 래퍼
    Interop/NativeMethods.cs       Win32 P/Invoke
    app.manifest                   PerMonitorV2 DPI, asInvoker
  AppLauncher.Core/                UI 의존 없는 클래스 라이브러리
    Models/HotkeySpec.cs           "Ctrl+Alt+K" 형식 파싱/직렬화
    Models/LauncherSettings.cs
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

실행하면 런처 창이 한 번 표시되고 트레이에 상주합니다.

- `Alt+Space`: 창 열기/닫기
- `Esc` 또는 포커스 이탈: 창 숨김
- 트레이 아이콘 왼쪽 클릭: 창 열기/닫기, 오른쪽 클릭: 메뉴(열기, 종료)

단축키는 `%APPDATA%\AppLauncherForWindows\settings.json`의 `Hotkey` 값으로 바꿀 수 있습니다. 예: `"Ctrl+Shift+Space"`

## 로드맵

1. ~~솔루션 스캐폴딩, 빈 창, 전역 단축키 토글~~
2. 시작 메뉴 스캐너, 아이콘 추출, 결과 목록 표시
3. 퍼지 검색, 사용 빈도 랭킹, 실행 기록
4. 자동 시작, 설정 화면
5. 스토어 앱(UWP) 스캐너, 즐겨찾기, 라이트/다크 테마
6. GitHub Actions 빌드와 릴리스
