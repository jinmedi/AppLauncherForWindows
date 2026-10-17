using System.Runtime.InteropServices;

namespace AppLauncher.App.Interop;

internal static class NativeMethods
{
    public const int WM_HOTKEY = 0x0312;

    /// <summary>Suppresses auto-repeat while the hotkey is held down (Windows 7+).</summary>
    public const uint MOD_NOREPEAT = 0x4000;

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
