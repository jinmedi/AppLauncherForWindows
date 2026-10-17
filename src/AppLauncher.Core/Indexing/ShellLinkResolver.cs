using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text;

namespace AppLauncher.Core.Indexing;

/// <summary>Reads .lnk files through the shell's IShellLinkW COM interface.</summary>
[SupportedOSPlatform("windows")]
public sealed class ShellLinkResolver : IShellLinkResolver
{
    private const int MaxPath = 260;
    private const int InfoTipSize = 1024;
    private const uint StgmRead = 0x00000000;

    public ShellLinkTarget? Resolve(string shortcutPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(shortcutPath);

        IShellLinkW? link = null;
        try
        {
            link = (IShellLinkW)new ShellLinkCoClass();
            ((IPersistFile)link).Load(shortcutPath, StgmRead);

            var target = new StringBuilder(MaxPath);
            link.GetPath(target, target.Capacity, IntPtr.Zero, 0);
            if (target.Length == 0)
            {
                return null;
            }

            var arguments = new StringBuilder(InfoTipSize);
            link.GetArguments(arguments, arguments.Capacity);

            var workingDirectory = new StringBuilder(MaxPath);
            link.GetWorkingDirectory(workingDirectory, workingDirectory.Capacity);

            var description = new StringBuilder(InfoTipSize);
            link.GetDescription(description, description.Capacity);

            var iconPath = new StringBuilder(MaxPath);
            link.GetIconLocation(iconPath, iconPath.Capacity, out _);

            return new ShellLinkTarget(
                Environment.ExpandEnvironmentVariables(target.ToString()),
                NullIfEmpty(arguments),
                NullIfEmpty(workingDirectory) is { } wd ? Environment.ExpandEnvironmentVariables(wd) : null,
                NullIfEmpty(description),
                NullIfEmpty(iconPath) is { } icon ? Environment.ExpandEnvironmentVariables(icon) : null);
        }
        catch (COMException)
        {
            return null;
        }
        catch (InvalidCastException)
        {
            return null;
        }
        finally
        {
            if (link is not null)
            {
                Marshal.FinalReleaseComObject(link);
            }
        }
    }

    private static string? NullIfEmpty(StringBuilder builder) =>
        builder.Length == 0 ? null : builder.ToString();

    [ComImport]
    [Guid("00021401-0000-0000-C000-000000000046")]
    private class ShellLinkCoClass
    {
    }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("000214F9-0000-0000-C000-000000000046")]
    private interface IShellLinkW
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cchMaxPath, IntPtr pfd, uint fFlags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cchMaxName);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cchMaxPath);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cchMaxPath);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
        void GetHotkey(out ushort pwHotkey);
        void SetHotkey(ushort wHotkey);
        void GetShowCmd(out int piShowCmd);
        void SetShowCmd(int iShowCmd);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cchIconPath, out int piIcon);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
        void Resolve(IntPtr hwnd, uint fFlags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
    }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("0000010b-0000-0000-C000-000000000046")]
    private interface IPersistFile
    {
        void GetClassID(out Guid pClassID);
        [PreserveSig] int IsDirty();
        void Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, uint dwMode);
        void Save([MarshalAs(UnmanagedType.LPWStr)] string? pszFileName, [MarshalAs(UnmanagedType.Bool)] bool fRemember);
        void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string pszFileName);
        void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string ppszFileName);
    }
}
