using System.Diagnostics;
using AppLauncher.Core.Indexing;
using AppLauncher.Core.Models;
using AppLauncher.Core.Search;

namespace AppLauncher.Core.Services;

/// <summary>What one source contributed to the last refresh. <see cref="Error"/> is set when it threw.</summary>
public sealed record SourceReport(string Source, int Count, TimeSpan Elapsed, string? Error);

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

    public IReadOnlyList<SourceReport> LastReport { get; private set; } = [];

    public bool HasErrors => LastReport.Any(r => r.Error is not null);

    /// <summary>Raised on a thread-pool thread after every refresh. Marshal to the UI thread yourself.</summary>
    public event EventHandler? Refreshed;

    /// <summary>Scans every source. A source that throws is reported in <see cref="LastReport"/> and skipped; the others still load.</summary>
    public async Task RefreshAsync(CancellationToken cancellationToken = default)
    {
        IsRefreshing = true;
        try
        {
            var results = await Task.WhenAll(_sources.Select(s => ScanSourceAsync(s, cancellationToken))).ConfigureAwait(false);

            var merged = new List<AppEntry>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var entry in results.SelectMany(r => r.Entries))
            {
                if (seen.Add(entry.Id))
                {
                    merged.Add(entry);
                }
            }

            LastReport = results.Select(r => r.Report).ToArray();
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

    private static async Task<(IReadOnlyList<AppEntry> Entries, SourceReport Report)> ScanSourceAsync(IAppSource source, CancellationToken cancellationToken)
    {
        var stopwatch = Stopwatch.StartNew();
        try
        {
            var entries = await source.ScanAsync(cancellationToken).ConfigureAwait(false);
            return (entries, new SourceReport(source.Name, entries.Count, stopwatch.Elapsed, null));
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            return ([], new SourceReport(source.Name, 0, stopwatch.Elapsed, ex.GetType().Name + ": " + ex.Message));
        }
    }
}
