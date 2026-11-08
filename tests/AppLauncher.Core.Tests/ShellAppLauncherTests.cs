using AppLauncher.Core.Models;
using AppLauncher.Core.Services;

namespace AppLauncher.Core.Tests;

public class ShellAppLauncherTests
{
    private const string Target = @"C:\does-not-exist\App.exe";

    private static readonly AppEntry App = new()
    {
        Id = "test:app",
        Name = "App",
        LaunchPath = @"C:\does-not-exist\App.lnk",
        TargetPath = Target,
    };

    private static readonly AppEntry Folder = new()
    {
        Id = "folder:x",
        Name = "X",
        LaunchPath = @"C:\does-not-exist\X",
        TargetPath = @"C:\does-not-exist\X",
        Source = AppSource.Folder,
    };

    [Fact]
    public void Launch_ActivatesTheRunningApp_InsteadOfStartingIt()
    {
        var activator = new FakeActivator(result: true);

        new ShellAppLauncher(activator).Launch(App); // would throw if it tried to start the missing .lnk

        Assert.Equal([Target], activator.Asked);
    }

    [Fact]
    public void Launch_FallsBackToStarting_WhenNothingIsRunning()
    {
        var activator = new FakeActivator(result: false);

        Assert.ThrowsAny<Exception>(() => new ShellAppLauncher(activator).Launch(App));

        Assert.Equal([Target], activator.Asked);
    }

    [Fact]
    public void Launch_NeverActivatesFolders_OrWithoutAnActivator()
    {
        var activator = new FakeActivator(result: true);

        Assert.ThrowsAny<Exception>(() => new ShellAppLauncher(activator).Launch(Folder));
        Assert.ThrowsAny<Exception>(() => new ShellAppLauncher(null).Launch(App));

        Assert.Empty(activator.Asked);
    }

    private sealed class FakeActivator(bool result) : IRunningAppActivator
    {
        public List<string> Asked { get; } = [];

        public bool TryActivate(string executablePath)
        {
            Asked.Add(executablePath);
            return result;
        }
    }
}
