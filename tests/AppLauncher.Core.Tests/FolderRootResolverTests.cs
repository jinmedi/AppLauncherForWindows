using AppLauncher.Core.Indexing;
using AppLauncher.Core.Models;

namespace AppLauncher.Core.Tests;

public sealed class FolderRootResolverTests : IDisposable
{
    private readonly string _baseDir = Path.Combine(Path.GetTempPath(), "AppLauncherTests", Guid.NewGuid().ToString("N"));

    [Fact]
    public void Resolve_CombinesKnownCloudAndUserRoots_InThatOrder()
    {
        var settings = new LauncherSettings { FolderRoots = [@"D:\Work"] };

        var roots = FolderRootResolver.Resolve(settings, [@"C:\Users\me\Desktop"], [@"G:\내 드라이브"]);

        Assert.Equal([@"C:\Users\me\Desktop", @"G:\내 드라이브", @"D:\Work"], roots);
    }

    [Fact]
    public void Resolve_HonoursIncludeFlags()
    {
        var settings = new LauncherSettings { IncludeKnownFolders = false, IncludeCloudDrives = false, FolderRoots = [@"D:\Work"] };

        var roots = FolderRootResolver.Resolve(settings, [@"C:\Users\me\Desktop"], [@"G:\내 드라이브"]);

        Assert.Equal([@"D:\Work"], roots);
    }

    [Fact]
    public void Resolve_DeduplicatesCaseInsensitivelyAndIgnoresTrailingSeparators()
    {
        // Old settings files carry the known folders in FolderRoots; they must not be indexed twice.
        var settings = new LauncherSettings { FolderRoots = [@"c:\users\ME\desktop\", "", "  "] };

        var roots = FolderRootResolver.Resolve(settings, [@"C:\Users\me\Desktop"], []);

        Assert.Single(roots);
    }

    [Fact]
    public void Resolve_ExpandsEnvironmentVariables()
    {
        Environment.SetEnvironmentVariable("APPLAUNCHER_TEST_ROOT", @"D:\FromEnv");
        try
        {
            var roots = FolderRootResolver.Resolve(new LauncherSettings { FolderRoots = [@"%APPLAUNCHER_TEST_ROOT%\Sub"] }, [], []);

            Assert.Equal([@"D:\FromEnv\Sub"], roots);
        }
        finally
        {
            Environment.SetEnvironmentVariable("APPLAUNCHER_TEST_ROOT", null);
        }
    }

    [Fact]
    public void CloudRoots_FindsGoogleDriveStreamingTopLevelFolders_SkippingHiddenAndDotFolders()
    {
        var drive = MakeDir("G");
        MakeDir("G", "내 드라이브");
        MakeDir("G", "다른 컴퓨터");
        MakeDir("G", ".shortcut-targets-by-id");
        MakeDir("G", "$RECYCLE.BIN");
        var profile = MakeDir("profile");

        var roots = FolderRootResolver.CloudRoots([(drive, "Google Drive"), (@"C:\", "")], profile, _ => null, null);

        Assert.Equal(
            [Path.Combine(drive, "내 드라이브"), Path.Combine(drive, "다른 컴퓨터")],
            roots.OrderBy(r => r, StringComparer.Ordinal));
    }

    [Fact]
    public void CloudRoots_UsesOneDriveEnvironmentVariables_WhenTheFolderExists()
    {
        var profile = MakeDir("profile");
        var personal = MakeDir("profile", "OneDrive");
        var work = MakeDir("profile", "OneDrive - Company");
        var env = new Dictionary<string, string?>
        {
            ["OneDrive"] = work,
            ["OneDriveConsumer"] = personal,
            ["OneDriveCommercial"] = Path.Combine(profile, "missing"),
        };

        var roots = FolderRootResolver.CloudRoots([], profile, name => env.GetValueOrDefault(name), null);

        Assert.Equal([work, personal], roots.Take(2));
        Assert.DoesNotContain(roots, r => r.EndsWith("missing", StringComparison.Ordinal));
    }

    [Fact]
    public void CloudRoots_FindsMirrorModeAndProfileCloudFolders()
    {
        var profile = MakeDir("profile");
        var googleMirror = MakeDir("profile", "Google Drive");
        var icloud = MakeDir("profile", "iCloudDrive");

        var roots = FolderRootResolver.CloudRoots([], profile, _ => null, null);

        Assert.Contains(googleMirror, roots);
        Assert.Contains(icloud, roots);
    }

    [Fact]
    public void CloudRoots_ReadsDropboxInfoJson()
    {
        var personal = MakeDir("Dropbox");
        var business = MakeDir("Dropbox (Work)");
        var info = Path.Combine(_baseDir, "info.json");
        File.WriteAllText(info, $$"""
            { "personal": { "path": {{System.Text.Json.JsonSerializer.Serialize(personal)}}, "host": 1 },
              "business": { "path": {{System.Text.Json.JsonSerializer.Serialize(business)}} },
              "broken": { "path": "Z:\\does\\not\\exist" } }
            """);

        var roots = FolderRootResolver.CloudRoots([], MakeDir("profile"), _ => null, info);

        Assert.Equal([personal, business], roots);
    }

    [Fact]
    public void CloudRoots_ToleratesCorruptDropboxInfo()
    {
        var info = Path.Combine(_baseDir, "info.json");
        Directory.CreateDirectory(_baseDir);
        File.WriteAllText(info, "{ not json");

        var roots = FolderRootResolver.CloudRoots([], MakeDir("profile"), _ => null, info);

        Assert.Empty(roots);
    }

    [Fact]
    public void KnownFolders_ContainsSevenExistingOrPlausiblePaths()
    {
        var known = FolderRootResolver.KnownFolders();

        Assert.Equal(7, known.Count);
        Assert.All(known, path => Assert.True(Path.IsPathRooted(path), path));
        Assert.Contains(known, p => p.EndsWith("Downloads", StringComparison.OrdinalIgnoreCase));
    }

    private string MakeDir(params string[] parts)
    {
        var path = Path.Combine([_baseDir, .. parts]);
        Directory.CreateDirectory(path);
        return path;
    }

    public void Dispose()
    {
        if (Directory.Exists(_baseDir))
        {
            Directory.Delete(_baseDir, recursive: true);
        }
    }
}
