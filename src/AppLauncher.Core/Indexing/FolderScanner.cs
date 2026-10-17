using AppLauncher.Core.Models;

namespace AppLauncher.Core.Indexing;

/// <summary>
/// Indexes a set of root folders and their subfolders down to a fixed depth so they can be
/// opened in Explorer from the launcher. Hidden, system and dot-folders are skipped, as are
/// symbolic links and junctions. Cloud placeholders (OneDrive Files On-Demand, Google Drive
/// streaming) are reparse points too but not links, so they are kept.
/// </summary>
public sealed class FolderScanner : IAppSource
{
    public const int DefaultMaxDepth = 2;
    public const int DefaultMaxEntries = 10_000;

    /// <summary>Alternative names people type for well-known roots, added as search keywords.</summary>
    private static readonly Dictionary<string, string[]> RootKeywordsByName = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Desktop"] = ["바탕 화면"],
        ["바탕 화면"] = ["Desktop"],
        ["Documents"] = ["문서"],
        ["문서"] = ["Documents"],
        ["Downloads"] = ["다운로드"],
        ["다운로드"] = ["Downloads"],
        ["Pictures"] = ["사진"],
        ["사진"] = ["Pictures"],
        ["Videos"] = ["동영상"],
        ["동영상"] = ["Videos"],
        ["Music"] = ["음악"],
        ["음악"] = ["Music"],
        ["내 드라이브"] = ["My Drive", "Google Drive", "구글 드라이브"],
        ["My Drive"] = ["내 드라이브", "Google Drive", "구글 드라이브"],
        ["공유 드라이브"] = ["Shared drives", "Google Drive", "구글 드라이브"],
        ["Shared drives"] = ["공유 드라이브", "Google Drive", "구글 드라이브"],
        ["다른 컴퓨터"] = ["Computers", "Google Drive", "구글 드라이브"],
        ["Google Drive"] = ["구글 드라이브"],
        ["Dropbox"] = ["드롭박스"],
        ["iCloudDrive"] = ["iCloud", "아이클라우드"],
        ["iCloud Drive"] = ["iCloud", "아이클라우드"],
    };

    /// <summary>
    /// Never descended into. AppData is listed explicitly because it is not always marked hidden;
    /// add it as a root in settings if you want it indexed.
    /// </summary>
    private static readonly HashSet<string> SkippedFolderNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "AppData", "node_modules", "bin", "obj", "__pycache__", "$RECYCLE.BIN", "System Volume Information",
    };

    private static readonly EnumerationOptions ChildOptions = new()
    {
        RecurseSubdirectories = false,
        IgnoreInaccessible = true,
        AttributesToSkip = FileAttributes.Hidden | FileAttributes.System,
    };

    private readonly IReadOnlyList<string> _roots;
    private readonly int _maxDepth;
    private readonly int _maxEntries;

    public FolderScanner(IEnumerable<string> roots, int maxDepth = DefaultMaxDepth, int maxEntries = DefaultMaxEntries)
    {
        ArgumentNullException.ThrowIfNull(roots);
        ArgumentOutOfRangeException.ThrowIfNegative(maxDepth);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maxEntries);

        _roots = roots.Where(r => !string.IsNullOrWhiteSpace(r)).ToArray();
        _maxDepth = maxDepth;
        _maxEntries = maxEntries;
    }

    public string Name => "Folders";

    public IReadOnlyList<string> Roots => _roots;

    public Task<IReadOnlyList<AppEntry>> ScanAsync(CancellationToken cancellationToken = default) =>
        Task.Run(() => Scan(cancellationToken), cancellationToken);

    public IReadOnlyList<AppEntry> Scan(CancellationToken cancellationToken = default)
    {
        var entries = new List<AppEntry>();
        var seen = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

        foreach (var configuredRoot in _roots)
        {
            cancellationToken.ThrowIfCancellationRequested();

            string root;
            try
            {
                root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Environment.ExpandEnvironmentVariables(configuredRoot)));
            }
            catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
            {
                continue;
            }

            if (!SafeDirectoryExists(root))
            {
                continue;
            }

            var rootName = Path.GetFileName(root);
            if (rootName.Length == 0)
            {
                rootName = root; // a drive root such as "G:\"
            }

            var keywords = RootKeywordsByName.TryGetValue(rootName, out var known) ? known
                : rootName.StartsWith("OneDrive", StringComparison.OrdinalIgnoreCase) ? ["원드라이브"]
                : [];
            Add(entries, seen, root, rootName, keywords);

            if (_maxDepth > 0)
            {
                Walk(entries, seen, root, depth: 1, cancellationToken);
            }

            if (entries.Count >= _maxEntries)
            {
                break;
            }
        }

        return entries;
    }

    private void Walk(List<AppEntry> entries, Dictionary<string, int> seen, string directory, int depth, CancellationToken cancellationToken)
    {
        var parentName = Path.GetFileName(directory);
        if (parentName.Length == 0)
        {
            parentName = directory;
        }

        IEnumerator<DirectoryInfo> children;
        try
        {
            children = new DirectoryInfo(directory).EnumerateDirectories("*", ChildOptions).GetEnumerator();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            return;
        }

        using (children)
        {
            while (true)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (entries.Count >= _maxEntries)
                {
                    return;
                }

                // MoveNext can throw mid-way (cloud provider offline, path too long, device removed);
                // one bad entry must not abort the whole source.
                DirectoryInfo child;
                try
                {
                    if (!children.MoveNext())
                    {
                        return;
                    }

                    child = children.Current;
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Security.SecurityException)
                {
                    return;
                }

                var name = child.Name;
                if (name.Length == 0 || name[0] == '.' || SkippedFolderNames.Contains(name) || IsLink(child))
                {
                    continue;
                }

                Add(entries, seen, child.FullName, name, [parentName]);

                if (depth < _maxDepth)
                {
                    Walk(entries, seen, child.FullName, depth + 1, cancellationToken);
                }
            }
        }
    }

    /// <summary>True for symbolic links and junctions; false for cloud placeholders and ordinary folders.</summary>
    private static bool IsLink(DirectoryInfo info)
    {
        if ((info.Attributes & FileAttributes.ReparsePoint) == 0)
        {
            return false;
        }

        try
        {
            return info.LinkTarget is not null;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return true;
        }
    }

    private static bool SafeDirectoryExists(string path)
    {
        try
        {
            return Directory.Exists(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    /// <summary>
    /// Adds a folder once. When a root was already picked up as a child of an earlier root (the profile
    /// folder contains "OneDrive - Work", for example) the root's keywords are merged into the existing
    /// entry so "원드라이브" still finds it.
    /// </summary>
    private static void Add(List<AppEntry> entries, Dictionary<string, int> seen, string path, string name, IReadOnlyList<string> keywords)
    {
        if (seen.TryGetValue(path, out var existingIndex))
        {
            var existing = entries[existingIndex];
            var missing = keywords.Where(k => !existing.Keywords.Contains(k, StringComparer.OrdinalIgnoreCase)).ToList();
            if (missing.Count > 0)
            {
                entries[existingIndex] = existing with { Keywords = [.. existing.Keywords, .. missing] };
            }

            return;
        }

        seen[path] = entries.Count;
        entries.Add(new AppEntry
        {
            Id = "folder:" + path.ToLowerInvariant(),
            Name = name,
            LaunchPath = path,
            WorkingDirectory = path,
            Source = AppSource.Folder,
            Keywords = keywords,
        });
    }
}
