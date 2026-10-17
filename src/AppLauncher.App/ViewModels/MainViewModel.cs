using AppLauncher.Core.Models;
using CommunityToolkit.Mvvm.ComponentModel;

namespace AppLauncher.App.ViewModels;

public partial class MainViewModel : ObservableObject
{
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsQueryEmpty))]
    private string _query = string.Empty;

    public MainViewModel(LauncherSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        HintText = $"Esc 닫기   ·   {settings.GetHotkeyOrDefault()} 열기/닫기";
    }

    public bool IsQueryEmpty => string.IsNullOrEmpty(Query);

    public string HintText { get; }
}
