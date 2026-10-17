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
        Assert.NotEmpty(settings.FolderRoots);
        Assert.Equal(2, settings.FolderScanDepth);
    }

    [Fact]
    public void Save_ThenLoad_RoundTripsFolderSettings()
    {
        var store = new SettingsStore(SettingsPath);
        store.Save(new LauncherSettings { FolderRoots = [@"D:\Work", @"%USERPROFILE%\Desktop"], FolderScanDepth = 1 });

        var loaded = store.Load();

        Assert.Equal([@"D:\Work", @"%USERPROFILE%\Desktop"], loaded.FolderRoots);
        Assert.Equal(1, loaded.FolderScanDepth);
    }

    [Fact]
    public void Save_WritesKoreanAndPlusSignsUnescaped()
    {
        var store = new SettingsStore(SettingsPath);
        store.Save(new LauncherSettings { Hotkey = "Ctrl+Space", FolderRoots = [@"C:\Users\me\바탕 화면"] });

        var json = File.ReadAllText(SettingsPath);

        Assert.Contains("Ctrl+Space", json);
        Assert.Contains("바탕 화면", json);
        Assert.DoesNotContain("\\u", json);
    }

    [Fact]
    public void Load_UsesDefaultFolderSettings_WhenOlderFileOmitsThem()
    {
        Directory.CreateDirectory(_directory);
        File.WriteAllText(SettingsPath, """{ "Hotkey": "Alt+Space", "StartWithWindows": false }""");

        var settings = new SettingsStore(SettingsPath).Load();

        Assert.NotEmpty(settings.FolderRoots);
        Assert.Equal(2, settings.FolderScanDepth);
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
