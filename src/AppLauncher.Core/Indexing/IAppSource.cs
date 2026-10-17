using AppLauncher.Core.Models;

namespace AppLauncher.Core.Indexing;

/// <summary>Something that can enumerate launchable apps (Start Menu, registry, Store, ...).</summary>
public interface IAppSource
{
    string Name { get; }

    Task<IReadOnlyList<AppEntry>> ScanAsync(CancellationToken cancellationToken = default);
}
