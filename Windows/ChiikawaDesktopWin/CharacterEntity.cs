using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;

namespace ChiikawaDesktopWin;

public enum CharacterStateID
{
    IDLE,
    WALK,
    JUMP_STEP,
    CLIMB_WALL,
    CLIMB_REST,
    CRY_CLICK,
    DRAGGED_STRUGGLE,
    FALL,
    FALL_FROM_GRAB,
    TUMBLE
}

public sealed class CharacterEntity
{
    public Guid InstanceID { get; } = Guid.NewGuid();
    public CharacterFSMSpec.CharacterProfileSpec Profile { get; }

    private readonly CharacterFSMSpec _fsmSpec;
    private readonly PhysicsWorld _physics;
    private static readonly Random Rng = new();

    // Normalized bottom-left coordinates (X: center of feet, Y: bottom of feet)
    public double X { get; set; }
    public double Y { get; set; }
    public double Vx { get; set; }
    public double Vy { get; set; }
    public bool FacingRight { get; set; } = true;
    public double ScaleFactor { get; set; } = 1.0;

    public CharacterStateID State { get; private set; }
    public double StateElapsed { get; private set; }
    public double TargetStateDuration { get; private set; } = 2.5;
    public PlatformSegment? CurrentPlatform { get; private set; }

    // Step jump state
    private double _jumpStartX, _jumpStartY, _jumpTargetX, _jumpTargetY;
    private PlatformSegment? _jumpTargetPlatform;

    // Window edge climb state
    public int ClimbingWindowID { get; private set; }
    public bool ClimbingOnLeftEdge { get; private set; } = true;
    private double _climbDistanceSinceRest;
    private double _climbTotalHeight;
    private double _climbActionCooldown;
    private readonly Dictionary<int, double> _ignoredWindowCooldowns = new();

    // Mouse interaction
    public bool IsMousePressed { get; private set; }
    private Point _mousePressOrigin;
    private Point _lastMousePosition;
    private double _lastMouseVelocityX;

    // True while CRY_CLICK is showing the singing animation for a playing song.
    private bool _isSingingSong;

    // Speech bubble
    public string? ActiveSpeechText { get; private set; }
    private double _speechTimer;
    public double AnimPhase { get; private set; }

    public CharacterEntity(
        CharacterFSMSpec.CharacterProfileSpec profile,
        CharacterFSMSpec fsmSpec,
        PhysicsWorld physics,
        double startX,
        double startY,
        double scaleFactor = 1.0)
    {
        Profile = profile;
        _fsmSpec = fsmSpec;
        _physics = physics;
        X = startX;
        Y = startY;
        ScaleFactor = scaleFactor;
        FacingRight = Rng.NextDouble() >= 0.5;
        State = Enum.TryParse<CharacterStateID>(fsmSpec.InitialState, out var init) ? init : CharacterStateID.FALL;
        Transition(State);
    }

    public double Width => _physics.Dimensions.Width * ScaleFactor;
    public double Height => _physics.Dimensions.Height * ScaleFactor;
    public double SpriteRenderScale =>
        (State == CharacterStateID.CRY_CLICK && Profile.PlaysSongOnClick)
            ? Profile.SongSpriteScale
            : Profile.BaseSpriteScale;
    public double SpriteBoundsHeight => Height * Profile.HeightMultiplier;

    public Rect HitboxRect
    {
        get
        {
            double pad = _physics.Dimensions.HitboxPadding;
            double w = Width + pad * 2.0;
            double h = SpriteBoundsHeight + pad * 2.0;
            return new Rect(X - w * 0.5, Y - pad, w, h);
        }
    }

    public bool IsHighFrequencyState =>
        State is CharacterStateID.DRAGGED_STRUGGLE or CharacterStateID.FALL or CharacterStateID.FALL_FROM_GRAB
            or CharacterStateID.TUMBLE or CharacterStateID.CRY_CLICK or CharacterStateID.JUMP_STEP
            or CharacterStateID.CLIMB_WALL or CharacterStateID.CLIMB_REST
        || (CurrentPlatform is { IsFloor: false });

    public void Update(double dt, List<PlatformSegment> platforms, bool wanderingEnabled)
    {
        StateElapsed += dt;
        AnimPhase += dt;

        if (_speechTimer > 0)
        {
            _speechTimer -= dt;
            if (_speechTimer <= 0) ActiveSpeechText = null;
        }

        if (_climbActionCooldown > 0) _climbActionCooldown -= dt;

        if (_ignoredWindowCooldowns.Count > 0)
        {
            foreach (var key in _ignoredWindowCooldowns.Keys.ToList())
            {
                double rem = _ignoredWindowCooldowns[key] - dt;
                if (rem <= 0) _ignoredWindowCooldowns.Remove(key);
                else _ignoredWindowCooldowns[key] = rem;
            }
        }

        var timings = _fsmSpec.InteractionTimings;
        Rect usable = _physics.UsableScreenBounds;
        double halfW = Width * 0.42;
        double effectiveH = SpriteBoundsHeight;
        double minScreenX = usable.Left + halfW;
        double maxScreenX = usable.Right - halfW;
        double maxScreenY = usable.Bottom - effectiveH * 0.92;
        var activeFloorSegment = platforms.FirstOrDefault(p => p.IsFloor && X >= p.MinX && X <= p.MaxX)
            ?? platforms.FirstOrDefault(p => p.IsFloor);
        double floorY = Math.Max(0.0, activeFloorSegment?.Y ?? usable.Top);

        if (_physics.RidingRules.HardFloorClampEnabled && Y < floorY - 2.0 &&
            State is not CharacterStateID.FALL and not CharacterStateID.FALL_FROM_GRAB)
        {
            Y = floorY;
        }

        switch (State)
        {
            case CharacterStateID.IDLE:
                Vx = 0;
                Vy = 0;
                if (_physics.ResolveStandingSupport(X, Y, Width, Height, CurrentPlatform, platforms) is { } resolvedIdle)
                {
                    X = resolvedIdle.X;
                    Y = resolvedIdle.Y;
                    CurrentPlatform = resolvedIdle.Segment;
                }
                else
                {
                    X = Math.Clamp(X, minScreenX, maxScreenX);
                    Y = Math.Max(floorY, Math.Min(Y, maxScreenY));
                    CurrentPlatform = null;
                    Transition(CharacterStateID.FALL);
                    return;
                }

                if (wanderingEnabled && StateElapsed >= timings.IdleMinDurationSeconds && StateElapsed >= TargetStateDuration)
                {
                    FacingRight = Rng.NextDouble() >= 0.5;
                    Transition(CharacterStateID.WALK);
                }
                break;

            case CharacterStateID.WALK:
                if (!wanderingEnabled)
                {
                    Transition(CharacterStateID.IDLE);
                    return;
                }

                if (_physics.ResolveStandingSupport(X, Y, Width, Height, CurrentPlatform, platforms) is not { } resolvedWalk)
                {
                    X = Math.Clamp(X, minScreenX, maxScreenX);
                    Y = Math.Max(floorY, Math.Min(Y, maxScreenY));
                    CurrentPlatform = null;
                    Transition(CharacterStateID.FALL);
                    return;
                }

                X = resolvedWalk.X;
                Y = resolvedWalk.Y;
                var support = resolvedWalk.Segment;
                CurrentPlatform = support;

                if (_climbActionCooldown <= 0 &&
                    _physics.FindStepJumpTarget(X, Y, FacingRight, Width, Height, support.WindowID, platforms) is { } stepTarget &&
                    !_ignoredWindowCooldowns.ContainsKey(stepTarget.Segment.WindowID))
                {
                    if (Rng.NextDouble() < _physics.JumpAndClimb.StepJumpProbability)
                    {
                        StartStepJump(stepTarget.Segment, stepTarget.LandingX);
                        return;
                    }
                    _ignoredWindowCooldowns[stepTarget.Segment.WindowID] = _physics.JumpAndClimb.DecisionCooldownSeconds;
                }

                if (_climbActionCooldown <= 0 &&
                    _physics.FindClimbableWindowEdge(X, Y, FacingRight, Width, Height, support.WindowID, platforms) is { } climbTarget &&
                    !_ignoredWindowCooldowns.ContainsKey(climbTarget.Segment.WindowID))
                {
                    if (Rng.NextDouble() < _physics.JumpAndClimb.ClimbProbability)
                    {
                        StartWindowClimb(climbTarget.Segment, climbTarget.ClimbOnLeftEdge, climbTarget.EdgeX);
                        return;
                    }
                    _ignoredWindowCooldowns[climbTarget.Segment.WindowID] = _physics.JumpAndClimb.DecisionCooldownSeconds;
                }

                double speed = _physics.Constants.WalkSpeed;
                Vx = FacingRight ? speed : -speed;
                double nextX = X + Vx * dt;
                double footHalfW = Width * 0.30;
                double segMinX = Math.Max(minScreenX, support.MinX + footHalfW);
                double segMaxX = Math.Min(maxScreenX, support.MaxX - footHalfW);

                if (segMinX >= segMaxX)
                {
                    X = Math.Clamp(X, minScreenX, maxScreenX);
                    CurrentPlatform = null;
                    Transition(CharacterStateID.FALL);
                    return;
                }

                if (nextX <= segMinX || nextX >= segMaxX)
                {
                    if (!support.IsFloor && Rng.NextDouble() < _physics.Constants.EdgeDropProbability)
                    {
                        double dropX = FacingRight ? (support.MaxX + footHalfW + 4.0) : (support.MinX - footHalfW - 4.0);
                        X = Math.Clamp(dropX, minScreenX, maxScreenX);
                        Vx = FacingRight ? speed * 0.4 : -speed * 0.4;
                        CurrentPlatform = null;
                        Transition(CharacterStateID.FALL);
                        return;
                    }
                    FacingRight = !FacingRight;
                    X = Math.Clamp(nextX, segMinX, segMaxX);
                }
                else
                {
                    X = nextX;
                }

                if (StateElapsed >= TargetStateDuration)
                {
                    Transition(CharacterStateID.IDLE);
                }
                break;

            case CharacterStateID.JUMP_STEP:
                if (_jumpTargetPlatform == null ||
                    platforms.FirstOrDefault(p => p.WindowID == _jumpTargetPlatform.WindowID) is not { } updatedTarget)
                {
                    CurrentPlatform = null;
                    Transition(CharacterStateID.FALL);
                    return;
                }

                double dxJump = updatedTarget.RawWindowMinX - _jumpTargetPlatform.RawWindowMinX;
                _jumpTargetX += dxJump;
                _jumpTargetY = updatedTarget.Y;
                _jumpTargetPlatform = updatedTarget;

                double duration = Math.Max(0.15, _physics.JumpAndClimb.StepJumpDurationSeconds);
                double t = Math.Min(1.0, StateElapsed / duration);
                double arcOffset = Math.Sin(t * Math.PI) * _physics.JumpAndClimb.StepJumpArcPeakOffset * ScaleFactor;

                double jx = _jumpStartX + (_jumpTargetX - _jumpStartX) * t;
                double jy = _jumpStartY + (_jumpTargetY - _jumpStartY) * t + arcOffset;

                if (!_physics.IsCharacterBodyInsideScreen(jx, jy, Width, effectiveH, usable))
                {
                    X = Math.Clamp(jx, minScreenX, maxScreenX);
                    Y = Math.Max(floorY, Math.Min(jy, maxScreenY));
                    CurrentPlatform = null;
                    Transition(CharacterStateID.FALL);
                    return;
                }

                X = jx;
                Y = jy;

                if (t >= 1.0)
                {
                    X = _jumpTargetX;
                    Y = updatedTarget.Y;
                    CurrentPlatform = updatedTarget;
                    _climbActionCooldown = 0.8;
                    Transition(CharacterStateID.WALK);
                }
                break;

            case CharacterStateID.CLIMB_WALL:
                if (ClimbingWindowID == 0 ||
                    platforms.FirstOrDefault(p => p.WindowID == ClimbingWindowID) is not { } winSeg)
                {
                    X = Math.Clamp(X, minScreenX, maxScreenX);
                    Y = Math.Max(floorY, Math.Min(Y, maxScreenY));
                    CurrentPlatform = null;
                    Transition(CharacterStateID.FALL);
                    return;
                }

                double edgeX = ClimbingOnLeftEdge ? winSeg.RawWindowMinX : winSeg.RawWindowMaxX;
                if (CurrentPlatform != null && CurrentPlatform.WindowID == ClimbingWindowID)
                {
                    Y += (winSeg.Y - CurrentPlatform.Y);
                }
                CurrentPlatform = winSeg;
                FacingRight = ClimbingOnLeftEdge;

                double dy = _physics.JumpAndClimb.ClimbSpeed * dt;
                double nextClimbY = Y + dy;
                _climbDistanceSinceRest += dy;

                if (!_physics.IsCharacterBodyInsideScreen(edgeX, Math.Min(nextClimbY, winSeg.Y), Width, effectiveH, usable))
                {
                    X = Math.Clamp(edgeX, minScreenX, maxScreenX);
                    Y = Math.Max(floorY, Math.Min(Y, maxScreenY));
                    CurrentPlatform = null;
                    Transition(CharacterStateID.FALL);
                    return;
                }

                X = edgeX;
                if (nextClimbY >= winSeg.Y)
                {
                    double fh = Width * 0.32;
                    double stepInX = ClimbingOnLeftEdge
                        ? Math.Min(winSeg.MaxX - fh, winSeg.MinX + fh + 8.0)
                        : Math.Max(winSeg.MinX + fh, winSeg.MaxX - fh - 8.0);
                    X = Math.Clamp(stepInX, minScreenX, maxScreenX);
                    Y = winSeg.Y;
                    CurrentPlatform = winSeg;
                    _climbActionCooldown = 1.5;
                    ShowSpeech(SpeechFor("CLIMB_TOP", "영차! 올라왔다! ( ˶ˆᗜˆ˵ )"));
                    Transition(CharacterStateID.WALK);
                    return;
                }

                Y = nextClimbY;

                if (Profile.CanRestDuringClimb &&
                    _climbTotalHeight >= Height * _physics.JumpAndClimb.MinClimbHeightForRestRatio &&
                    _climbDistanceSinceRest >= Height * _physics.JumpAndClimb.ClimbRestSegmentDistanceRatio &&
                    (winSeg.Y - Y) > Height * 0.45)
                {
                    _climbDistanceSinceRest = 0.0;
                    Transition(CharacterStateID.CLIMB_REST);
                }
                break;

            case CharacterStateID.CLIMB_REST:
                if (ClimbingWindowID == 0 ||
                    platforms.FirstOrDefault(p => p.WindowID == ClimbingWindowID) is not { } restSeg)
                {
                    X = Math.Clamp(X, minScreenX, maxScreenX);
                    Y = Math.Max(floorY, Math.Min(Y, maxScreenY));
                    CurrentPlatform = null;
                    Transition(CharacterStateID.FALL);
                    return;
                }

                double restEdgeX = ClimbingOnLeftEdge ? restSeg.RawWindowMinX : restSeg.RawWindowMaxX;
                if (CurrentPlatform != null && CurrentPlatform.WindowID == ClimbingWindowID)
                {
                    Y += (restSeg.Y - CurrentPlatform.Y);
                }
                CurrentPlatform = restSeg;
                X = restEdgeX;

                if (!_physics.IsCharacterBodyInsideScreen(X, Y, Width, effectiveH, usable) || Y > restSeg.Y)
                {
                    X = Math.Clamp(X, minScreenX, maxScreenX);
                    Y = Math.Max(floorY, Math.Min(Y, maxScreenY));
                    CurrentPlatform = null;
                    Transition(CharacterStateID.FALL);
                    return;
                }

                if (StateElapsed >= TargetStateDuration)
                {
                    Transition(CharacterStateID.CLIMB_WALL);
                }
                break;

            case CharacterStateID.CRY_CLICK:
                Vx = 0;
                Vy = 0;
                if (IsMousePressed && StateElapsed >= timings.HoldThresholdSeconds)
                {
                    Transition(CharacterStateID.DRAGGED_STRUGGLE);
                    return;
                }

                if (!IsMousePressed)
                {
                    if (_physics.ResolveStandingSupport(X, Y, Width, Height, CurrentPlatform, platforms) is { } resCry)
                    {
                        X = resCry.X;
                        Y = resCry.Y;
                        CurrentPlatform = resCry.Segment;
                    }
                    else
                    {
                        X = Math.Clamp(X, minScreenX, maxScreenX);
                        Y = Math.Max(floorY, Math.Min(Y, maxScreenY));
                        CurrentPlatform = null;
                        Transition(CharacterStateID.FALL);
                        return;
                    }

                    // Singing ends exactly when the audio ends (MediaEnded / end of
                    // position / playback failure), not after a guessed duration.
                    bool songFinished = _isSingingSong && !AudioAssetPlayer.Shared.IsSongActive(Profile.Id);
                    if (songFinished || StateElapsed >= TargetStateDuration)
                    {
                        AudioAssetPlayer.Shared.StopSong(Profile.Id);
                        Transition(CharacterStateID.IDLE);
                    }
                }
                break;

            case CharacterStateID.DRAGGED_STRUGGLE:
                CurrentPlatform = null;
                ClimbingWindowID = 0;
                double anchorOffset = _physics.Dimensions.GrabAnchorOffsetY * ScaleFactor;
                X = Math.Clamp(_lastMousePosition.X, minScreenX, maxScreenX);
                Y = Math.Clamp(_lastMousePosition.Y - anchorOffset, 0.0, maxScreenY);
                break;

            case CharacterStateID.FALL:
            case CharacterStateID.FALL_FROM_GRAB:
                double prevY = Y;
                Vy = Math.Max(_physics.Constants.TerminalVelocity, Vy + _physics.Constants.Gravity * dt);
                Vx *= _physics.Constants.AirResistance;

                double nextFallX = Math.Clamp(X + Vx * dt, minScreenX, maxScreenX);
                double nextFallY = Math.Min(Y + Vy * dt, maxScreenY);

                if (_physics.FindLandingPlatform(nextFallX, Math.Max(prevY, floorY), nextFallY, Width, Height, platforms) is { } landed)
                {
                    X = nextFallX;
                    Y = Math.Max(floorY, landed.Y);
                    Vx = 0;
                    Vy = 0;
                    CurrentPlatform = landed;
                    Transition(CharacterStateID.TUMBLE);
                    return;
                }

                if (nextFallY <= floorY)
                {
                    X = nextFallX;
                    Y = floorY;
                    Vx = 0;
                    Vy = 0;
                    CurrentPlatform = activeFloorSegment;
                    Transition(CharacterStateID.TUMBLE);
                    return;
                }

                X = nextFallX;
                Y = nextFallY;
                break;

            case CharacterStateID.TUMBLE:
                Vx = 0;
                Vy = 0;
                if (_physics.ResolveStandingSupport(X, Y, Width, Height, CurrentPlatform, platforms) is { } resTumble)
                {
                    X = resTumble.X;
                    Y = resTumble.Y;
                    CurrentPlatform = resTumble.Segment;
                }
                else
                {
                    X = Math.Clamp(X, minScreenX, maxScreenX);
                    Y = Math.Max(floorY, Math.Min(Y, maxScreenY));
                    CurrentPlatform = null;
                    Transition(CharacterStateID.FALL);
                    return;
                }

                if (StateElapsed >= TargetStateDuration)
                {
                    Transition(CharacterStateID.IDLE);
                }
                break;
        }
    }

    private string SpeechFor(string key, string fallback) =>
        Profile.StateSpeeches != null && Profile.StateSpeeches.TryGetValue(key, out var text) ? text : fallback;

    private void StartStepJump(PlatformSegment segment, double landingX)
    {
        _jumpStartX = X;
        _jumpStartY = Y;
        _jumpTargetX = landingX;
        _jumpTargetY = segment.Y;
        _jumpTargetPlatform = segment;
        FacingRight = landingX >= X;
        ShowSpeech(SpeechFor("JUMP_STEP", "폴짝! ♪"));
        Transition(CharacterStateID.JUMP_STEP);
    }

    private void StartWindowClimb(PlatformSegment target, bool onLeftEdge, double edgeX)
    {
        ClimbingWindowID = target.WindowID;
        ClimbingOnLeftEdge = onLeftEdge;
        _climbDistanceSinceRest = 0.0;
        _climbTotalHeight = Math.Max(0.0, target.Y - Y);
        CurrentPlatform = target;
        X = edgeX;
        FacingRight = onLeftEdge;
        ShowSpeech(SpeechFor("CLIMB_WALL", "영차.. 영차..!"));
        Transition(CharacterStateID.CLIMB_WALL);
    }

    public void HandleMouseDown(Point point)
    {
        IsMousePressed = true;
        _mousePressOrigin = point;
        _lastMousePosition = point;
        _lastMouseVelocityX = 0.0;

        if (State is CharacterStateID.FALL or CharacterStateID.FALL_FROM_GRAB or CharacterStateID.JUMP_STEP
            or CharacterStateID.CLIMB_WALL or CharacterStateID.CLIMB_REST)
        {
            Transition(CharacterStateID.DRAGGED_STRUGGLE);
        }
        else
        {
            Transition(CharacterStateID.CRY_CLICK);
        }
    }

    public void HandleMouseDragged(Point point, double dt)
    {
        if (!IsMousePressed) return;
        double dx = point.X - _lastMousePosition.X;
        if (dt > 0.001)
        {
            _lastMouseVelocityX = Math.Clamp(dx / dt * 0.35, -350.0, 350.0);
        }
        if (Math.Abs(dx) > 1.5)
        {
            FacingRight = dx > 0;
        }
        _lastMousePosition = point;

        double dist = double.Hypot(point.X - _mousePressOrigin.X, point.Y - _mousePressOrigin.Y);
        if (State == CharacterStateID.CRY_CLICK && dist > 5.0)
        {
            Transition(CharacterStateID.DRAGGED_STRUGGLE);
        }
    }

    public void HandleMouseCancel()
    {
        if (!IsMousePressed) return;
        IsMousePressed = false;

        if (State == CharacterStateID.DRAGGED_STRUGGLE)
        {
            Vx = 0.0;
            Vy = -60.0;
            Transition(CharacterStateID.FALL_FROM_GRAB);
        }
        else if (State == CharacterStateID.CRY_CLICK)
        {
            // Cancelled capture: do NOT trigger single-click song/cry; return cleanly to IDLE
            Transition(CharacterStateID.IDLE);
        }
    }

    public void HandleMouseUp(Point point)
    {
        if (!IsMousePressed) return;
        IsMousePressed = false;
        _lastMousePosition = point;

        if (State == CharacterStateID.DRAGGED_STRUGGLE)
        {
            Vx = _lastMouseVelocityX;
            Vy = -60.0;
            Transition(CharacterStateID.FALL_FROM_GRAB);
        }
        else if (State == CharacterStateID.CRY_CLICK && Profile.PlaysSongOnClick)
        {
            if (AudioAssetPlayer.Shared.ToggleOrPlayClickSong(
                Profile,
                _fsmSpec.InteractionTimings.AllowConcurrentSinging) is double songDuration)
            {
                if (songDuration < 0)
                {
                    Transition(CharacterStateID.IDLE);
                    string busySpeech = SpeechFor("SONG_BUSY", "");
                    if (!string.IsNullOrEmpty(busySpeech))
                    {
                        ShowSpeech(busySpeech);
                    }
                    else
                    {
                        ActiveSpeechText = null;
                        _speechTimer = 0;
                    }
                }
                else
                {
                    _isSingingSong = true;
                    TargetStateDuration = StateElapsed + songDuration;
                    ShowSpeech(Profile.ClickSpeech);
                }
            }
            else
            {
                Transition(CharacterStateID.IDLE);
            }
        }
    }

    public void ShowSpeech(string text)
    {
        ActiveSpeechText = text;
        _speechTimer = _fsmSpec.InteractionTimings.SpeechBubbleDurationSeconds;
    }

    public void Transition(CharacterStateID newState)
    {
        State = newState;
        StateElapsed = 0.0;
        _isSingingSong = false;

        // The song belongs to the singing (CRY_CLICK) pose only. Leaving it for any
        // other state stops the audio so sound and animation never get out of sync.
        // (Pressing on a singing character re-enters CRY_CLICK; releasing toggles it off.)
        if (newState != CharacterStateID.CRY_CLICK)
        {
            AudioAssetPlayer.Shared.StopSong(Profile.Id);
        }
        var timings = _fsmSpec.InteractionTimings;

        switch (newState)
        {
            case CharacterStateID.IDLE:
                TargetStateDuration = timings.IdleMinDurationSeconds +
                    Rng.NextDouble() * (timings.IdleMaxDurationSeconds - timings.IdleMinDurationSeconds);
                if (Rng.NextDouble() < 0.28 && Profile.Catchphrases.Count > 0)
                {
                    ShowSpeech(Profile.Catchphrases[Rng.Next(Profile.Catchphrases.Count)]);
                }
                break;
            case CharacterStateID.WALK:
                TargetStateDuration = timings.WalkMinDurationSeconds +
                    Rng.NextDouble() * (timings.WalkMaxDurationSeconds - timings.WalkMinDurationSeconds);
                break;
            case CharacterStateID.JUMP_STEP:
                TargetStateDuration = _physics.JumpAndClimb.StepJumpDurationSeconds;
                break;
            case CharacterStateID.CLIMB_REST:
                TargetStateDuration = _physics.JumpAndClimb.ClimbRestDurationSeconds;
                ShowSpeech(SpeechFor("CLIMB_REST", "헉헉.. 잠깐만 쉬자.. 💦"));
                break;
            case CharacterStateID.CRY_CLICK:
                TargetStateDuration = timings.ClickCryDurationSeconds;
                ShowSpeech(Profile.ClickSpeech);
                break;
            case CharacterStateID.DRAGGED_STRUGGLE:
                AudioAssetPlayer.Shared.StopSong(Profile.Id);
                ShowSpeech(SpeechFor("DRAGGED_STRUGGLE", "으아아앙!! 놔줘~!! 💦"));
                break;
            case CharacterStateID.FALL:
                ClimbingWindowID = 0;
                break;
            case CharacterStateID.FALL_FROM_GRAB:
                ClimbingWindowID = 0;
                AudioAssetPlayer.Shared.StopSong(Profile.Id);
                ShowSpeech(SpeechFor("FALL_FROM_GRAB", "와아아앗~!!"));
                break;
            case CharacterStateID.TUMBLE:
                TargetStateDuration = Profile.TumbleDurationSeconds;
                ShowSpeech(SpeechFor("TUMBLE", "철푸덕..! @~@"));
                break;
        }
    }
}
