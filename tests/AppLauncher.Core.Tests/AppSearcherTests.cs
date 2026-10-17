using AppLauncher.Core.Models;
using AppLauncher.Core.Search;

namespace AppLauncher.Core.Tests;

public class AppSearcherTests
{
    private static readonly AppEntry KakaoTalk = Make("카카오톡", "KakaoTalk");
    private static readonly AppEntry Notepad = Make("메모장", "notepad");
    private static readonly AppEntry VsCode = Make("Visual Studio Code", "Code");
    private static readonly AppEntry VisualStudio = Make("Visual Studio 2022", "devenv");
    private static readonly AppEntry Calculator = Make("계산기", "calc");

    private static readonly AppEntry[] All = [Notepad, VsCode, VisualStudio, KakaoTalk, Calculator];

    [Fact]
    public void Search_FindsKoreanNameByKoreanPrefix()
    {
        var results = AppSearcher.Search("카카", All);

        Assert.Single(results);
        Assert.Same(KakaoTalk, results[0].Entry);
    }

    [Fact]
    public void Search_FindsKoreanNameByEnglishExecutableKeyword()
    {
        var results = AppSearcher.Search("kakao", All);

        Assert.Single(results);
        Assert.Same(KakaoTalk, results[0].Entry);
    }

    [Fact]
    public void Search_NameMatchOutranksKeywordMatch()
    {
        var byName = Make("Code Writer", "writer");
        var byKeyword = Make("Editor", "code");

        var results = AppSearcher.Search("code", [byKeyword, byName]);

        Assert.Equal(2, results.Count);
        Assert.Same(byName, results[0].Entry);
    }

    [Fact]
    public void Search_MultiWordQuery_RequiresEveryWord()
    {
        var results = AppSearcher.Search("visual code", All);

        Assert.Single(results);
        Assert.Same(VsCode, results[0].Entry);
    }

    [Fact]
    public void Search_RespectsMaxResults()
    {
        var results = AppSearcher.Search("visual", All, maxResults: 1);

        Assert.Single(results);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Search_EmptyQuery_ReturnsNothing(string? query)
    {
        Assert.Empty(AppSearcher.Search(query, All));
    }

    [Fact]
    public void Search_NoMatch_ReturnsNothing()
    {
        Assert.Empty(AppSearcher.Search("qqqq", All));
    }

    [Fact]
    public void Search_OnEqualScore_AppOutranksFolder()
    {
        var folder = new AppEntry { Id = "folder:x", Name = "Slack", LaunchPath = @"C:\Users\me\Slack", Source = AppSource.Folder };
        var app = new AppEntry { Id = "startmenu:x", Name = "Slack", LaunchPath = @"C:\fake\Slack.lnk", Source = AppSource.StartMenu };

        var results = AppSearcher.Search("slack", [folder, app]);

        Assert.Equal(2, results.Count);
        Assert.Equal(results[0].Score, results[1].Score);
        Assert.Same(app, results[0].Entry);
    }

    [Fact]
    public void Search_SameNamedFolders_ShallowerPathFirst()
    {
        var deep = new AppEntry { Id = "folder:deep", Name = "Downloads", LaunchPath = @"C:\Users\me\OneDrive\Backup\Downloads", Source = AppSource.Folder };
        var root = new AppEntry { Id = "folder:root", Name = "Downloads", LaunchPath = @"C:\Users\me\Downloads", Source = AppSource.Folder };

        var results = AppSearcher.Search("downloads", [deep, root]);

        Assert.Same(root, results[0].Entry);
        Assert.Same(deep, results[1].Entry);
    }

    [Fact]
    public void Search_FolderWithBetterScore_StillWins()
    {
        var folder = new AppEntry { Id = "folder:x", Name = "Invoices", LaunchPath = @"C:\Users\me\Invoices", Source = AppSource.Folder };
        var app = new AppEntry { Id = "startmenu:x", Name = "Invoice Tool Deluxe", LaunchPath = @"C:\fake\tool.lnk", Source = AppSource.StartMenu };

        var results = AppSearcher.Search("invoices", [app, folder]);

        Assert.Same(folder, results[0].Entry);
    }

    private static AppEntry Make(string name, string exeName) => new()
    {
        Id = "test:" + name,
        Name = name,
        LaunchPath = $@"C:\fake\{name}.lnk",
        TargetPath = $@"C:\fake\{exeName}.exe",
        Keywords = [exeName],
    };
}
