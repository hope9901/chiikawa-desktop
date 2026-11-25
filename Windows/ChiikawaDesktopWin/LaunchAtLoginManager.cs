using System;
using System.Diagnostics;
using Microsoft.Win32;

namespace ChiikawaDesktopWin;

/// Manages Windows startup registration (HKCU\Software\Microsoft\Windows\CurrentVersion\Run)
/// so the user can toggle "시작프로그램 등록 (로그인 시 자동 실행)" directly from the tray/context menu.
public sealed class LaunchAtLoginManager
{
    public static LaunchAtLoginManager Shared { get; } = new();

    private const string RunRegistryPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string AppValueName = "ChiikawaDesktop";

    private LaunchAtLoginManager() { }

    public bool IsEnabled
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(RunRegistryPath, writable: false);
                return key?.GetValue(AppValueName) is string val && !string.IsNullOrWhiteSpace(val);
            }
            catch
            {
                return false;
            }
        }
    }

    public bool SetEnabled(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunRegistryPath, writable: true);
            if (key == null) return false;

            if (enabled)
            {
                string exePath = Process.GetCurrentProcess().MainModule?.FileName
                    ?? System.IO.Path.Combine(AppContext.BaseDirectory, "ChiikawaDesktop.exe");
                key.SetValue(AppValueName, $"\"{exePath}\"");
            }
            else
            {
                key.DeleteValue(AppValueName, throwOnMissingValue: false);
            }
            return true;
        }
        catch
        {
            return false;
        }
    }

    public bool Toggle()
    {
        SetEnabled(!IsEnabled);
        return IsEnabled;
    }
}
