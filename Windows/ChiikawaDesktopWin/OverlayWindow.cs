using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace ChiikawaDesktopWin;

public sealed class OverlayWindow : Window
{
    private readonly SpecBundle _specBundle;
    private readonly WindowTracker _windowTracker;
    private readonly PhysicsWorld _physicsWorld;
    private readonly SpriteAssetRepository _spriteRepository;
    private readonly OverlayCanvas _canvas;

    private readonly DispatcherTimer _timer;
    private readonly Stopwatch _uptime = Stopwatch.StartNew();
    private double _lastUpdateTimestamp;

    private IntPtr _hwnd = IntPtr.Zero;
    private bool _isClickThrough = true;
    private CharacterEntity? _grabbedCharacter;
    private Forms.NotifyIcon? _trayIcon;

    public List<CharacterEntity> Characters { get; } = new();
    public bool WanderingEnabled { get; private set; } = true;
    public double CurrentScale { get; private set; } = 1.0;

    public OverlayWindow(SpecBundle specBundle)
    {
        _specBundle = specBundle;
        _windowTracker = new WindowTracker(specBundle.PhysicsAndWorld);
        _physicsWorld = new PhysicsWorld(specBundle.PhysicsAndWorld);
        _spriteRepository = new SpriteAssetRepository(specBundle.CharacterFSM, specBundle.ProjectRootDirectory);

        Title = "ChiikawaDesktop";
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;

        Left = SystemParameters.VirtualScreenLeft;
        Top = SystemParameters.VirtualScreenTop;
        Width = SystemParameters.VirtualScreenWidth;
        Height = SystemParameters.VirtualScreenHeight;

        _canvas = new OverlayCanvas(this, _spriteRepository);
        Content = _canvas;

        Loaded += OnLoaded;
        Closing += (_, _) => _trayIcon?.Dispose();

        _lastUpdateTimestamp = _uptime.Elapsed.TotalSeconds;
        _timer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromSeconds(1.0 / 30.0)
        };
        _timer.Tick += (_, _) => StepSimulation();
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        _hwnd = new WindowInteropHelper(this).Handle;
        _windowTracker.SetOwnOverlayHandle(_hwnd);

        // Configure WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW
        int exStyle = GetWindowLong(_hwnd, GWL_EXSTYLE);
        SetWindowLong(_hwnd, GWL_EXSTYLE, exStyle | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW);
        _isClickThrough = true;

        SetupSystemTray();

        var range = _specBundle.PhysicsAndWorld.CharacterDimensions.ScaleRange;
        double startupScale = UserPreferencesStore.Shared.DefaultStartupScale(range.Default);
        SetScaleForAll(startupScale);

        var fallbackChars = _specBundle.PhysicsAndWorld.PopulationLimits.InitialSpawnCharacters;
        foreach (var id in UserPreferencesStore.Shared.DefaultStartupCharacters(fallbackChars))
        {
            SpawnCharacter(id);
        }

        _timer.Start();
    }

    public bool IsCharacterActive(string id) => Characters.Any(c => c.Profile.Id == id);

    public bool SpawnCharacter(string id)
    {
        var limits = _specBundle.PhysicsAndWorld.PopulationLimits;
        if (Characters.Count >= limits.MaxConcurrentCharacters) return false;
        if (!limits.AllowDuplicateCharacters && IsCharacterActive(id)) return false;

        var profile = _specBundle.CharacterFSM.DefaultCharacters.FirstOrDefault(c => c.Id == id);
        if (profile == null) return false;

        var rng = new Random();
        double margin = 140.0;
        double startX = margin + rng.NextDouble() * Math.Max(20.0, Width - margin * 2.0);
        double startY = Height - 140.0;

        Characters.Add(new CharacterEntity(profile, _specBundle.CharacterFSM, _physicsWorld, startX, startY, CurrentScale));
        _canvas.InvalidateVisual();
        return true;
    }

    public void RemoveCharacter(string id)
    {
        AudioAssetPlayer.Shared.StopSong(id);
        Characters.RemoveAll(c => c.Profile.Id == id);
        _canvas.InvalidateVisual();
    }

    public void ToggleCharacter(string id)
    {
        if (IsCharacterActive(id)) RemoveCharacter(id);
        else SpawnCharacter(id);
    }

    public void SetScaleForAll(double scale)
    {
        var range = _specBundle.PhysicsAndWorld.CharacterDimensions.ScaleRange;
        double span = range.Max - range.Min;
        if (span > 0)
        {
            double frac = (scale - range.Min) / span;
            foreach (var detent in range.DetentFractions)
            {
                if (Math.Abs(frac - detent) <= range.DetentSnapRadiusFraction)
                {
                    scale = range.Min + detent * span;
                    break;
                }
            }
        }

        CurrentScale = Math.Clamp(scale, range.Min, range.Max);
        foreach (var c in Characters) c.ScaleFactor = CurrentScale;
        _canvas.InvalidateVisual();
    }

    private void StepSimulation()
    {
        double now = _uptime.Elapsed.TotalSeconds;
        double dt = Math.Clamp(now - _lastUpdateTimestamp, 0.001, 0.05);
        _lastUpdateTimestamp = now;

        var platforms = _windowTracker.PollPlatforms(force: false);
        foreach (var c in Characters)
        {
            c.Update(dt, platforms, WanderingEnabled);
        }

        UpdateClickThroughState();
        _canvas.InvalidateVisual();

        // Adaptive frame rate from spec/physics_and_world.json
        var coord = _specBundle.PhysicsAndWorld.CoordinateSystem;
        double targetInterval = Characters.Any(c => c.IsHighFrequencyState)
            ? 1.0 / coord.ActiveFrameRate
            : (!WanderingEnabled && Characters.All(c => c.State == CharacterStateID.IDLE)
                ? 1.0 / coord.IdleFrameRate
                : 1.0 / coord.NormalFrameRate);

        if (Math.Abs(_timer.Interval.TotalSeconds - targetInterval) > 0.004)
        {
            _timer.Interval = TimeSpan.FromSeconds(targetInterval);
        }
    }

    private Point GetMouseBottomLeftPoint()
    {
        GetCursorPos(out POINT pt);
        // Use WPF PointFromScreen on the canvas so multi-monitor offsets and per-monitor DPI match canvas mouse events 1:1
        if (PresentationSource.FromVisual(_canvas) != null)
        {
            Point localTopDown = _canvas.PointFromScreen(new Point(pt.X, pt.Y));
            return new Point(localTopDown.X, _canvas.ActualHeight > 0 ? _canvas.ActualHeight - localTopDown.Y : Height - localTopDown.Y);
        }
        double dpi = GetDpiForWindow(_hwnd) / 96.0;
        if (dpi <= 0) dpi = 1.0;
        double x = (pt.X / dpi) - Left;
        double yFromTop = (pt.Y / dpi) - Top;
        return new Point(x, Height - yFromTop);
    }

    private void UpdateClickThroughState()
    {
        if (_hwnd == IntPtr.Zero) return;

        bool shouldIgnore;
        if (_grabbedCharacter != null)
        {
            shouldIgnore = false;
        }
        else
        {
            Point mousePt = GetMouseBottomLeftPoint();
            bool hovering = Characters.Any(c => c.HitboxRect.Contains(mousePt));
            shouldIgnore = !hovering;
        }

        if (shouldIgnore != _isClickThrough)
        {
            int exStyle = GetWindowLong(_hwnd, GWL_EXSTYLE);
            if (shouldIgnore)
                SetWindowLong(_hwnd, GWL_EXSTYLE, exStyle | WS_EX_TRANSPARENT);
            else
                SetWindowLong(_hwnd, GWL_EXSTYLE, exStyle & ~WS_EX_TRANSPARENT);
            _isClickThrough = shouldIgnore;
        }
    }

    public bool HandleCanvasMouseDown(Point bottomLeftPt)
    {
        var target = Characters.AsEnumerable().Reverse().FirstOrDefault(c => c.HitboxRect.Contains(bottomLeftPt));
        if (target != null)
        {
            _grabbedCharacter = target;
            target.HandleMouseDown(bottomLeftPt);
            UpdateClickThroughState();
            return true;
        }
        return false;
    }

    public void HandleCanvasMouseMove(Point bottomLeftPt)
    {
        _grabbedCharacter?.HandleMouseDragged(bottomLeftPt, 1.0 / 60.0);
    }

    public void HandleCanvasMouseUp(Point bottomLeftPt)
    {
        if (_grabbedCharacter != null)
        {
            var target = _grabbedCharacter;
            _grabbedCharacter = null;
            target.HandleMouseUp(bottomLeftPt);
            UpdateClickThroughState();
        }
    }

    public void HandleCanvasMouseCancel()
    {
        if (_grabbedCharacter != null)
        {
            var target = _grabbedCharacter;
            _grabbedCharacter = null;
            target.HandleMouseCancel();
            UpdateClickThroughState();
        }
    }

    public void HandleCanvasRightClick(Point bottomLeftPt)
    {
        var target = Characters.AsEnumerable().Reverse().FirstOrDefault(c => c.HitboxRect.Contains(bottomLeftPt));
        if (target == null) return;
        OpenContextMenu(target);
    }

    private void SetupSystemTray()
    {
        _trayIcon = new Forms.NotifyIcon
        {
            Text = "ChiikawaDesktop",
            Icon = System.Drawing.SystemIcons.Application,
            Visible = true
        };
        _trayIcon.MouseClick += (_, args) =>
        {
            if (args.Button is Forms.MouseButtons.Left or Forms.MouseButtons.Right)
            {
                OpenContextMenu(null);
            }
        };
    }

    private void OpenContextMenu(CharacterEntity? clickedCharacter)
    {
        var menu = new ContextMenu();
        int maxCount = _specBundle.PhysicsAndWorld.PopulationLimits.MaxConcurrentCharacters;

        menu.Items.Add(new MenuItem
        {
            Header = $"🐾 현재 캐릭터: {Characters.Count} / {maxCount}명",
            IsEnabled = false
        });
        menu.Items.Add(new Separator());

        foreach (var profile in _specBundle.CharacterFSM.DefaultCharacters)
        {
            bool active = IsCharacterActive(profile.Id);
            string actionWord = active ? "휴식" : "소환";
            var item = new MenuItem
            {
                Header = $"{profile.DisplayName} {actionWord}",
                IsChecked = active,
                IsCheckable = true
            };
            string pid = profile.Id;
            item.Click += (_, _) => ToggleCharacter(pid);
            menu.Items.Add(item);
        }

        menu.Items.Add(new Separator());

        var wanderItem = new MenuItem
        {
            Header = WanderingEnabled ? "자율 돌아다니기: 켜짐" : "자율 돌아다니기: 꺼짐",
            IsChecked = WanderingEnabled
        };
        wanderItem.Click += (_, _) => WanderingEnabled = !WanderingEnabled;
        menu.Items.Add(wanderItem);

        // Scale slider with 1/4, 2/4, 3/4 magnetic detents and 5 tier labels
        var range = _specBundle.PhysicsAndWorld.CharacterDimensions.ScaleRange;
        string FormatScaleTier(double val)
        {
            double span = range.Max - range.Min;
            double frac = span > 0 ? Math.Clamp((val - range.Min) / span, 0.0, 1.0) : 0.5;
            var labels = range.TierLabels.Count == 5
                ? range.TierLabels
                : new List<string> { "아주 작게", "작게", "보통", "크게", "아주 크게" };
            int idx = Math.Clamp((int)Math.Round(frac * 4.0), 0, 4);
            return $"캐릭터 크기: {labels[idx]}";
        }

        var sliderPanel = new StackPanel { Width = 200, Margin = new Thickness(8, 4, 8, 4) };
        var sliderLabel = new TextBlock
        {
            Text = FormatScaleTier(CurrentScale),
            Margin = new Thickness(0, 0, 0, 4)
        };
        var slider = new Slider
        {
            Minimum = range.Min,
            Maximum = range.Max,
            Value = CurrentScale,
            TickPlacement = System.Windows.Controls.Primitives.TickPlacement.BottomRight,
            TickFrequency = (range.Max - range.Min) / 4.0,
            IsSnapToTickEnabled = false
        };
        slider.ValueChanged += (_, args) =>
        {
            SetScaleForAll(args.NewValue);
            if (Math.Abs(slider.Value - CurrentScale) > 0.001)
                slider.Value = CurrentScale;
            sliderLabel.Text = FormatScaleTier(CurrentScale);
        };
        sliderPanel.Children.Add(sliderLabel);
        sliderPanel.Children.Add(slider);
        menu.Items.Add(sliderPanel);

        menu.Items.Add(new Separator());

        if (clickedCharacter != null)
        {
            var restThis = new MenuItem { Header = $"{clickedCharacter.Profile.DisplayName} 휴식" };
            restThis.Click += (_, _) => RemoveCharacter(clickedCharacter.Profile.Id);
            menu.Items.Add(restThis);
        }

        // Default Startup Configuration submenu (multi-select startup characters + default scale)
        var defaultSubmenu = new MenuItem { Header = "기본 시작 설정 (캐릭터 / 크기)" };
        var fallbackChars = _specBundle.PhysicsAndWorld.PopulationLimits.InitialSpawnCharacters;
        var orderedIds = _specBundle.CharacterFSM.DefaultCharacters.Select(c => c.Id).ToList();

        defaultSubmenu.Items.Add(new MenuItem { Header = "시작 시 기본 소환 캐릭터 (복수 선택 가능)", IsEnabled = false });
        foreach (var profile in _specBundle.CharacterFSM.DefaultCharacters)
        {
            bool selected = UserPreferencesStore.Shared.IsStartupCharacterSelected(profile.Id, fallbackChars);
            var cItem = new MenuItem
            {
                Header = profile.DisplayName,
                IsChecked = selected,
                IsCheckable = true
            };
            string pid = profile.Id;
            cItem.Click += (_, _) => UserPreferencesStore.Shared.ToggleStartupCharacter(pid, fallbackChars, orderedIds);
            defaultSubmenu.Items.Add(cItem);
        }

        defaultSubmenu.Items.Add(new Separator());
        defaultSubmenu.Items.Add(new MenuItem { Header = "시작 시 기본 캐릭터 크기", IsEnabled = false });

        double savedDefaultScale = UserPreferencesStore.Shared.DefaultStartupScale(range.Default);
        var tierLabels = range.TierLabels.Count == 5
            ? range.TierLabels
            : new List<string> { "아주 작게", "작게", "보통", "크게", "아주 크게" };
        double span = range.Max - range.Min;

        for (int i = 0; i < 5; i++)
        {
            double tierScale = range.Min + (i * 0.25) * span;
            var sItem = new MenuItem
            {
                Header = tierLabels[i],
                IsChecked = Math.Abs(savedDefaultScale - tierScale) < 0.03
            };
            double targetScale = tierScale;
            sItem.Click += (_, _) =>
            {
                UserPreferencesStore.Shared.SetDefaultStartupScale(targetScale);
                SetScaleForAll(targetScale);
            };
            defaultSubmenu.Items.Add(sItem);
        }
        menu.Items.Add(defaultSubmenu);

        var loginItem = new MenuItem
        {
            Header = "시작프로그램 등록 (로그인 시 자동 실행)",
            IsChecked = LaunchAtLoginManager.Shared.IsEnabled,
            IsCheckable = true
        };
        loginItem.Click += (_, _) => LaunchAtLoginManager.Shared.Toggle();
        menu.Items.Add(loginItem);

        menu.Items.Add(new Separator());

        var quitItem = new MenuItem { Header = "종료 (Quit)" };
        quitItem.Click += (_, _) => Application.Current.Shutdown();
        menu.Items.Add(quitItem);

        menu.Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint;
        Activate();
        menu.IsOpen = true;
    }

    #region Win32 P/Invoke

    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_LAYERED = 0x00080000;
    private const int WS_EX_TRANSPARENT = 0x00000020;
    private const int WS_EX_TOOLWINDOW = 0x00000080;

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X, Y; }

    [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT lpPoint);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);

    #endregion
}

public sealed class OverlayCanvas : FrameworkElement
{
    private readonly OverlayWindow _window;
    private readonly SpriteAssetRepository _sprites;

    public OverlayCanvas(OverlayWindow window, SpriteAssetRepository sprites)
    {
        _window = window;
        _sprites = sprites;
        IsHitTestVisible = true;

        MouseLeftButtonDown += (_, e) =>
        {
            var pos = e.GetPosition(this);
            double h = ActualHeight > 0 ? ActualHeight : _window.Height;
            if (_window.HandleCanvasMouseDown(new Point(pos.X, h - pos.Y)))
            {
                CaptureMouse();
                e.Handled = true;
            }
        };
        MouseMove += (_, e) =>
        {
            var pos = e.GetPosition(this);
            double h = ActualHeight > 0 ? ActualHeight : _window.Height;
            _window.HandleCanvasMouseMove(new Point(pos.X, h - pos.Y));
        };
        MouseLeftButtonUp += (_, e) =>
        {
            var pos = e.GetPosition(this);
            double h = ActualHeight > 0 ? ActualHeight : _window.Height;
            _window.HandleCanvasMouseUp(new Point(pos.X, h - pos.Y));
            if (IsMouseCaptured) ReleaseMouseCapture();
            e.Handled = true;
        };
        LostMouseCapture += (_, _) =>
        {
            _window.HandleCanvasMouseCancel();
        };
        MouseRightButtonDown += (_, e) =>
        {
            var pos = e.GetPosition(this);
            double h = ActualHeight > 0 ? ActualHeight : _window.Height;
            _window.HandleCanvasRightClick(new Point(pos.X, h - pos.Y));
            e.Handled = true;
        };
    }

    protected override HitTestResult HitTestCore(PointHitTestParameters hitTestParameters)
    {
        // Ensure transparent regions inside the canvas still deliver mouse events whenever WS_EX_TRANSPARENT is disabled
        return new PointHitTestResult(this, hitTestParameters.HitPoint);
    }

    protected override void OnRender(DrawingContext dc)
    {
        double screenH = _window.Height;

        foreach (var c in _window.Characters)
        {
            double w = c.Width;
            double h = c.Height;
            double topDownFeetY = screenH - c.Y;

            var frame = _sprites.GetFrame(c.Profile.Id, c.State, c.StateElapsed, c.AnimPhase);
            if (frame != null)
            {
                double renderScale = c.SpriteRenderScale;
                double spriteW = w * renderScale;
                double spriteH = h * renderScale * frame.PixelHeight / Math.Max(1.0, frame.PixelWidth);
                dc.PushTransform(new TranslateTransform(c.X, topDownFeetY));
                dc.PushTransform(new ScaleTransform(c.FacingRight ? 1.0 : -1.0, 1.0));
                dc.DrawImage(frame, new Rect(-spriteW * 0.5, -spriteH, spriteW, spriteH));
                dc.Pop();
                dc.Pop();

                if (!string.IsNullOrEmpty(c.ActiveSpeechText))
                {
                    DrawSpeechBubble(dc, c.ActiveSpeechText!, c.X, topDownFeetY - spriteH - 8.0);
                }
            }
            else
            {
                // Fallback vector circle character
                var brush = (SolidColorBrush)new BrushConverter().ConvertFromString(c.Profile.PrimaryColorHex)!;
                var pen = new Pen(Brushes.DarkSlateGray, 2.5);
                dc.DrawEllipse(brush, pen, new Point(c.X, topDownFeetY - h * 0.45), w * 0.38, h * 0.35);

                if (!string.IsNullOrEmpty(c.ActiveSpeechText))
                {
                    DrawSpeechBubble(dc, c.ActiveSpeechText!, c.X, topDownFeetY - h - 8.0);
                }
            }
        }
    }

    private static void DrawSpeechBubble(DrawingContext dc, string text, double centerX, double bottomY)
    {
        var ft = new FormattedText(
            text,
            CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            new Typeface("Malgun Gothic"),
            12.0,
            Brushes.Black,
            1.25);

        double padX = 10.0, padY = 5.0;
        double bw = ft.Width + padX * 2.0;
        double bh = ft.Height + padY * 2.0;
        var rect = new Rect(centerX - bw * 0.5, bottomY - bh, bw, bh);

        dc.DrawRoundedRectangle(Brushes.White, new Pen(Brushes.DimGray, 1.5), rect, 10, 10);
        dc.DrawText(ft, new Point(rect.Left + padX, rect.Top + padY));
    }
}
