using AppLauncher.Core.Models;

namespace AppLauncher.Core.Tests;

public class HotkeySpecTests
{
    [Theory]
    [InlineData("Alt+Space", HotkeyModifiers.Alt, "Space")]
    [InlineData("ctrl + shift + k", HotkeyModifiers.Control | HotkeyModifiers.Shift, "K")]
    [InlineData("Win+1", HotkeyModifiers.Win, "D1")]
    [InlineData("Control+Alt+F12", HotkeyModifiers.Control | HotkeyModifiers.Alt, "F12")]
    public void TryParse_AcceptsValidCombinations(string text, HotkeyModifiers modifiers, string key)
    {
        Assert.True(HotkeySpec.TryParse(text, out var spec));
        Assert.Equal(modifiers, spec.Modifiers);
        Assert.Equal(key, spec.Key);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("Space")]        // no modifier
    [InlineData("Alt+")]         // no key
    [InlineData("Foo+Space")]    // unknown modifier
    [InlineData("Alt+Ctrl")]     // modifier used as key
    public void TryParse_RejectsInvalidInput(string? text)
    {
        Assert.False(HotkeySpec.TryParse(text, out var spec));
        Assert.Equal(HotkeySpec.Default, spec);
    }

    [Fact]
    public void ToString_RoundTripsThroughParse()
    {
        var original = new HotkeySpec(HotkeyModifiers.Control | HotkeyModifiers.Win, "Space");
        var text = original.ToString();

        Assert.Equal("Ctrl+Win+Space", text);
        Assert.Equal(original, HotkeySpec.Parse(text));
    }

    [Fact]
    public void Parse_ThrowsOnInvalidText()
    {
        Assert.Throws<FormatException>(() => HotkeySpec.Parse("nonsense"));
    }
}
