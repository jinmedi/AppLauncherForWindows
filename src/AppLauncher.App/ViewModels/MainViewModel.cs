using System.Collections.ObjectModel;
using AppLauncher.App.Interop;
using AppLauncher.Core.Models;
using AppLauncher.Core.Services;
using CommunityToolkit.Mvvm.ComponentModel;

namespace AppLauncher.App.ViewModels;

public partial class MainViewModel : ObservableObject
{
    private const int MaxResults = 8;

    private readonly AppIndex _index;
    private readonly IAppLauncher _launcher;
    private readonly IconExtractor _icons;
    private readonly SynchronizationContext? _uiContext;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsQueryEmpty))]
    private string _query = string.Empty;

    [ObservableProperty]
    private SearchResultViewModel? _selectedResult;

    [ObservableProperty]
    private string _statusText = string.Empty;

    public MainViewModel(LauncherSettings settings, AppIndex index, IAppLauncher launcher, IconExtractor icons)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(index);
        ArgumentNullException.ThrowIfNull(launcher);
        ArgumentNullException.ThrowIfNull(icons);

        _index = index;
        _launcher = launcher;
        _icons = icons;
        _uiContext = SynchronizationContext.Current;

        HintText = $"Enter 실행   ·   Ctrl+숫자 n+1번째 실행   ·   Esc 닫기   ·   {settings.GetHotkeyOrDefault()} 열기/닫기";
        _index.Refreshed += (_, _) => RunOnUiThread(OnIndexRefreshed);
        UpdateStatus();
    }

    public ObservableCollection<SearchResultViewModel> Results { get; } = [];

    public bool IsQueryEmpty => string.IsNullOrEmpty(Query);

    public bool HasResults => Results.Count > 0;

    public string HintText { get; }

    /// <summary>Raised after an app was started so the window can hide itself.</summary>
    public event EventHandler? LaunchSucceeded;

    public void MoveSelection(int delta)
    {
        if (Results.Count == 0)
        {
            return;
        }

        var current = SelectedResult is null ? -1 : Results.IndexOf(SelectedResult);
        var next = current < 0 ? 0 : (current + delta + Results.Count) % Results.Count;
        SelectedResult = Results[next];
    }

    public bool LaunchSelected()
    {
        if (SelectedResult is null)
        {
            return false;
        }

        return Launch(SelectedResult);
    }

    /// <summary>
    /// Launches the result at <paramref name="index"/> (0-based). Enter covers index 0 (the selected row),
    /// so Ctrl+1 maps to index 1, Ctrl+2 to index 2, and so on. Out-of-range indexes do nothing.
    /// </summary>
    public bool LaunchAt(int index)
    {
        if (index < 0 || index >= Results.Count)
        {
            return false;
        }

        return Launch(Results[index]);
    }

    /// <summary>Highest Ctrl+digit that is meaningful: Ctrl+1 through Ctrl+(MaxResults - 1).</summary>
    public static int MaxShortcutDigit => MaxResults - 1;

    private static string ShortcutHintFor(int index) => index == 0 ? "Enter" : $"Ctrl+{index}";

    public bool Launch(SearchResultViewModel result)
    {
        ArgumentNullException.ThrowIfNull(result);

        try
        {
            _launcher.Launch(result.Entry);
        }
        catch (Exception ex)
        {
            StatusText = $"실행 실패: {ex.Message}";
            return false;
        }

        Query = string.Empty;
        LaunchSucceeded?.Invoke(this, EventArgs.Empty);
        return true;
    }

    partial void OnQueryChanged(string value) => UpdateResults();

    private void UpdateResults()
    {
        var matches = _index.Search(Query, MaxResults);

        Results.Clear();
        foreach (var match in matches)
        {
            Results.Add(new SearchResultViewModel(match.Entry, _icons) { ShortcutHint = ShortcutHintFor(Results.Count) });
        }

        SelectedResult = Results.Count > 0 ? Results[0] : null;
        OnPropertyChanged(nameof(HasResults));
    }

    private void OnIndexRefreshed()
    {
        UpdateStatus();
        if (!IsQueryEmpty)
        {
            UpdateResults();
        }
    }

    private void UpdateStatus()
    {
        if (_index.IsRefreshing || _index.Count == 0)
        {
            StatusText = "앱 목록을 읽는 중...";
            return;
        }

        var folders = _index.Entries.Count(e => e.Source == AppSource.Folder);
        var apps = _index.Count - folders;
        var status = folders > 0 ? $"앱 {apps}개   ·   폴더 {folders}개" : $"앱 {apps}개";
        if (_index.HasErrors)
        {
            status += "   ·   일부 읽기 실패 (index.log 확인)";
        }

        StatusText = status;
    }

    private void RunOnUiThread(Action action)
    {
        if (_uiContext is null || SynchronizationContext.Current == _uiContext)
        {
            action();
        }
        else
        {
            _uiContext.Post(_ => action(), null);
        }
    }
}
