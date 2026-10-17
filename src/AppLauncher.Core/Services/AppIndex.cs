using AppLauncher.Core.Indexing;
using AppLauncher.Core.Models;
using AppLauncher.Core.Search;

namespace AppLauncher.Core.Services;

/// <summary>In-memory list of launchable apps gathered from all registered sources.</summary>
public sealed class AppIndex
{
    private readonly IReadOnlyList<IAppSource> _sources;
    private IReadOnlyList<AppEntry> _entries = [];

    public AppIndex(IEnumerable<IAppSource> sources)
    {
        ArgumentNullException.ThrowIfNull(sources);
        _sources = sources.ToArray();
    }

    public IReadOnlyList<AppEntry> Entries => Volatile.Read(ref _entries);

    public int Count => Entries.Count;

    public bool IsRefreshing { get; private set; }

    /// <summary>Raised on a thread-pool thread after every refresh. Marshal to the UI thread yourself.</summary>
    public event EventHandler? Refreshed;

    public async Task RefreshAsync(CancellationToken cancellationToken = default)
    {
        IsRefreshing = true;
        try
        {
            var scans = _sources.Select(s => s.ScanAsync(cancellationToken));
            var lists = await Task.WhenAll(scans).ConfigureAwait(false);

            var merged = new List<AppEntry>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var entry in lists.SelectMany(l => l))
            {
                if (seen.Add(entry.Id))
                {
                    merged.Add(entry);
                }
            }

            Volatile.Write(ref _entries, merged);
        }
        finally
        {
            IsRefreshing = false;
        }

        Refreshed?.Invoke(this, EventArgs.Empty);
    }

    public IReadOnlyList<SearchResult> Search(string? query, int maxResults = 8) =>
        AppSearcher.Search(query, Entries, maxResults);
}
