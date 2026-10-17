using System.ComponentModel;
using System.Windows;
using System.Windows.Input;
using AppLauncher.App.ViewModels;

namespace AppLauncher.App.Views;

public partial class MainWindow : Window
{
    public MainWindow(MainViewModel viewModel)
    {
        InitializeComponent();
        DataContext = viewModel;
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
        if (e.Key == Key.Escape)
        {
            HideLauncher();
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
