using AppLauncher.Core.Models;

namespace AppLauncher.Core.Indexing;

/// <summary>
/// Indexes a set of root folders and their subfolders down to a fixed depth so they can be
/// opened in Explorer from the launcher. Hidden, system and dot-folders are skipped.
/// </summary>
public sealed class FolderScanner : IAppSource
{
    public const int DefaultMaxDepth = 2;
    public const int DefaultMaxEntries = 10_000;

    /// <summary>Korean display names Explorer uses for the well-known profile folders, added as search keywords.</summary>
    private static readonly Dictionary<string, string> LocalizedRootNames = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Desktop"] = "바탕 화면",
        ["Documents"] = "문서",
        ["Downloads"] = "다운로드",
        ["Pictures"] = "사진",
        ["Videos"] = "동영상",
        ["Music"] = "음악",
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
        AttributesToSkip = FileAttributes.Hidden | FileAttributes.System | FileAttributes.ReparsePoint,
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

    /// <summary>Desktop, Documents, Downloads, Pictures, Videos, Music and the profile folder itself.</summary>
    public static IEnumerable<string> DefaultRoots()
    {
        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

        yield return Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
        yield return Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        yield return Path.Combine(profile, "Downloads");
        yield return Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
        yield return Environment.GetFolderPath(Environment.SpecialFolder.MyVideos);
        yield return Environment.GetFolderPath(Environment.SpecialFolder.MyMusic);
        yield return profile;
    }

    public Task<IReadOnlyList<AppEntry>> ScanAsync(CancellationToken cancellationToken = default) =>
        Task.Run(() => Scan(cancellationToken), cancellationToken);

    public IReadOnlyList<AppEntry> Scan(CancellationToken cancellationToken = default)
    {
        var entries = new List<AppEntry>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

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

            if (!Directory.Exists(root))
            {
                continue;
            }

            var rootName = Path.GetFileName(root);
            if (rootName.Length == 0)
            {
                rootName = root; // a drive root such as "C:\"
            }

            var rootKeywords = LocalizedRootNames.TryGetValue(rootName, out var localized) ? [localized] : Array.Empty<string>();
            Add(entries, seen, root, rootName, rootKeywords);

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

    private void Walk(List<AppEntry> entries, HashSet<string> seen, string directory, int depth, CancellationToken cancellationToken)
    {
        var parentName = Path.GetFileName(directory);

        IEnumerable<string> children;
        try
        {
            children = Directory.EnumerateDirectories(directory, "*", ChildOptions);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return;
        }

        foreach (var child in children)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (entries.Count >= _maxEntries)
            {
                return;
            }

            var name = Path.GetFileName(child);
            if (name.Length == 0 || name[0] == '.' || SkippedFolderNames.Contains(name))
            {
                continue;
            }

            Add(entries, seen, child, name, [parentName]);

            if (depth < _maxDepth)
            {
                Walk(entries, seen, child, depth + 1, cancellationToken);
            }
        }
    }

    private static void Add(List<AppEntry> entries, HashSet<string> seen, string path, string name, IReadOnlyList<string> keywords)
    {
        if (!seen.Add(path))
        {
            return;
        }

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
