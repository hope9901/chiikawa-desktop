using System;
using System.Windows;

namespace ChiikawaDesktopWin;

public static class Program
{
    [STAThread]
    public static void Main()
    {
        var app = new Application();
        var specBundle = SpecBundle.LoadDefault();
        var window = new OverlayWindow(specBundle);
        app.Run(window);
    }
}
