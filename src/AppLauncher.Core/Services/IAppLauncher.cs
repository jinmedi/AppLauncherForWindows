using System.Diagnostics;
using AppLauncher.Core.Models;

namespace AppLauncher.Core.Services;

public interface IAppLauncher
{
    /// <summary>Starts the app. Throws on failure so the caller can show a message.</summary>
    void Launch(AppEntry entry);
}

/// <summary>
/// Launches through the shell (ShellExecute). Handing it the .lnk itself means the shortcut's own
/// arguments, working directory and "run as" settings are honoured without re-implementing them.
/// When the target is already running and <c>activateRunningApps</c> is on, its window is brought to the
/// front instead: a second instance of a tray-resident app can take seconds to hand over to the first.
/// </summary>
public sealed class ShellAppLauncher : IAppLauncher
{
    private readonly IRunningAppActivator? _activator;

    public ShellAppLauncher()
        : this(null)
    {
    }

    /// <param name="activator">Consulted before launching; null disables activation of running apps.</param>
    public ShellAppLauncher(IRunningAppActivator? activator)
    {
        _activator = activator;
    }

    public void Launch(AppEntry entry)
    {
        ArgumentNullException.ThrowIfNull(entry);

        // Folders always open a new Explorer window; apps are activated when already running.
        if (_activator is not null && entry.Source != AppSource.Folder && entry.TargetPath is { Length: > 0 } target
            && _activator.TryActivate(target))
        {
            return;
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = entry.LaunchPath,
            UseShellExecute = true,
            WorkingDirectory = entry.WorkingDirectory ?? string.Empty,
        };

        using var process = Process.Start(startInfo);
    }
}
