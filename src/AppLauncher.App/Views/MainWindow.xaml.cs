using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using AppLauncher.App.ViewModels;

namespace AppLauncher.App.Views;

public partial class MainWindow : Window
{
    private readonly MainViewModel _viewModel;

    public MainWindow(MainViewModel viewModel)
    {
        ArgumentNullException.ThrowIfNull(viewModel);

        InitializeComponent();
        _viewModel = viewModel;
        DataContext = viewModel;
        _viewModel.LaunchSucceeded += (_, _) => HideLauncher();
    }

    /// <summary>Shows the launcher centred near the top of the primary work area and focuses the query box.</summary>
    public void ShowLauncher()
    {
        var workArea = SystemParameters.WorkArea;
        Left = workArea.Left + (workArea.Width - Width) / 2;
        Top = workArea.Top + workArea.Height * 0.18;

        Show();
        Activate();
        QueryBox.Focus();
        QueryBox.SelectAll();
    }

    public void HideLauncher() => Hide();

    public void ToggleLauncher()
    {
        if (IsVisible && IsActive)
        {
            HideLauncher();
        }
        else
        {
            ShowLauncher();
        }
    }

    private void OnDeactivated(object? sender, EventArgs e) => HideLauncher();

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        switch (e.Key)
        {
            case Key.Escape:
                HideLauncher();
                e.Handled = true;
                break;

            case Key.Down:
                _viewModel.MoveSelection(+1);
                e.Handled = true;
                break;

            case Key.Up:
                _viewModel.MoveSelection(-1);
                e.Handled = true;
                break;

            case Key.Enter:
                _viewModel.LaunchSelected();
                e.Handled = true;
                break;
        }
    }

    private void OnResultsSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ResultsList.SelectedItem is { } selected)
        {
            ResultsList.ScrollIntoView(selected);
        }
    }

    private void OnResultClicked(object sender, MouseButtonEventArgs e)
    {
        if (sender is ListBoxItem { DataContext: SearchResultViewModel result })
        {
            _viewModel.Launch(result);
            e.Handled = true;
        }
    }

    /// <summary>Alt+F4 hides instead of closing; Application.Shutdown ignores Cancel so exit still works.</summary>
    private void OnClosing(object? sender, CancelEventArgs e)
    {
        e.Cancel = true;
        HideLauncher();
    }
}
