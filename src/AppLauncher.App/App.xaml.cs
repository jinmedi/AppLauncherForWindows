using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using AppLauncher.App.Interop;
using AppLauncher.App.ViewModels;
using AppLauncher.Core.Indexing;
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
        WriteDefaultSettingsIfMissing(_services.GetRequiredService<SettingsStore>(), settings);

        _window = _services.GetRequiredService<Views.MainWindow>();
        MainWindow = _window;

        RegisterHotkey(settings.GetHotkeyOrDefault());
        CreateTrayIcon();

        // Index in the background; the window shows "reading apps..." until it finishes.
        _ = RefreshIndexAsync(_services.GetRequiredService<AppIndex>(), _services.GetServices<IAppSource>());

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

        services.AddSingleton<IShellLinkResolver, ShellLinkResolver>();
        // Factories so DI does not try to satisfy the scanners' IEnumerable<string> roots parameters itself.
        services.AddSingleton<IAppSource>(sp => new StartMenuScanner(sp.GetRequiredService<IShellLinkResolver>()));
        services.AddSingleton<IAppSource>(sp =>
        {
            var settings = sp.GetRequiredService<LauncherSettings>();
            return new FolderScanner(FolderRootResolver.Resolve(settings), settings.FolderScanDepth);
        });
        services.AddSingleton(_ =>
        {
            var history = new UsageHistory(UsageHistory.DefaultPath);
            history.Load();
            return history;
        });
        services.AddSingleton<AppIndex>();
        services.AddSingleton<IAppLauncher, ShellAppLauncher>();
        services.AddSingleton<IconExtractor>();

        services.AddSingleton<MainViewModel>();
        services.AddSingleton<Views.MainWindow>();

        return services.BuildServiceProvider();
    }

    /// <summary>Writes the defaults on first run so the user has a file to edit (hotkey, folder roots).</summary>
    private static void WriteDefaultSettingsIfMissing(SettingsStore store, LauncherSettings settings)
    {
        if (File.Exists(store.FilePath))
        {
            return;
        }

        try
        {
            store.Save(settings);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Trace.WriteLine($"[AppLauncher] could not write default settings: {ex.Message}");
        }
    }

    private static async Task RefreshIndexAsync(AppIndex index, IEnumerable<IAppSource> sources)
    {
        try
        {
            var stopwatch = Stopwatch.StartNew();
            await index.RefreshAsync();
            Trace.WriteLine($"[AppLauncher] indexed {index.Count} entries in {stopwatch.ElapsedMilliseconds} ms");
            WriteIndexLog(index, sources);
        }
        catch (Exception ex)
        {
            Trace.WriteLine($"[AppLauncher] index refresh failed: {ex}");
        }
    }

    /// <summary>
    /// %APPDATA%\AppLauncherForWindows\index.log, rewritten after every refresh: which folder roots were
    /// used and what each source contributed. This is what to look at when "my folder is not found".
    /// </summary>
    private static void WriteIndexLog(AppIndex index, IEnumerable<IAppSource> sources)
    {
        try
        {
            var lines = new List<string>
            {
                $"{DateTime.Now:yyyy-MM-dd HH:mm:ss}  {index.Count} entries",
                string.Empty,
                "[sources]",
            };

            foreach (var report in index.LastReport)
            {
                var status = report.Error is null ? $"{report.Count} entries" : $"FAILED: {report.Error}";
                lines.Add($"  {report.Source}: {status} ({report.Elapsed.TotalMilliseconds:F0} ms)");
            }

            foreach (var scanner in sources.OfType<FolderScanner>())
            {
                lines.Add(string.Empty);
                lines.Add("[folder roots]");
                foreach (var root in scanner.Roots)
                {
                    lines.Add($"  {root}  {(Directory.Exists(root) ? string.Empty : "(missing)")}".TrimEnd());
                }
            }

            var path = Path.Combine(Path.GetDirectoryName(SettingsStore.DefaultPath)!, "index.log");
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllLines(path, lines);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Trace.WriteLine($"[AppLauncher] could not write index.log: {ex.Message}");
        }
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
