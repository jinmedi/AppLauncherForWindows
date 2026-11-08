using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text;

namespace AppLauncher.Core.Services;

/// <summary>Brings an already running app's window to the front instead of starting a second copy.</summary>
public interface IRunningAppActivator
{
    /// <summary>
    /// True when a process running <paramref name="executablePath"/> was found and one of its windows was shown
    /// and activated. False when no such process or window exists; the caller then launches normally.
    /// </summary>
    bool TryActivate(string executablePath);
}

/// <summary>
/// Finds a running process by executable path and shows its main window. Tray-resident apps such as KakaoTalk
/// take seconds to hand a second instance over to the first one; showing the existing window directly is what
/// a tray-icon double-click does, and it is instant. The window may be hidden (minimised to the tray), so hidden
/// top-level windows are considered too, visible ones first.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class RunningAppActivator : IRunningAppActivator
{
    private const int SW_SHOW = 5;
    private const int SW_RESTORE = 9;
    private const int GWL_STYLE = -16;
    private const int GWL_EXSTYLE = -20;
    private const uint GW_OWNER = 4;
    private const long WS_CAPTION = 0x00C00000;
    private const long WS_EX_TOOLWINDOW = 0x00000080;
    private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

    public bool TryActivate(string executablePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(executablePath);

        var processName = Path.GetFileNameWithoutExtension(executablePath);
        var processes = Process.GetProcessesByName(processName);
        try
        {
            foreach (var process in processes)
            {
                if (process.Id == Environment.ProcessId || !RunsImage(process.Id, executablePath))
                {
                    continue;
                }

                var window = FindMainWindow(process.Id);
                if (window != IntPtr.Zero && Show(window))
                {
                    return true;
                }
            }
        }
        finally
        {
            foreach (var process in processes)
            {
                process.Dispose();
            }
        }

        return false;
    }

    /// <summary>Compares the process's image path with the shortcut target; works across 32/64-bit boundaries.</summary>
    private static bool RunsImage(int processId, string executablePath)
    {
        var handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, processId);
        if (handle == IntPtr.Zero)
        {
            return false;
        }

        try
        {
            var buffer = new StringBuilder(1024);
            var size = buffer.Capacity;
            return QueryFullProcessImageName(handle, 0, buffer, ref size)
                && string.Equals(buffer.ToString(), executablePath, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            CloseHandle(handle);
        }
    }

    /// <summary>
    /// The process's unowned, titled, captioned top-level window: a visible one if there is one, otherwise a hidden one
    /// (the tray-resident case). Tool windows and owned dialogs are skipped.
    /// </summary>
    private static IntPtr FindMainWindow(int processId)
    {
        var visible = IntPtr.Zero;
        var hidden = IntPtr.Zero;

        EnumWindows((hwnd, _) =>
        {
            GetWindowThreadProcessId(hwnd, out var windowProcessId);
            if (windowProcessId != processId || GetWindow(hwnd, GW_OWNER) != IntPtr.Zero)
            {
                return true;
            }

            var style = GetWindowLongPtr(hwnd, GWL_STYLE).ToInt64();
            var exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64();
            if ((style & WS_CAPTION) != WS_CAPTION || (exStyle & WS_EX_TOOLWINDOW) != 0 || GetWindowTextLength(hwnd) == 0)
            {
                return true;
            }

            if (IsWindowVisible(hwnd))
            {
                visible = hwnd;
                return false; // good enough; stop enumerating
            }

            if (hidden == IntPtr.Zero)
            {
                hidden = hwnd;
            }

            return true;
        }, IntPtr.Zero);

        return visible != IntPtr.Zero ? visible : hidden;
    }

    private static bool Show(IntPtr window)
    {
        if (IsIconic(window))
        {
            ShowWindow(window, SW_RESTORE);
        }
        else if (!IsWindowVisible(window))
        {
            ShowWindow(window, SW_SHOW);
        }

        // The launcher is the foreground window at this point, so it may hand the foreground on. If Windows
        // still refuses, the window is at least visible now, which beats starting a slow second instance.
        SetForegroundWindow(window);
        return true;
    }

    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr hwnd, uint command);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);

    [DllImport("user32.dll")]
    private static extern int GetWindowTextLength(IntPtr hwnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(IntPtr hwnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsIconic(IntPtr hwnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShowWindow(IntPtr hwnd, int command);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(IntPtr hwnd);

    [DllImport("kernel32.dll")]
    private static extern IntPtr OpenProcess(uint desiredAccess, [MarshalAs(UnmanagedType.Bool)] bool inheritHandle, int processId);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool QueryFullProcessImageName(IntPtr process, uint flags, StringBuilder exeName, ref int size);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);
}
