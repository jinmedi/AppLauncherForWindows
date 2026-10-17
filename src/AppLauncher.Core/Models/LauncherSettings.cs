using AppLauncher.Core.Indexing;

namespace AppLauncher.Core.Models;

/// <summary>User-editable settings persisted as JSON.</summary>
public sealed class LauncherSettings
{
    /// <summary>Hotkey text in the form understood by <see cref="HotkeySpec.TryParse"/>.</summary>
    public string Hotkey { get; set; } = HotkeySpec.Default.ToString();

    public bool StartWithWindows { get; set; }

    /// <summary>Index Desktop, Documents, Downloads, Pictures, Videos, Music and the profile folder.</summary>
    public bool IncludeKnownFolders { get; set; } = true;

    /// <summary>Auto-detect and index OneDrive, Google Drive, Dropbox and iCloud folders.</summary>
    public bool IncludeCloudDrives { get; set; } = true;

    /// <summary>Extra folders to index on top of the detected ones. Environment variables are expanded.</summary>
    public List<string> FolderRoots { get; set; } = [];

    /// <summary>How many levels below each root to index. 0 indexes only the roots themselves.</summary>
    public int FolderScanDepth { get; set; } = FolderScanner.DefaultMaxDepth;

    public HotkeySpec GetHotkeyOrDefault() =>
        HotkeySpec.TryParse(Hotkey, out var spec) ? spec : HotkeySpec.Default;
}
