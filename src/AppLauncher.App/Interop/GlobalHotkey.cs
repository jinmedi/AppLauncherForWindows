using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Input;
using System.Windows.Interop;
using AppLauncher.Core.Models;

namespace AppLauncher.App.Interop;

/// <summary>
/// Registers a system-wide hotkey against a WPF window handle and raises <see cref="Pressed"/>
/// on the UI thread whenever it fires. Dispose to unregister.
/// </summary>
public sealed class GlobalHotkey : IDisposable
{
    private static int _nextId = 0x4A00;

    private readonly HwndSource _source;
    private readonly int _id;
    private bool _registered;

    public GlobalHotkey(HwndSource source, HotkeySpec spec)
    {
        ArgumentNullException.ThrowIfNull(source);
        ArgumentNullException.ThrowIfNull(spec);

        if (!TryGetVirtualKey(spec.Key, out var virtualKey))
        {
            throw new ArgumentException($"Unknown key name '{spec.Key}'.", nameof(spec));
        }

        _source = source;
        _id = Interlocked.Increment(ref _nextId);
        Spec = spec;

        _source.AddHook(WndProc);

        var modifiers = (uint)spec.Modifiers | NativeMethods.MOD_NOREPEAT;
        _registered = NativeMethods.RegisterHotKey(_source.Handle, _id, modifiers, virtualKey);
        if (!_registered)
        {
            var error = Marshal.GetLastWin32Error();
            _source.RemoveHook(WndProc);
            throw new Win32Exception(error, $"RegisterHotKey failed for {spec} (Win32 error {error}).");
        }
    }

    public HotkeySpec Spec { get; }

    public event EventHandler? Pressed;

    public static bool TryGetVirtualKey(string keyName, out uint virtualKey)
    {
        virtualKey = 0;
        if (!Enum.TryParse<Key>(keyName, ignoreCase: true, out var key) || key == Key.None)
        {
            return false;
        }

        virtualKey = (uint)KeyInterop.VirtualKeyFromKey(key);
        return virtualKey != 0;
    }

    public void Dispose()
    {
        if (_registered)
        {
            NativeMethods.UnregisterHotKey(_source.Handle, _id);
            _registered = false;
        }

        _source.RemoveHook(WndProc);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == NativeMethods.WM_HOTKEY && wParam.ToInt32() == _id)
        {
            Pressed?.Invoke(this, EventArgs.Empty);
            handled = true;
        }

        return IntPtr.Zero;
    }
}
