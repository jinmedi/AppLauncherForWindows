using System.Runtime.InteropServices;
using System.Text.Json;
using AppLauncher.Core.Models;

namespace AppLauncher.Core.Indexing;

/// <summary>
/// Builds the list of folders <see cref="FolderScanner"/> indexes: the well-known profile folders,
/// auto-detected cloud-sync roots (OneDrive, Google Drive, Dropbox, iCloud) and the user's own
/// <see cref="LauncherSettings.FolderRoots"/>. Detection runs at startup, so a laptop with a different
/// drive letter or account picks up its own folders without editing settings.
/// </summary>
public static class FolderRootResolver
{
    private static readonly Guid FolderIdDownloads = new("374DE290-123F-4565-9164-39C4925E467B");

    private static readonly string[] OneDriveEnvironmentVariables = ["OneDrive", "OneDriveConsumer", "OneDriveCommercial"];

    /// <summary>Folder names cloud clients create directly under the profile (mirror mode or legacy clients).</summary>
    private static readonly string[] CloudFolderNamesInProfile =
        ["Google Drive", "My Drive", "내 드라이브", "Dropbox", "iCloudDrive", "iCloud Drive"];

    private static readonly EnumerationOptions TopLevelOptions = new()
    {
        RecurseSubdirectories = false,
        IgnoreInaccessible = true,
        AttributesToSkip = FileAttributes.Hidden | FileAttributes.System,
    };

    public static IReadOnlyList<string> Resolve(LauncherSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        return Resolve(settings, KnownFolders(), CloudRoots());
    }

    /// <summary>Composition only; the detectors are passed in so it can be unit-tested.</summary>
    public static IReadOnlyList<string> Resolve(LauncherSettings settings, IEnumerable<string> knownFolders, IEnumerable<string> cloudRoots)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(knownFolders);
        ArgumentNullException.ThrowIfNull(cloudRoots);

        var result = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        if (settings.IncludeKnownFolders)
        {
            AddAll(knownFolders);
        }

        if (settings.IncludeCloudDrives)
        {
            AddAll(cloudRoots);
        }

        AddAll(settings.FolderRoots);
        return result;

        void AddAll(IEnumerable<string> paths)
        {
            foreach (var path in paths)
            {
                var normalized = Normalize(path);
                if (normalized is not null && seen.Add(normalized))
                {
                    result.Add(normalized);
                }
            }
        }
    }

    /// <summary>Desktop, Documents, Downloads, Pictures, Videos, Music and the profile folder itself.</summary>
    public static IReadOnlyList<string> KnownFolders()
    {
        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return
        [
            Environment.GetFolderPath(Environment.SpecialFolder.Desktop),
            Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
            DownloadsFolder(profile),
            Environment.GetFolderPath(Environment.SpecialFolder.MyPictures),
            Environment.GetFolderPath(Environment.SpecialFolder.MyVideos),
            Environment.GetFolderPath(Environment.SpecialFolder.MyMusic),
            profile,
        ];
    }

    /// <summary>Detects cloud-sync roots on this machine.</summary>
    public static IReadOnlyList<string> CloudRoots()
    {
        var drives = new List<(string Root, string Label)>();
        try
        {
            foreach (var drive in DriveInfo.GetDrives())
            {
                try
                {
                    if (drive.IsReady)
                    {
                        drives.Add((drive.Name, drive.VolumeLabel));
                    }
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                {
                    // A drive that refuses to answer is simply not a cloud drive we can index.
                }
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
        }

        var dropboxInfo = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Dropbox", "info.json");
        return CloudRoots(
            drives,
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            Environment.GetEnvironmentVariable,
            dropboxInfo);
    }

    /// <summary>Detection logic with its inputs injected so it can be unit-tested.</summary>
    public static IReadOnlyList<string> CloudRoots(
        IEnumerable<(string Root, string Label)> drives,
        string profile,
        Func<string, string?> getEnvironmentVariable,
        string? dropboxInfoPath)
    {
        ArgumentNullException.ThrowIfNull(drives);
        ArgumentNullException.ThrowIfNull(getEnvironmentVariable);

        var roots = new List<string>();

        // OneDrive sets these for personal and work accounts.
        foreach (var variable in OneDriveEnvironmentVariables)
        {
            var value = getEnvironmentVariable(variable);
            if (!string.IsNullOrWhiteSpace(value) && Directory.Exists(value))
            {
                roots.Add(value);
            }
        }

        // Google Drive in streaming mode mounts a virtual drive labelled "Google Drive" whose top level holds
        // "내 드라이브"/"My Drive", "공유 드라이브"/"Shared drives", "다른 컴퓨터". Each of those becomes a root.
        foreach (var (driveRoot, label) in drives)
        {
            if (label.Contains("Google Drive", StringComparison.OrdinalIgnoreCase))
            {
                roots.AddRange(TopLevelFolders(driveRoot));
            }
        }

        // Mirror-mode Google Drive, Dropbox and iCloud live directly under the profile.
        if (!string.IsNullOrEmpty(profile))
        {
            foreach (var name in CloudFolderNamesInProfile)
            {
                var path = Path.Combine(profile, name);
                if (Directory.Exists(path))
                {
                    roots.Add(path);
                }
            }
        }

        roots.AddRange(DropboxFolders(dropboxInfoPath));
        return roots;
    }

    private static string DownloadsFolder(string profile)
    {
        if (OperatingSystem.IsWindows())
        {
            var known = TryGetKnownFolderPath(FolderIdDownloads);
            if (!string.IsNullOrEmpty(known))
            {
                return known;
            }
        }

        return Path.Combine(profile, "Downloads");
    }

    private static IEnumerable<string> TopLevelFolders(string root)
    {
        try
        {
            return Directory.EnumerateDirectories(root, "*", TopLevelOptions)
                .Where(d => Path.GetFileName(d) is { Length: > 0 } name && name[0] is not ('.' or '$'))
                .ToList();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return [];
        }
    }

    /// <summary>Dropbox writes %LOCALAPPDATA%\Dropbox\info.json: { "personal": { "path": "..." }, "business": { "path": "..." } }.</summary>
    private static IEnumerable<string> DropboxFolders(string? infoPath)
    {
        if (string.IsNullOrEmpty(infoPath) || !File.Exists(infoPath))
        {
            return [];
        }

        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(infoPath));
            return document.RootElement.EnumerateObject()
                .Where(account => account.Value.ValueKind == JsonValueKind.Object
                                  && account.Value.TryGetProperty("path", out var p)
                                  && p.ValueKind == JsonValueKind.String)
                .Select(account => account.Value.GetProperty("path").GetString()!)
                .Where(Directory.Exists)
                .ToList();
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException)
        {
            return [];
        }
    }

    private static string? Normalize(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return null;
        }

        try
        {
            var full = Path.GetFullPath(Environment.ExpandEnvironmentVariables(path.Trim()));
            return Path.TrimEndingDirectorySeparator(full);
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return null;
        }
    }

    private static string? TryGetKnownFolderPath(Guid folderId)
    {
        var pointer = IntPtr.Zero;
        try
        {
            var hr = SHGetKnownFolderPath(folderId, 0, IntPtr.Zero, out pointer);
            return hr == 0 ? Marshal.PtrToStringUni(pointer) : null;
        }
        catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException)
        {
            return null;
        }
        finally
        {
            if (pointer != IntPtr.Zero)
            {
                Marshal.FreeCoTaskMem(pointer);
            }
        }
    }

    [DllImport("shell32.dll")]
    private static extern int SHGetKnownFolderPath([MarshalAs(UnmanagedType.LPStruct)] Guid rfid, uint dwFlags, IntPtr hToken, out IntPtr ppszPath);
}
