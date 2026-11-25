using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;

namespace ChiikawaDesktopWin;

public sealed record PlatformSegment(
    string Id,
    int WindowID,
    string OwnerName,
    double RawWindowMinX,
    double RawWindowMaxX,
    double WindowBottomY,
    double MinX,
    double MaxX,
    double Y,
    bool IsFloor
)
{
    public double Width => MaxX - MinX;
}

/// Queries Windows OS windows via Win32 EnumWindows + DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)
/// and converts coordinates into the normalized bottom-left origin defined in spec/physics_and_world.json.
public sealed class WindowTracker
{
    private readonly PhysicsAndWorldSpec.WindowDetectionRulesSpec _rules;
    private readonly double _pollIntervalSeconds;
    private readonly Stopwatch _stopwatch = Stopwatch.StartNew();
    private double _lastPollTime = -10.0;
    private IntPtr _ownOverlayHwnd = IntPtr.Zero;

    public List<PlatformSegment> CachedPlatforms { get; private set; } = new();

    public WindowTracker(PhysicsAndWorldSpec spec)
    {
        _rules = spec.WindowDetectionRules;
        _pollIntervalSeconds = spec.CoordinateSystem.WindowPollIntervalSeconds;
        PollPlatforms(force: true);
    }

    public void SetOwnOverlayHandle(IntPtr hwnd) => _ownOverlayHwnd = hwnd;

    public List<PlatformSegment> PollPlatforms(bool force = false)
    {
        double now = _stopwatch.Elapsed.TotalSeconds;
        if (!force && (now - _lastPollTime) < _pollIntervalSeconds && CachedPlatforms.Count > 0)
        {
            return CachedPlatforms;
        }
        _lastPollTime = now;

        double screenWidth = SystemParameters.PrimaryScreenWidth;
        double screenHeight = SystemParameters.PrimaryScreenHeight;
        Rect workArea = SystemParameters.WorkArea; // Excludes Windows Taskbar

        // Convert top-down WorkArea to bottom-up coordinates (0 = bottom of primary screen)
        double floorY = Math.Max(0.0, screenHeight - workArea.Bottom);
        double floorMinX = Math.Max(0.0, workArea.Left);
        double floorMaxX = Math.Min(screenWidth, workArea.Right);

        var segments = new List<PlatformSegment>
        {
            new PlatformSegment(
                Id: "floor",
                WindowID: 0,
                OwnerName: "Desktop Floor",
                RawWindowMinX: floorMinX,
                RawWindowMaxX: floorMaxX,
                WindowBottomY: floorY,
                MinX: floorMinX,
                MaxX: floorMaxX,
                Y: floorY,
                IsFloor: true
            )
        };

        var occludingRects = new List<Rect>();

        EnumWindows((hwnd, _) =>
        {
            if (hwnd == _ownOverlayHwnd || !IsWindowVisible(hwnd) || IsIconic(hwnd))
                return true;

            // Skip cloaked UWP / background shell windows
            if (DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, out int cloaked, sizeof(int)) == 0 && cloaked != 0)
                return true;

            int exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
            if ((exStyle & WS_EX_TOOLWINDOW) != 0)
                return true;

            string title = GetWindowTitle(hwnd);
            if (string.IsNullOrWhiteSpace(title) || title == "Program Manager")
                return true;

            foreach (var ignored in _rules.IgnoredOwnerNames)
            {
                if (title.Contains(ignored, StringComparison.OrdinalIgnoreCase))
                    return true;
            }

            if (DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, out RECT rawRect, Marshal.SizeOf<RECT>()) != 0)
            {
                if (!GetWindowRect(hwnd, out rawRect))
                    return true;
            }

            // Convert physical pixels to WPF logical points if DPI scaled
            double dpiScale = GetDpiForWindow(hwnd) / 96.0;
            if (dpiScale <= 0) dpiScale = 1.0;

            double winLeft = rawRect.Left / dpiScale;
            double winTop = rawRect.Top / dpiScale;
            double winRight = rawRect.Right / dpiScale;
            double winBottom = rawRect.Bottom / dpiScale;
            double winW = winRight - winLeft;
            double winH = winBottom - winTop;

            if (winW < _rules.MinWindowWidth || winH < _rules.MinWindowHeight)
                return true;

            // Exclude windows moved completely onto secondary monitors
            if (winRight <= 0 || winLeft >= screenWidth || winBottom <= 0 || winTop >= screenHeight)
                return true;

            // Convert top-left origin to bottom-left origin
            double topEdgeY = screenHeight - winTop;
            double bottomEdgeY = screenHeight - winBottom;
            double minX = Math.Max(floorMinX, winLeft);
            double maxX = Math.Min(floorMaxX, winRight);

            if (maxX - minX < 48.0)
                return true;

            if (winTop >= _rules.MinTopClearanceFromScreenTop && topEdgeY >= floorY + 16.0 && topEdgeY <= (screenHeight - workArea.Top))
            {
                int winId = hwnd.ToInt32();
                var baseSeg = new PlatformSegment(
                    Id: $"win_{winId}",
                    WindowID: winId,
                    OwnerName: title,
                    RawWindowMinX: winLeft,
                    RawWindowMaxX: winRight,
                    WindowBottomY: Math.Max(floorY, bottomEdgeY),
                    MinX: minX,
                    MaxX: maxX,
                    Y: topEdgeY,
                    IsFloor: false
                );

                if (_rules.OccludeLowerWindows)
                {
                    segments.AddRange(SliceSegment(baseSeg, occludingRects));
                }
                else
                {
                    segments.Add(baseSeg);
                }
            }

            occludingRects.Add(new Rect(minX, Math.Min(bottomEdgeY, topEdgeY), maxX - minX, Math.Max(1.0, topEdgeY - bottomEdgeY)));
            return true;
        }, IntPtr.Zero);

        CachedPlatforms = segments;
        return segments;
    }

    private static List<PlatformSegment> SliceSegment(PlatformSegment segment, List<Rect> occluders)
    {
        var intervals = new List<(double A, double B)> { (segment.MinX, segment.MaxX) };

        foreach (var rect in occluders)
        {
            if (segment.Y >= rect.Top - 2.0 && segment.Y <= rect.Bottom + 2.0)
            {
                double occMinX = rect.Left;
                double occMaxX = rect.Right;
                var next = new List<(double A, double B)>();

                foreach (var (a, b) in intervals)
                {
                    if (occMaxX <= a || occMinX >= b)
                    {
                        next.Add((a, b));
                    }
                    else
                    {
                        if (occMinX > a) next.Add((a, occMinX));
                        if (occMaxX < b) next.Add((occMaxX, b));
                    }
                }
                intervals = next;
                if (intervals.Count == 0) break;
            }
        }

        var result = new List<PlatformSegment>();
        for (int i = 0; i < intervals.Count; i++)
        {
            double width = intervals[i].B - intervals[i].A;
            if (width < 48.0) continue;
            result.Add(segment with
            {
                Id = i == 0 ? segment.Id : $"{segment.Id}_{i}",
                MinX = intervals[i].A,
                MaxX = intervals[i].B
            });
        }
        return result;
    }

    private static string GetWindowTitle(IntPtr hwnd)
    {
        int len = GetWindowTextLength(hwnd);
        if (len <= 0) return "";
        var sb = new StringBuilder(len + 1);
        GetWindowText(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }

    #region Win32 P/Invoke

    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
    private const int DWMWA_CLOAKED = 14;

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out int pvAttribute, int cbAttribute);

    #endregion
}
