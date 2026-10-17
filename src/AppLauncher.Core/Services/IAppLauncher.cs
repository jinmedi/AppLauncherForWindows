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
/// </summary>
public sealed class ShellAppLauncher : IAppLauncher
{
    public void Launch(AppEntry entry)
    {
        ArgumentNullException.ThrowIfNull(entry);

        var startInfo = new ProcessStartInfo
        {
            FileName = entry.LaunchPath,
            UseShellExecute = true,
            WorkingDirectory = entry.WorkingDirectory ?? string.Empty,
        };

        using var process = Process.Start(startInfo);
    }
}
