using AppLauncher.Core.Indexing;
using AppLauncher.Core.Models;
using AppLauncher.Core.Services;

namespace AppLauncher.Core.Tests;

public sealed class AppIndexTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), "AppLauncherTests", Guid.NewGuid().ToString("N"));

    private static readonly AppEntry Notepad = Make("메모장");
    private static readonly AppEntry Code = Make("Visual Studio Code");
    private static readonly AppEntry Kakao = Make("카카오톡");

    [Fact]
    public async Task MostUsed_ListsIndexedEntriesByLaunchCount_SkippingUnknownIds()
    {
        var history = new UsageHistory(Path.Combine(_directory, "history.json"));
        history.Record(Code.Id, "code");
        history.Record(Kakao.Id, null);
        history.Record(Kakao.Id, null);
        history.Record("test:Uninstalled", null);
        history.Record("test:Uninstalled", null);
        history.Record("test:Uninstalled", null);

        var index = new AppIndex([new StubSource(Notepad, Code, Kakao)], history);
        await index.RefreshAsync();

        var results = index.MostUsed();

        Assert.Equal([Kakao, Code], results.Select(r => r.Entry));
        Assert.All(results, r => Assert.Equal(r.Score, r.Boost));
        Assert.Equal(0, results[0].MatchScore);
    }

    [Fact]
    public async Task MostUsed_RespectsMaxResults_AndMatchesIdsCaseInsensitively()
    {
        var history = new UsageHistory(Path.Combine(_directory, "history.json"));
        history.Record(Kakao.Id.ToUpperInvariant(), null);
        history.Record(Kakao.Id.ToUpperInvariant(), null);
        history.Record(Code.Id, null);

        var index = new AppIndex([new StubSource(Code, Kakao)], history);
        await index.RefreshAsync();

        var results = index.MostUsed(maxResults: 1);

        Assert.Single(results);
        Assert.Same(Kakao, results[0].Entry);
    }

    [Fact]
    public async Task MostUsed_IsEmpty_WithoutHistoryOrBeforeRefresh()
    {
        var withoutHistory = new AppIndex([new StubSource(Code)]);
        await withoutHistory.RefreshAsync();
        Assert.Empty(withoutHistory.MostUsed());

        var history = new UsageHistory(Path.Combine(_directory, "history.json"));
        history.Record(Code.Id, null);
        var notRefreshed = new AppIndex([new StubSource(Code)], history);
        Assert.Empty(notRefreshed.MostUsed());
    }

    public void Dispose()
    {
        if (Directory.Exists(_directory))
        {
            Directory.Delete(_directory, recursive: true);
        }
    }

    private static AppEntry Make(string name) => new()
    {
        Id = "test:" + name,
        Name = name,
        LaunchPath = $@"C:\fake\{name}.lnk",
    };

    private sealed class StubSource(params AppEntry[] entries) : IAppSource
    {
        public string Name => "stub";

        public Task<IReadOnlyList<AppEntry>> ScanAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<AppEntry>>(entries);
    }
}
