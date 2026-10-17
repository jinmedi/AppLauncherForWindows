using AppLauncher.Core.Models;

namespace AppLauncher.Core.Search;

public sealed record SearchResult(AppEntry Entry, int Score);

/// <summary>Ranks index entries against a query. Multi-word queries require every word to match.</summary>
public static class AppSearcher
{
    /// <summary>Keyword hits (exe name, folder, description) count a little less than name hits.</summary>
    private const double KeywordWeight = 0.85;

    public static IReadOnlyList<SearchResult> Search(string? query, IReadOnlyList<AppEntry> entries, int maxResults = 8)
    {
        ArgumentNullException.ThrowIfNull(entries);

        if (string.IsNullOrWhiteSpace(query) || maxResults <= 0)
        {
            return [];
        }

        var terms = query.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var results = new List<SearchResult>();

        foreach (var entry in entries)
        {
            var total = 0;
            var matchedAll = true;

            foreach (var term in terms)
            {
                var best = ScoreEntry(term, entry);
                if (best == FuzzyMatcher.NoMatch)
                {
                    matchedAll = false;
                    break;
                }

                total += best;
            }

            if (matchedAll)
            {
                results.Add(new SearchResult(entry, total / terms.Length));
            }
        }

        return results
            .OrderByDescending(r => r.Score)
            .ThenBy(r => r.Entry.Name.Length)
            .ThenBy(r => r.Entry.Name, StringComparer.CurrentCultureIgnoreCase)
            .Take(maxResults)
            .ToArray();
    }

    private static int ScoreEntry(string term, AppEntry entry)
    {
        var best = FuzzyMatcher.Score(term, entry.Name);

        foreach (var keyword in entry.Keywords)
        {
            var keywordScore = FuzzyMatcher.Score(term, keyword);
            if (keywordScore != FuzzyMatcher.NoMatch)
            {
                best = Math.Max(best, (int)(keywordScore * KeywordWeight));
            }
        }

        return best;
    }
}
