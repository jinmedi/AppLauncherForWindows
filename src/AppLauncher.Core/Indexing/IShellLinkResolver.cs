namespace AppLauncher.Core.Indexing;

/// <summary>Contents of a Windows shortcut (.lnk).</summary>
public sealed record ShellLinkTarget(
    string TargetPath,
    string? Arguments,
    string? WorkingDirectory,
    string? Description,
    string? IconPath);

public interface IShellLinkResolver
{
    /// <summary>Returns null when the shortcut cannot be read or has no file target (e.g. Store app links).</summary>
    ShellLinkTarget? Resolve(string shortcutPath);
}
