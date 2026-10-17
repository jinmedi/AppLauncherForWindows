using System.Text.Json;
using System.Text.Json.Serialization;
using AppLauncher.Core.Models;

namespace AppLauncher.Core.Services;

/// <summary>Loads and saves <see cref="LauncherSettings"/> as a JSON file.</summary>
public sealed class SettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };

    public SettingsStore(string filePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);
        FilePath = filePath;
    }

    public string FilePath { get; }

    /// <summary>%APPDATA%\AppLauncherForWindows\settings.json</summary>
    public static string DefaultPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "AppLauncherForWindows",
        "settings.json");

    /// <summary>Returns defaults when the file is missing or unreadable.</summary>
    public LauncherSettings Load()
    {
        if (!File.Exists(FilePath))
        {
            return new LauncherSettings();
        }

        try
        {
            using var stream = File.OpenRead(FilePath);
            return JsonSerializer.Deserialize<LauncherSettings>(stream, JsonOptions) ?? new LauncherSettings();
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException)
        {
            return new LauncherSettings();
        }
    }

    public void Save(LauncherSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);

        var directory = Path.GetDirectoryName(FilePath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        // Write to a temp file first so a crash mid-write never leaves a truncated settings file.
        var tempPath = FilePath + ".tmp";
        using (var stream = File.Create(tempPath))
        {
            JsonSerializer.Serialize(stream, settings, JsonOptions);
        }

        File.Move(tempPath, FilePath, overwrite: true);
    }
}
