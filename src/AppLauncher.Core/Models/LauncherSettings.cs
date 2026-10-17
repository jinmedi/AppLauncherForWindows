using AppLauncher.Core.Indexing;

namespace AppLauncher.Core.Models;

/// <summary>User-editable settings persisted as JSON.</summary>
public sealed class LauncherSettings
{
    /// <summary>Hotkey text in the form understood by <see cref="HotkeySpec.TryParse"/>.</summary>
    public string Hotkey { get; set; } = HotkeySpec.Default.ToString();

    public bool StartWithWindows { get; set; }

    /// <summary>Folders to index (each root and its subfolders). Empty list disables folder search.</summary>
    public List<string> FolderRoots { get; set; } = FolderScanner.DefaultRoots().ToList();

    /// <summary>How many levels below each root to index. 0 indexes only the roots themselves.</summary>
    public int FolderScanDepth { get; set; } = FolderScanner.DefaultMaxDepth;

    public HotkeySpec GetHotkeyOrDefault() =>
        HotkeySpec.TryParse(Hotkey, out var spec) ? spec : HotkeySpec.Default;
}
