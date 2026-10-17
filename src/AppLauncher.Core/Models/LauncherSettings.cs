namespace AppLauncher.Core.Models;

/// <summary>User-editable settings persisted as JSON.</summary>
public sealed class LauncherSettings
{
    /// <summary>Hotkey text in the form understood by <see cref="HotkeySpec.TryParse"/>.</summary>
    public string Hotkey { get; set; } = HotkeySpec.Default.ToString();

    public bool StartWithWindows { get; set; }

    public HotkeySpec GetHotkeyOrDefault() =>
        HotkeySpec.TryParse(Hotkey, out var spec) ? spec : HotkeySpec.Default;
}
