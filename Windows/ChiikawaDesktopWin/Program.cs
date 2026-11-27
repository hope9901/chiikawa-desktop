using System;
using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Threading;

namespace ChiikawaDesktopWin;

public static class Program
{
    private const string SingleInstanceMutexName = @"Local\ChiikawaDesktop_SingleInstance_Mutex";

    [STAThread]
    public static void Main()
    {
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
            ReportFatalError(e.ExceptionObject as Exception);

        using var singleInstanceMutex = new Mutex(initiallyOwned: true, name: SingleInstanceMutexName, out bool createdNew);
        if (!createdNew)
        {
            // Another instance is already running in this Windows user session.
            return;
        }

        try
        {
            var app = new Application
            {
                ShutdownMode = ShutdownMode.OnMainWindowClose
            };
            app.DispatcherUnhandledException += OnDispatcherUnhandledException;

            var specBundle = SpecBundle.LoadDefault();
            var window = new OverlayWindow(specBundle);
            app.Run(window);
        }
        catch (Exception ex)
        {
            // Previously a startup failure (e.g. missing spec/assets next to the EXE)
            // made the process exit silently, which looked like "the app won't install/run".
            ReportFatalError(ex);
        }
        GC.KeepAlive(singleInstanceMutex);
    }

    private static void OnDispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        // Keep the desktop pet alive on non-fatal UI-thread errors; just log them.
        WriteLog(e.Exception);
        e.Handled = true;
    }

    private static string? WriteLog(Exception? ex)
    {
        try
        {
            string dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ChiikawaDesktop");
            Directory.CreateDirectory(dir);
            string logPath = Path.Combine(dir, "error.log");
            File.AppendAllText(logPath,
                $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {Environment.OSVersion} ({(Environment.Is64BitProcess ? "x64" : "x86")})"
                + Environment.NewLine + ex + Environment.NewLine + Environment.NewLine);
            return logPath;
        }
        catch
        {
            return null;
        }
    }

    private static void ReportFatalError(Exception? ex)
    {
        string? logPath = WriteLog(ex);
        try
        {
            MessageBox.Show(
                "치이카와 데스크톱을 시작하지 못했습니다.\n\n" +
                (ex?.Message ?? "알 수 없는 오류") +
                (logPath != null ? $"\n\n자세한 로그: {logPath}" : ""),
                "ChiikawaDesktop",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
        catch
        {
            // Nothing else we can do.
        }
    }
}
