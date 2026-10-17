using AppLauncher.Core.Search;

namespace AppLauncher.Core.Tests;

public class FuzzyMatcherTests
{
    [Fact]
    public void TiersAreOrdered_ExactBeatsPrefixBeatsWordStartBeatsSubstringBeatsSubsequence()
    {
        var exact = FuzzyMatcher.Score("code", "code");
        var prefix = FuzzyMatcher.Score("code", "Code Editor");
        var wordStart = FuzzyMatcher.Score("code", "Visual Studio Code");
        var substring = FuzzyMatcher.Score("code", "xcodex");
        var subsequence = FuzzyMatcher.Score("code", "cxoxdxe");   // no separators, so no acronym tier

        Assert.True(exact > prefix, $"{exact} > {prefix}");
        Assert.True(prefix > wordStart, $"{prefix} > {wordStart}");
        Assert.True(wordStart > substring, $"{wordStart} > {substring}");
        Assert.True(substring > subsequence, $"{substring} > {subsequence}");
        Assert.True(subsequence > 0);
    }

    [Theory]
    [InlineData("카카", "카카오톡")]
    [InlineData("카오", "카카오톡")]
    [InlineData("KAKAO", "KakaoTalk")]
    [InlineData("vsc", "Visual Studio Code")]
    [InlineData("kt", "KakaoTalk")]
    public void Score_MatchesCaseInsensitivelyAndAcrossScripts(string query, string candidate)
    {
        Assert.NotEqual(FuzzyMatcher.NoMatch, FuzzyMatcher.Score(query, candidate));
    }

    [Theory]
    [InlineData("zzz", "KakaoTalk")]
    [InlineData("talkkakao", "KakaoTalk")]   // right letters, wrong order
    [InlineData("", "KakaoTalk")]
    [InlineData("   ", "KakaoTalk")]
    [InlineData("a", "")]
    public void Score_ReturnsNoMatch_WhenQueryCannotBeFound(string query, string candidate)
    {
        Assert.Equal(FuzzyMatcher.NoMatch, FuzzyMatcher.Score(query, candidate));
    }

    [Fact]
    public void Acronym_MatchesFirstLettersOfWords()
    {
        var acronym = FuzzyMatcher.Score("vsc", "Visual Studio Code");
        var scattered = FuzzyMatcher.Score("vsc", "Advanced Scanner");

        Assert.True(acronym > scattered, $"{acronym} > {scattered}");
    }

    [Fact]
    public void ShorterCandidate_WinsOnEqualPrefix()
    {
        var shorter = FuzzyMatcher.Score("note", "Notepad");
        var longer = FuzzyMatcher.Score("note", "Notepad++ Portable Edition");

        Assert.True(shorter > longer, $"{shorter} > {longer}");
    }
}
