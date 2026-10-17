namespace AppLauncher.Core.Models;

public enum AppSource
{
    StartMenu,
    Registry,
    Store,
    Folder,
    Custom,
}

/// <summary>One launchable item in the index.</summary>
public sealed record AppEntry
{
    /// <summary>Stable, case-insensitive key used for de-duplication and usage history.</summary>
    public required string Id { get; init; }

    /// <summary>Display name, e.g. "카카오톡".</summary>
    public required string Name { get; init; }

    /// <summary>What gets handed to the shell to launch. For Start Menu items this is the .lnk itself.</summary>
    public required string LaunchPath { get; init; }

    /// <summary>Resolved executable, when known. Used for icons and as a search keyword.</summary>
    public string? TargetPath { get; init; }

    public string? Arguments { get; init; }

    public string? WorkingDirectory { get; init; }

    public string? Description { get; init; }

    public AppSource Source { get; init; }

    /// <summary>Extra searchable terms (executable name, folder name, description).</summary>
    public IReadOnlyList<string> Keywords { get; init; } = [];
}
