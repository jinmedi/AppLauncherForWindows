using AppLauncher.Core.Models;
using AppLauncher.Core.Services;

namespace AppLauncher.Core.Tests;

public sealed class SettingsStoreTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), "AppLauncherTests", Guid.NewGuid().ToString("N"));

    private string SettingsPath => Path.Combine(_directory, "settings.json");

    [Fact]
    public void Load_ReturnsDefaults_WhenFileIsMissing()
    {
        var store = new SettingsStore(SettingsPath);

        var settings = store.Load();

        Assert.Equal("Alt+Space", settings.Hotkey);
        Assert.False(settings.StartWithWindows);
    }

    [Fact]
    public void Save_ThenLoad_RoundTrips()
    {
        var store = new SettingsStore(SettingsPath);
        store.Save(new LauncherSettings { Hotkey = "Ctrl+Shift+Space", StartWithWindows = true });

        var loaded = store.Load();

        Assert.Equal("Ctrl+Shift+Space", loaded.Hotkey);
        Assert.True(loaded.StartWithWindows);
        Assert.False(File.Exists(SettingsPath + ".tmp"));
    }

    [Fact]
    public void Load_ReturnsDefaults_WhenFileIsCorrupt()
    {
        Directory.CreateDirectory(_directory);
        File.WriteAllText(SettingsPath, "{ not json");
        var store = new SettingsStore(SettingsPath);

        var settings = store.Load();

        Assert.Equal("Alt+Space", settings.Hotkey);
    }

    public void Dispose()
    {
        if (Directory.Exists(_directory))
        {
            Directory.Delete(_directory, recursive: true);
        }
    }
}
