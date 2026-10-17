using AppLauncher.Core.Services;

namespace AppLauncher.Core.Tests;

public sealed class UsageHistoryTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), "AppLauncherTests", Guid.NewGuid().ToString("N"));
    private DateTimeOffset _now = new(2026, 10, 17, 12, 0, 0, TimeSpan.FromHours(9));

    private string HistoryPath => Path.Combine(_directory, "history.json");

    private UsageHistory NewHistory() => new(HistoryPath, () => _now);

    [Fact]
    public void BoostFor_IsZero_WithoutHistory()
    {
        var history = NewHistory();

        Assert.Equal(0, history.BoostFor("startmenu:x", "x"));
    }

    [Fact]
    public void Record_GrowsCountBoost_UntilCap()
    {
        var history = NewHistory();

        history.Record("app", null);
        var afterOne = history.BoostFor("app", null);

        for (var i = 0; i < 50; i++)
        {
            history.Record("app", null);
        }

        var afterMany = history.BoostFor("app", null);

        Assert.Equal(15 + 60, afterOne);                       // one launch, just now
        Assert.Equal(UsageHistory.MaxCountBoost + 60, afterMany); // capped count, just now
        Assert.Equal(51, history.LaunchCount("app"));
    }

    [Fact]
    public void BoostFor_DecaysWithAge()
    {
        var history = NewHistory();
        history.Record("app", null);

        var fresh = history.BoostFor("app", null);
        _now = _now.AddDays(3);
        var thisWeek = history.BoostFor("app", null);
        _now = _now.AddDays(20);
        var thisMonth = history.BoostFor("app", null);
        _now = _now.AddDays(60);
        var old = history.BoostFor("app", null);

        Assert.Equal(75, fresh);
        Assert.Equal(55, thisWeek);
        Assert.Equal(35, thisMonth);
        Assert.Equal(15, old);
    }

    [Fact]
    public void BoostFor_RewardsTheQueryThatLaunchedItBefore()
    {
        var history = NewHistory();
        history.Record("kakao", "  KaKao ");

        var exact = history.BoostFor("kakao", "kakao");
        var prefixOfStored = history.BoostFor("kakao", "ka");
        var extendsStored = history.BoostFor("kakao", "kakaotalk");
        var unrelated = history.BoostFor("kakao", "zoom");

        Assert.Equal(75 + UsageHistory.ExactQueryBoost, exact);
        Assert.Equal(75 + UsageHistory.PartialQueryBoost, prefixOfStored);
        Assert.Equal(75 + UsageHistory.PartialQueryBoost, extendsStored);
        Assert.Equal(75, unrelated);
    }

    [Fact]
    public void Record_PersistsAndLoadReadsItBack()
    {
        var history = NewHistory();
        history.Record("app", "ap");
        history.Record("app", "ap");
        history.Record("folder:c:\\x", "x");

        var reloaded = NewHistory();
        reloaded.Load();

        Assert.Equal(2, reloaded.Count);
        Assert.Equal(2, reloaded.LaunchCount("app"));
        Assert.Equal(30 + 60 + UsageHistory.ExactQueryBoost, reloaded.BoostFor("app", "ap"));
        Assert.False(File.Exists(HistoryPath + ".tmp"));
    }

    [Fact]
    public void Load_ToleratesMissingAndCorruptFiles()
    {
        var missing = NewHistory();
        missing.Load();
        Assert.Equal(0, missing.Count);

        Directory.CreateDirectory(_directory);
        File.WriteAllText(HistoryPath, "{ nope");
        var corrupt = NewHistory();
        corrupt.Load();
        Assert.Equal(0, corrupt.Count);
    }

    [Fact]
    public void Save_DropsEntriesNotLaunchedForSixMonths()
    {
        var history = NewHistory();
        history.Record("old", null);
        _now = _now.AddDays(200);
        history.Record("new", null);   // saving now prunes "old"

        var reloaded = NewHistory();
        reloaded.Load();

        Assert.Equal(0, reloaded.LaunchCount("old"));
        Assert.Equal(1, reloaded.LaunchCount("new"));
    }

    [Fact]
    public void Record_KeepsAtMostTenQueriesPerEntry()
    {
        var history = NewHistory();
        for (var i = 0; i < 12; i++)
        {
            history.Record("app", "q" + i);
        }

        history.Record("app", "q11"); // strongest; must survive

        const int thirteenLaunchesJustNow = 13 * 15 + 60;
        Assert.Equal(thirteenLaunchesJustNow + UsageHistory.ExactQueryBoost, history.BoostFor("app", "q11"));
        Assert.Equal(thirteenLaunchesJustNow, history.BoostFor("app", "zzz"));
    }

    public void Dispose()
    {
        if (Directory.Exists(_directory))
        {
            Directory.Delete(_directory, recursive: true);
        }
    }
}
