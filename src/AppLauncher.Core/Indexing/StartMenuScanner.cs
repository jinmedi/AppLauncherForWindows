using AppLauncher.Core.Models;

namespace AppLauncher.Core.Indexing;

/// <summary>
/// Enumerates .lnk shortcuts under the per-user and all-users Start Menu "Programs" folders,
/// resolves their targets and filters out uninstallers, documentation links and duplicates.
/// </summary>
public sealed class StartMenuScanner : IAppSource
{
    private static readonly string[] ExcludedNameFragments =
    [
        "uninstall", "제거", "삭제", "readme", "release notes", "license", "라이선스", "website", "웹사이트", "홈페이지",
    ];

    private static readonly HashSet<string> LaunchableExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".exe", ".com", ".bat", ".cmd", ".msc",
    };

    private readonly IShellLinkResolver _resolver;
    private readonly IReadOnlyList<string> _roots;

    public StartMenuScanner(IShellLinkResolver resolver, IEnumerable<string>? roots = null)
    {
        ArgumentNullException.ThrowIfNull(resolver);
        _resolver = resolver;
        _roots = (roots ?? DefaultRoots()).ToArray();
    }

    public string Name => "Start Menu";

    /// <summary>Per-user folder first so a user-level shortcut wins over the all-users one.</summary>
    public static IEnumerable<string> DefaultRoots()
    {
        yield return Environment.GetFolderPath(Environment.SpecialFolder.Programs);
        yield return Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms);
    }

    public Task<IReadOnlyList<AppEntry>> ScanAsync(CancellationToken cancellationToken = default) =>
        Task.Run(() => Scan(cancellationToken), cancellationToken);

    public IReadOnlyList<AppEntry> Scan(CancellationToken cancellationToken = default)
    {
        var entries = new List<AppEntry>();
        var seenTargets = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.System | FileAttributes.ReparsePoint,
        };

        foreach (var root in _roots)
        {
            if (string.IsNullOrEmpty(root) || !Directory.Exists(root))
            {
                continue;
            }

            foreach (var shortcutPath in Directory.EnumerateFiles(root, "*.lnk", options))
            {
                cancellationToken.ThrowIfCancellationRequested();

                var entry = TryCreateEntry(root, shortcutPath);
                if (entry is null)
                {
                    continue;
                }

                var targetKey = (entry.TargetPath ?? entry.LaunchPath) + "|" + entry.Arguments;
                if (seenTargets.Add(targetKey))
                {
                    entries.Add(entry);
                }
            }
        }

        return entries;
    }

    private AppEntry? TryCreateEntry(string root, string shortcutPath)
    {
        var name = Path.GetFileNameWithoutExtension(shortcutPath);
        if (name.Length == 0 || IsExcludedName(name))
        {
            return null;
        }

        ShellLinkTarget? link;
        try
        {
            link = _resolver.Resolve(shortcutPath);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return null;
        }

        if (link is null || !IsLaunchableTarget(link.TargetPath))
        {
            return null;
        }

        var keywords = new List<string>(3);
        var targetName = Path.GetFileNameWithoutExtension(link.TargetPath);
        AddKeyword(keywords, name, targetName);

        var folderName = Path.GetFileName(Path.GetDirectoryName(shortcutPath) ?? string.Empty);
        if (!string.Equals(Path.GetDirectoryName(shortcutPath), root, StringComparison.OrdinalIgnoreCase))
        {
            AddKeyword(keywords, name, folderName);
        }

        AddKeyword(keywords, name, link.Description);

        return new AppEntry
        {
            Id = "startmenu:" + shortcutPath.ToLowerInvariant(),
            Name = name,
            LaunchPath = shortcutPath,
            TargetPath = link.TargetPath,
            Arguments = link.Arguments,
            WorkingDirectory = link.WorkingDirectory,
            Description = link.Description,
            Source = AppSource.StartMenu,
            Keywords = keywords,
        };
    }

    private static bool IsExcludedName(string name)
    {
        foreach (var fragment in ExcludedNameFragments)
        {
            if (name.Contains(fragment, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    private static bool IsLaunchableTarget(string targetPath)
    {
        if (string.IsNullOrWhiteSpace(targetPath))
        {
            return false;
        }

        var extension = Path.GetExtension(targetPath);
        if (!LaunchableExtensions.Contains(extension))
        {
            return false;
        }

        var fileName = Path.GetFileNameWithoutExtension(targetPath);
        return !fileName.Contains("unins", StringComparison.OrdinalIgnoreCase);
    }

    private static void AddKeyword(List<string> keywords, string name, string? candidate)
    {
        if (string.IsNullOrWhiteSpace(candidate))
        {
            return;
        }

        var trimmed = candidate.Trim();
        if (trimmed.Equals(name, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        foreach (var existing in keywords)
        {
            if (existing.Equals(trimmed, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }
        }

        keywords.Add(trimmed);
    }
}
