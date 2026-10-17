namespace AppLauncher.Core.Search;

/// <summary>
/// Scores how well a query matches a candidate string. Higher is better; <see cref="NoMatch"/> means no match.
/// Tiers, best first: exact, prefix, word-start prefix, acronym, substring, in-order subsequence.
/// Works on code points, so Korean syllables match the same way as Latin letters.
/// </summary>
public static class FuzzyMatcher
{
    public const int NoMatch = -1;

    private static readonly char[] WordSeparators = [' ', '-', '_', '.', '(', ')', '[', ']', '/', '\\', ','];

    public static int Score(string query, string candidate)
    {
        if (string.IsNullOrWhiteSpace(query) || string.IsNullOrEmpty(candidate))
        {
            return NoMatch;
        }

        var q = query.Trim().ToLowerInvariant();
        var c = candidate.ToLowerInvariant();

        if (c == q)
        {
            return 1000;
        }

        if (c.StartsWith(q, StringComparison.Ordinal))
        {
            return 900 - Math.Min(c.Length - q.Length, 50);
        }

        var words = c.Split(WordSeparators, StringSplitOptions.RemoveEmptyEntries);
        for (var i = 0; i < words.Length; i++)
        {
            if (words[i].StartsWith(q, StringComparison.Ordinal))
            {
                return 800 - Math.Min(i * 10, 50);
            }
        }

        if (words.Length > 1 && q.Length >= 2)
        {
            var acronym = string.Concat(words.Select(w => w[0]));
            if (acronym.StartsWith(q, StringComparison.Ordinal))
            {
                return 750;
            }
        }

        var index = c.IndexOf(q, StringComparison.Ordinal);
        if (index >= 0)
        {
            return 600 - Math.Min(index * 5, 150);
        }

        return SubsequenceScore(q, c);
    }

    /// <summary>
    /// All query characters must appear in order. Rewards runs of consecutive matches and matches
    /// at word starts; penalises gaps so "kt" prefers "KakaoTalk" over "k....t" spread far apart.
    /// </summary>
    private static int SubsequenceScore(string q, string c)
    {
        var score = 300;
        var ci = 0;
        var previousMatch = -2;

        for (var qi = 0; qi < q.Length; qi++)
        {
            var found = c.IndexOf(q[qi], ci);
            if (found < 0)
            {
                return NoMatch;
            }

            if (found == previousMatch + 1)
            {
                score += 12;
            }
            else
            {
                var gap = found - Math.Max(previousMatch + 1, 0);
                score -= Math.Min(gap * 2, 40);
            }

            if (found == 0 || Array.IndexOf(WordSeparators, c[found - 1]) >= 0)
            {
                score += 15;
            }

            previousMatch = found;
            ci = found + 1;
        }

        return Math.Max(score, 1);
    }
}
