using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using AppLauncher.App.Interop;
using AppLauncher.App.ViewModels;
using AppLauncher.Core.Models;
using AppLauncher.Core.Services;
using H.NotifyIcon;
using Microsoft.Extensions.DependencyInjection;

namespace AppLauncher.App;

public partial class App : Application
{
    private const string SingleInstanceMutexName = @"Local\AppLauncherForWindows.SingleInstance";

    private Mutex? _singleInstanceMutex;
    private ServiceProvider? _services;
    private Views.MainWindow? _window;
    private GlobalHotkey? _hotkey;
    private TaskbarIcon? _trayIcon;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _singleInstanceMutex = new Mutex(initiallyOwned: true, SingleInstanceMutexName, out var isFirstInstance);
        if (!isFirstInstance)
        {
            // A later step will forward "show" to the running instance instead of exiting silently.
            _singleInstanceMutex.Dispose();
            _singleInstanceMutex = null;
            Shutdown();
            return;
        }

        _services = BuildServices();

        var settings = _services.GetRequiredService<LauncherSettings>();
        _window = _services.GetRequiredService<Views.MainWindow>();
        MainWindow = _window;

        RegisterHotkey(settings.GetHotkeyOrDefault());
        CreateTrayIcon();

        // Show once on first launch so the user sees something happened.
        _window.ShowLauncher();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _hotkey?.Dispose();
        _trayIcon?.Dispose();
        _services?.Dispose();

        if (_singleInstanceMutex is not null)
        {
            _singleInstanceMutex.ReleaseMutex();
            _singleInstanceMutex.Dispose();
        }

        base.OnExit(e);
    }

    private static ServiceProvider BuildServices()
    {
        var services = new ServiceCollection();

        services.AddSingleton(new SettingsStore(SettingsStore.DefaultPath));
        services.AddSingleton(sp => sp.GetRequiredService<SettingsStore>().Load());
        services.AddSingleton<MainViewModel>();
        services.AddSingleton<Views.MainWindow>();

        return services.BuildServiceProvider();
    }

    private void RegisterHotkey(HotkeySpec spec)
    {
        // Force the HWND to exist while the window is still hidden so the hotkey works before first show.
        var handle = new WindowInteropHelper(_window!).EnsureHandle();
        var source = HwndSource.FromHwnd(handle)
                     ?? throw new InvalidOperationException("Main window has no HwndSource.");

        try
        {
            _hotkey = new GlobalHotkey(source, spec);
            _hotkey.Pressed += (_, _) => _window!.ToggleLauncher();
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                $"전역 단축키 {spec}을(를) 등록하지 못했습니다. 다른 프로그램이 같은 단축키를 사용 중일 수 있습니다.\n\n{ex.Message}",
                "App Launcher",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
    }

    private void CreateTrayIcon()
    {
        var openItem = new MenuItem { Header = "열기" };
        openItem.Click += (_, _) => _window!.ShowLauncher();

        var exitItem = new MenuItem { Header = "종료" };
        exitItem.Click += (_, _) => Shutdown();

        var menu = new ContextMenu();
        menu.Items.Add(openItem);
        menu.Items.Add(new Separator());
        menu.Items.Add(exitItem);

        _trayIcon = new TaskbarIcon
        {
            ToolTipText = "App Launcher",
            Icon = System.Drawing.SystemIcons.Application,
            ContextMenu = menu,
        };
        _trayIcon.TrayLeftMouseUp += (_, _) => _window!.ToggleLauncher();
        _trayIcon.ForceCreate();
    }
}
