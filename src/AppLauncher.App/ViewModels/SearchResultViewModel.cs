using System.Windows.Media;
using AppLauncher.App.Interop;
using AppLauncher.Core.Models;
using CommunityToolkit.Mvvm.ComponentModel;

namespace AppLauncher.App.ViewModels;

public partial class SearchResultViewModel : ObservableObject
{
    [ObservableProperty]
    private ImageSource? _icon;

    public SearchResultViewModel(AppEntry entry, IconExtractor icons)
    {
        ArgumentNullException.ThrowIfNull(entry);
        ArgumentNullException.ThrowIfNull(icons);

        Entry = entry;
        _ = LoadIconAsync(icons);
    }

    public AppEntry Entry { get; }

    public string Name => Entry.Name;

    public string Detail => Entry.TargetPath ?? Entry.LaunchPath;

    private async Task LoadIconAsync(IconExtractor icons)
    {
        try
        {
            // Constructed on the UI thread, so the continuation lands there too.
            Icon = await icons.GetIconAsync(Entry.LaunchPath);
        }
        catch (Exception)
        {
            // A missing icon is cosmetic; the row still works without one.
        }
    }
}
