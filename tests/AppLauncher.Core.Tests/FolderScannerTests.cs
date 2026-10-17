using AppLauncher.Core.Indexing;
using AppLauncher.Core.Models;

namespace AppLauncher.Core.Tests;

public sealed class FolderScannerTests : IDisposable
{
    private readonly string _baseDir = Path.Combine(Path.GetTempPath(), "AppLauncherTests", Guid.NewGuid().ToString("N"));

    [Fact]
    public void Scan_IncludesRootAndSubfoldersDownToMaxDepth()
    {
        var root = MakeDir("Projects");
        MakeDir("Projects", "Alpha");
        MakeDir("Projects", "Alpha", "src");
        MakeDir("Projects", "Alpha", "src", "deep");   // depth 3: beyond the limit

        var names = new FolderScanner([root], maxDepth: 2).Scan().Select(e => e.Name).ToList();

        Assert.Equal(["Projects", "Alpha", "src"], names);
    }

    [Fact]
    public void Scan_DepthZero_IndexesOnlyRoots()
    {
        var root = MakeDir("Only");
        MakeDir("Only", "Child");

        var entries = new FolderScanner([root], maxDepth: 0).Scan();

        var entry = Assert.Single(entries);
        Assert.Equal("Only", entry.Name);
    }

    [Fact]
    public void Scan_SkipsHiddenDotAndNoiseFolders()
    {
        var root = MakeDir("Repo");
        MakeDir("Repo", "src");
        MakeDir("Repo", ".git");
        MakeDir("Repo", "node_modules");
        MakeDir("Repo", "obj");
        MakeDir("Repo", "AppData");
        var hidden = MakeDir("Repo", "Secret");
        File.SetAttributes(hidden, File.GetAttributes(hidden) | FileAttributes.Hidden);

        var names = new FolderScanner([root]).Scan().Select(e => e.Name).ToList();

        Assert.Equal(["Repo", "src"], names);
    }

    [Fact]
    public void Scan_ProducesFolderEntriesThatOpenThePathItself()
    {
        var root = MakeDir("Docs");

        var entry = Assert.Single(new FolderScanner([root], maxDepth: 0).Scan());

        Assert.Equal(AppSource.Folder, entry.Source);
        Assert.Equal(root, entry.LaunchPath, ignoreCase: true);
        Assert.Equal(root, entry.WorkingDirectory, ignoreCase: true);
        Assert.Null(entry.TargetPath);
        Assert.StartsWith("folder:", entry.Id);
    }

    [Fact]
    public void Scan_AddsKoreanKeywordForWellKnownRootNames()
    {
        var root = MakeDir("Downloads");

        var entry = Assert.Single(new FolderScanner([root], maxDepth: 0).Scan());

        Assert.Contains("다운로드", entry.Keywords);
    }

    [Fact]
    public void Scan_AddsParentNameAsKeywordForSubfolders()
    {
        var root = MakeDir("Work");
        MakeDir("Work", "Invoices");

        var child = new FolderScanner([root]).Scan().Single(e => e.Name == "Invoices");

        Assert.Contains("Work", child.Keywords);
    }

    [Fact]
    public void Scan_IgnoresMissingAndBlankRoots()
    {
        var root = MakeDir("Real");

        var entries = new FolderScanner([Path.Combine(_baseDir, "missing"), "", "   ", root], maxDepth: 0).Scan();

        Assert.Single(entries);
    }

    [Fact]
    public void Scan_DeduplicatesOverlappingRoots()
    {
        var root = MakeDir("Home");
        var child = MakeDir("Home", "Docs");

        var entries = new FolderScanner([root, child]).Scan();

        Assert.Equal(2, entries.Count);
    }

    [Fact]
    public void Scan_StopsAtMaxEntries()
    {
        var root = MakeDir("Many");
        for (var i = 0; i < 10; i++)
        {
            MakeDir("Many", $"f{i}");
        }

        var entries = new FolderScanner([root], maxDepth: 1, maxEntries: 4).Scan();

        Assert.Equal(4, entries.Count);
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
            foreach (var dir in Directory.EnumerateDirectories(_baseDir, "*", SearchOption.AllDirectories))
            {
                File.SetAttributes(dir, FileAttributes.Directory);
            }

            Directory.Delete(_baseDir, recursive: true);
        }
    }
}
