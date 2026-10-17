namespace AppLauncher.Core.Models;

/// <summary>
/// Modifier flags for a global hotkey. Values match the Win32 MOD_* constants
/// so they can be passed straight to RegisterHotKey.
/// </summary>
[Flags]
public enum HotkeyModifiers
{
    None = 0,
    Alt = 0x0001,
    Control = 0x0002,
    Shift = 0x0004,
    Win = 0x0008,
}

/// <summary>
/// A parsed hotkey such as "Alt+Space" or "Ctrl+Shift+K".
/// The key is kept as a name (matching the WPF <c>Key</c> enum) so Core stays UI-agnostic.
/// </summary>
public sealed record HotkeySpec(HotkeyModifiers Modifiers, string Key)
{
    public static HotkeySpec Default { get; } = new(HotkeyModifiers.Alt, "Space");

    public static HotkeySpec Parse(string text)
    {
        if (!TryParse(text, out var spec))
        {
            throw new FormatException($"'{text}' is not a valid hotkey. Expected e.g. \"Alt+Space\".");
        }

        return spec;
    }

    public static bool TryParse(string? text, out HotkeySpec spec)
    {
        spec = Default;
        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        var parts = text.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length < 2)
        {
            return false;
        }

        var modifiers = HotkeyModifiers.None;
        for (var i = 0; i < parts.Length - 1; i++)
        {
            var modifier = ParseModifier(parts[i]);
            if (modifier is null)
            {
                return false;
            }

            modifiers |= modifier.Value;
        }

        var key = parts[^1];
        if (key.Length == 0 || ParseModifier(key) is not null)
        {
            return false;
        }

        spec = new HotkeySpec(modifiers, NormalizeKey(key));
        return true;
    }

    public override string ToString()
    {
        var parts = new List<string>(5);
        if (Modifiers.HasFlag(HotkeyModifiers.Control)) parts.Add("Ctrl");
        if (Modifiers.HasFlag(HotkeyModifiers.Alt)) parts.Add("Alt");
        if (Modifiers.HasFlag(HotkeyModifiers.Shift)) parts.Add("Shift");
        if (Modifiers.HasFlag(HotkeyModifiers.Win)) parts.Add("Win");
        parts.Add(Key);
        return string.Join("+", parts);
    }

    private static HotkeyModifiers? ParseModifier(string token) => token.ToLowerInvariant() switch
    {
        "ctrl" or "control" => HotkeyModifiers.Control,
        "alt" => HotkeyModifiers.Alt,
        "shift" => HotkeyModifiers.Shift,
        "win" or "windows" or "super" => HotkeyModifiers.Win,
        _ => null,
    };

    /// <summary>Single letters are upper-cased; single digits map to WPF's D0..D9 names.</summary>
    private static string NormalizeKey(string key)
    {
        if (key.Length == 1)
        {
            var c = key[0];
            if (char.IsAsciiLetter(c)) return char.ToUpperInvariant(c).ToString();
            if (char.IsAsciiDigit(c)) return "D" + c;
        }

        return key;
    }
}
