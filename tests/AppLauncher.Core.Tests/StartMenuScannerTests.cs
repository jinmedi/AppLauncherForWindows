using AppLauncher.Core.Indexing;
using AppLauncher.Core.Models;

namespace AppLauncher.Core.Tests;

public sealed class StartMenuScannerTests : IDisposable
{
    private readonly string _userRoot;
    private readonly string _commonRoot;
    private readonly FakeResolver _resolver = new();

    public StartMenuScannerTests()
    {
        var baseDir = Path.Combine(Path.GetTempPath(), "AppLauncherTests", Guid.NewGuid().ToString("N"));
        _userRoot = Path.Combine(baseDir, "User");
        _commonRoot = Path.Combine(baseDir, "Common");
        Directory.CreateDirectory(_userRoot);
        Directory.CreateDirectory(_commonRoot);
    }

    [Fact]
    public void Scan_FindsAppAndSkipsItsUninstaller()
    {
        var folder = Path.Combine(_commonRoot, "카카오톡");
        AddShortcut(folder, "카카오톡", @"C:\Program Files (x86)\Kakao\KakaoTalk\KakaoTalk.exe");
        AddShortcut(folder, "카카오톡 제거", @"C:\Program Files (x86)\Kakao\KakaoTalk\uninstall.exe");

        var entries = Scan();

        var entry = Assert.Single(entries);
        Assert.Equal("카카오톡", entry.Name);
        Assert.Equal(AppSource.StartMenu, entry.Source);
        Assert.EndsWith("KakaoTalk.exe", entry.TargetPath);
        Assert.EndsWith("카카오톡.lnk", entry.LaunchPath);
        Assert.Contains("KakaoTalk", entry.Keywords);
    }

    [Fact]
    public void Scan_SkipsUninstallerByTargetName_EvenWithInnocentShortcutName()
    {
        AddShortcut(_commonRoot, "Setup Tool", @"C:\Apps\Tool\unins000.exe");

        Assert.Empty(Scan());
    }

    [Fact]
    public void Scan_SkipsNonExecutableTargets()
    {
        AddShortcut(_commonRoot, "Manual", @"C:\Apps\Tool\manual.pdf");
        AddShortcut(_commonRoot, "Docs Folder", @"C:\Apps\Tool\docs");

        Assert.Empty(Scan());
    }

    [Fact]
    public void Scan_SkipsShortcutsTheResolverCannotRead()
    {
        File.WriteAllText(Path.Combine(_commonRoot, "Broken.lnk"), string.Empty);

        Assert.Empty(Scan());
    }

    [Fact]
    public void Scan_DeduplicatesSameTarget_PreferringUserRoot()
    {
        AddShortcut(_userRoot, "My Editor", @"C:\Apps\Editor\editor.exe");
        AddShortcut(_commonRoot, "Editor", @"C:\Apps\Editor\editor.exe");

        var entries = Scan();

        var entry = Assert.Single(entries);
        Assert.Equal("My Editor", entry.Name);
    }

    [Fact]
    public void Scan_KeepsSameExeWithDifferentArgumentsAsSeparateEntries()
    {
        AddShortcut(_commonRoot, "Game", @"C:\Apps\Game\game.exe");
        AddShortcut(_commonRoot, "Game (Safe Mode)", @"C:\Apps\Game\game.exe", arguments: "--safe");

        Assert.Equal(2, Scan().Count);
    }

    [Fact]
    public void Scan_AddsFolderNameAsKeyword_WhenItDiffersFromShortcutName()
    {
        AddShortcut(Path.Combine(_commonRoot, "JetBrains"), "Rider 2025.2", @"C:\Apps\Rider\rider64.exe");

        var entry = Assert.Single(Scan());

        Assert.Contains("JetBrains", entry.Keywords);
        Assert.Contains("rider64", entry.Keywords);
    }

    [Fact]
    public void Scan_ToleratesMissingRoot()
    {
        var scanner = new StartMenuScanner(_resolver, [Path.Combine(_userRoot, "does-not-exist")]);

        Assert.Empty(scanner.Scan());
    }

    private IReadOnlyList<AppEntry> Scan() =>
        new StartMenuScanner(_resolver, [_userRoot, _commonRoot]).Scan();

    private void AddShortcut(string folder, string name, string target, string? arguments = null)
    {
        Directory.CreateDirectory(folder);
        var path = Path.Combine(folder, name + ".lnk");
        File.WriteAllText(path, "fake");
        _resolver.Targets[path] = new ShellLinkTarget(target, arguments, null, null, null);
    }

    public void Dispose()
    {
        var baseDir = Path.GetDirectoryName(_userRoot)!;
        if (Directory.Exists(baseDir))
        {
            Directory.Delete(baseDir, recursive: true);
        }
    }

    private sealed class FakeResolver : IShellLinkResolver
    {
        public Dictionary<string, ShellLinkTarget> Targets { get; } = new(StringComparer.OrdinalIgnoreCase);

        public ShellLinkTarget? Resolve(string shortcutPath) =>
            Targets.TryGetValue(shortcutPath, out var target) ? target : null;
    }
}
