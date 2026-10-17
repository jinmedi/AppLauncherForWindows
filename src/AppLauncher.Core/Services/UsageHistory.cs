using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AppLauncher.Core.Services;

/// <summary>
/// Remembers what was launched, how often, when, and with which query, and turns that into a
/// ranking boost so frequently used items float to the top of matching results.
/// Persisted as JSON next to settings.json. Safe to call from any thread.
/// </summary>
public sealed class UsageHistory
{
    public const int MaxCountBoost = 300;
    public const int ExactQueryBoost = 400;
    public const int PartialQueryBoost = 200;

    private const int PointsPerLaunch = 15;
    private const int CountCap = MaxCountBoost / PointsPerLaunch;
    private const int MaxQueriesPerEntry = 10;
    private const int MaxEntries = 1000;
    private static readonly TimeSpan RetainFor = TimeSpan.FromDays(180);

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };

    private readonly object _gate = new();
    private readonly Func<DateTimeOffset> _clock;
    private Dictionary<string, UsageRecord> _records = new(StringComparer.OrdinalIgnoreCase);

    public UsageHistory(string filePath, Func<DateTimeOffset>? clock = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);
        FilePath = filePath;
        _clock = clock ?? (() => DateTimeOffset.Now);
    }

    public string FilePath { get; }

    /// <summary>%APPDATA%\AppLauncherForWindows\history.json</summary>
    public static string DefaultPath => Path.Combine(Path.GetDirectoryName(SettingsStore.DefaultPath)!, "history.json");

    public int Count
    {
        get { lock (_gate) { return _records.Count; } }
    }

    /// <summary>Loads the file; a missing or corrupt file simply means no history.</summary>
    public void Load()
    {
        Dictionary<string, UsageRecord> loaded = new(StringComparer.OrdinalIgnoreCase);
        try
        {
            if (File.Exists(FilePath))
            {
                using var stream = File.OpenRead(FilePath);
                var file = JsonSerializer.Deserialize<HistoryFile>(stream, JsonOptions);
                if (file?.Entries is not null)
                {
                    foreach (var (id, record) in file.Entries)
                    {
                        if (!string.IsNullOrEmpty(id) && record is not null)
                        {
                            loaded[id] = record;
                        }
                    }
                }
            }
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException)
        {
            loaded.Clear();
        }

        lock (_gate)
        {
            _records = loaded;
        }
    }

    /// <summary>Records one launch of <paramref name="entryId"/> made from <paramref name="query"/> and saves.</summary>
    public void Record(string entryId, string? query)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(entryId);

        var now = _clock();
        var normalizedQuery = NormalizeQuery(query);

        lock (_gate)
        {
            if (!_records.TryGetValue(entryId, out var record))
            {
                record = new UsageRecord();
                _records[entryId] = record;
            }

            record.Count++;
            record.LastLaunched = now;

            if (normalizedQuery.Length > 0)
            {
                record.Queries[normalizedQuery] = record.Queries.GetValueOrDefault(normalizedQuery) + 1;
                if (record.Queries.Count > MaxQueriesPerEntry)
                {
                    // Never evict the query just recorded; Dictionary enumeration order reuses freed slots, so "first" is not "oldest".
                    var weakest = record.Queries.Where(q => q.Key != normalizedQuery).OrderBy(q => q.Value).First().Key;
                    record.Queries.Remove(weakest);
                }
            }

            SaveLocked(now);
        }
    }

    public int LaunchCount(string entryId)
    {
        lock (_gate)
        {
            return _records.TryGetValue(entryId, out var r) ? r.Count : 0;
        }
    }

    /// <summary>
    /// Ranking bonus for <paramref name="entryId"/> when the user typed <paramref name="query"/>:
    /// launches (15 each, capped at 300) + recency (60/40/20 within 1/7/30 days)
    /// + 400 if this exact query launched it before, or 200 if a remembered query shares a prefix with it.
    /// </summary>
    public int BoostFor(string entryId, string? query)
    {
        if (string.IsNullOrEmpty(entryId))
        {
            return 0;
        }

        UsageRecord? record;
        lock (_gate)
        {
            if (!_records.TryGetValue(entryId, out record))
            {
                return 0;
            }

            record = record.Clone();
        }

        var boost = Math.Min(record.Count, CountCap) * PointsPerLaunch;

        var age = _clock() - record.LastLaunched;
        boost += age switch
        {
            _ when age < TimeSpan.FromDays(1) => 60,
            _ when age < TimeSpan.FromDays(7) => 40,
            _ when age < TimeSpan.FromDays(30) => 20,
            _ => 0,
        };

        var q = NormalizeQuery(query);
        if (q.Length > 0)
        {
            if (record.Queries.ContainsKey(q))
            {
                boost += ExactQueryBoost;
            }
            else if (record.Queries.Keys.Any(k => k.StartsWith(q, StringComparison.Ordinal) || q.StartsWith(k, StringComparison.Ordinal)))
            {
                boost += PartialQueryBoost;
            }
        }

        return boost;
    }

    private static string NormalizeQuery(string? query) => (query ?? string.Empty).Trim().ToLowerInvariant();

    /// <summary>Caller holds the lock. Drops stale entries, keeps the most-used, and writes atomically.</summary>
    private void SaveLocked(DateTimeOffset now)
    {
        var cutoff = now - RetainFor;
        foreach (var stale in _records.Where(kv => kv.Value.LastLaunched < cutoff).Select(kv => kv.Key).ToList())
        {
            _records.Remove(stale);
        }

        if (_records.Count > MaxEntries)
        {
            foreach (var overflow in _records.OrderBy(kv => kv.Value.Count).ThenBy(kv => kv.Value.LastLaunched)
                         .Take(_records.Count - MaxEntries).Select(kv => kv.Key).ToList())
            {
                _records.Remove(overflow);
            }
        }

        try
        {
            var directory = Path.GetDirectoryName(FilePath);
            if (!string.IsNullOrEmpty(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var tempPath = FilePath + ".tmp";
            using (var stream = File.Create(tempPath))
            {
                JsonSerializer.Serialize(stream, new HistoryFile { Entries = _records }, JsonOptions);
            }

            File.Move(tempPath, FilePath, overwrite: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Losing one save is acceptable; the in-memory history still ranks this session.
        }
    }

    private sealed class HistoryFile
    {
        public Dictionary<string, UsageRecord>? Entries { get; set; }
    }

    private sealed class UsageRecord
    {
        public int Count { get; set; }

        public DateTimeOffset LastLaunched { get; set; }

        [JsonInclude]
        public Dictionary<string, int> Queries { get; set; } = new(StringComparer.Ordinal);

        public UsageRecord Clone() => new()
        {
            Count = Count,
            LastLaunched = LastLaunched,
            Queries = new Dictionary<string, int>(Queries, StringComparer.Ordinal),
        };
    }
}
