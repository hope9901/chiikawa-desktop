using System;
using System.Threading;
using System.Windows;

namespace ChiikawaDesktopWin;

public static class Program
{
    private const string SingleInstanceMutexName = @"Local\ChiikawaDesktop_SingleInstance_Mutex";

    [STAThread]
    public static void Main()
    {
        using var singleInstanceMutex = new Mutex(initiallyOwned: true, name: SingleInstanceMutexName, out bool createdNew);
        if (!createdNew)
        {
            // Another instance is already running in this Windows user session.
            return;
        }

        var app = new Application();
        var specBundle = SpecBundle.LoadDefault();
        var window = new OverlayWindow(specBundle);
        app.Run(window);
        GC.KeepAlive(singleInstanceMutex);
    }
}
