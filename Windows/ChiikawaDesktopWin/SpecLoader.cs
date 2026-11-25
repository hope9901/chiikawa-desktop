using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ChiikawaDesktopWin;

public sealed class ArchitectureSpec
{
    [JsonPropertyName("schemaVersion")] public string SchemaVersion { get; set; } = "";
    [JsonPropertyName("projectName")] public string ProjectName { get; set; } = "";
    [JsonPropertyName("resourceOptimizationPolicy")] public ResourceOptimizationPolicySpec ResourceOptimizationPolicy { get; set; } = new();

    public sealed class ResourceOptimizationPolicySpec
    {
        [JsonPropertyName("activeFrameRate")] public int ActiveFrameRate { get; set; } = 60;
        [JsonPropertyName("normalFrameRate")] public int NormalFrameRate { get; set; } = 30;
        [JsonPropertyName("idleFrameRate")] public int IdleFrameRate { get; set; } = 15;
        [JsonPropertyName("windowPollIntervalSeconds")] public double WindowPollIntervalSeconds { get; set; } = 0.08;
        [JsonPropertyName("useDirtyRectInvalidation")] public bool UseDirtyRectInvalidation { get; set; } = true;
        [JsonPropertyName("sleepOnScreenLock")] public bool SleepOnScreenLock { get; set; } = true;
        [JsonPropertyName("maxConcurrentCharacters")] public int MaxConcurrentCharacters { get; set; } = 4;
        [JsonPropertyName("allowDuplicateCharacters")] public bool AllowDuplicateCharacters { get; set; } = false;
    }
}

public sealed class PhysicsAndWorldSpec
{
    [JsonPropertyName("schemaVersion")] public string SchemaVersion { get; set; } = "";
    [JsonPropertyName("coordinateSystem")] public CoordinateSystemSpec CoordinateSystem { get; set; } = new();
    [JsonPropertyName("populationLimits")] public PopulationLimitsSpec PopulationLimits { get; set; } = new();
    [JsonPropertyName("physicsConstants")] public PhysicsConstantsSpec PhysicsConstants { get; set; } = new();
    [JsonPropertyName("jumpAndClimbRules")] public JumpAndClimbRulesSpec JumpAndClimbRules { get; set; } = new();
    [JsonPropertyName("windowRidingRules")] public WindowRidingRulesSpec WindowRidingRules { get; set; } = new();
    [JsonPropertyName("characterDimensions")] public CharacterDimensionsSpec CharacterDimensions { get; set; } = new();
    [JsonPropertyName("windowDetectionRules")] public WindowDetectionRulesSpec WindowDetectionRules { get; set; } = new();

    public sealed class CoordinateSystemSpec
    {
        [JsonPropertyName("origin")] public string Origin { get; set; } = "bottom-left";
        [JsonPropertyName("activeFrameRate")] public int ActiveFrameRate { get; set; } = 60;
        [JsonPropertyName("normalFrameRate")] public int NormalFrameRate { get; set; } = 30;
        [JsonPropertyName("idleFrameRate")] public int IdleFrameRate { get; set; } = 15;
        [JsonPropertyName("windowPollIntervalSeconds")] public double WindowPollIntervalSeconds { get; set; } = 0.08;
    }

    public sealed class PopulationLimitsSpec
    {
        [JsonPropertyName("maxConcurrentCharacters")] public int MaxConcurrentCharacters { get; set; } = 4;
        [JsonPropertyName("allowDuplicateCharacters")] public bool AllowDuplicateCharacters { get; set; } = false;
        [JsonPropertyName("initialSpawnCharacters")] public List<string> InitialSpawnCharacters { get; set; } = new();
    }

    public sealed class PhysicsConstantsSpec
    {
        [JsonPropertyName("gravity")] public double Gravity { get; set; } = -1450.0;
        [JsonPropertyName("terminalVelocity")] public double TerminalVelocity { get; set; } = -1200.0;
        [JsonPropertyName("airResistance")] public double AirResistance { get; set; } = 0.99;
        [JsonPropertyName("groundFriction")] public double GroundFriction { get; set; } = 0.85;
        [JsonPropertyName("walkSpeed")] public double WalkSpeed { get; set; } = 62.0;
        [JsonPropertyName("landingSnapTolerance")] public double LandingSnapTolerance { get; set; } = 16.0;
        [JsonPropertyName("windowTrackingMaxSnapDeltaY")] public double WindowTrackingMaxSnapDeltaY { get; set; } = 240.0;
        [JsonPropertyName("edgeDropProbability")] public double EdgeDropProbability { get; set; } = 0.2;
        [JsonPropertyName("bounceRestitution")] public double BounceRestitution { get; set; } = 0.15;
    }

    public sealed class JumpAndClimbRulesSpec
    {
        [JsonPropertyName("enableStepJump")] public bool EnableStepJump { get; set; } = true;
        [JsonPropertyName("maxStepJumpHeightRatio")] public double MaxStepJumpHeightRatio { get; set; } = 0.55;
        [JsonPropertyName("minStepJumpHeightPoints")] public double MinStepJumpHeightPoints { get; set; } = 8.0;
        [JsonPropertyName("stepJumpHorizontalReach")] public double StepJumpHorizontalReach { get; set; } = 36.0;
        [JsonPropertyName("stepJumpDurationSeconds")] public double StepJumpDurationSeconds { get; set; } = 0.38;
        [JsonPropertyName("stepJumpArcPeakOffset")] public double StepJumpArcPeakOffset { get; set; } = 22.0;
        [JsonPropertyName("stepJumpProbability")] public double StepJumpProbability { get; set; } = 0.45;
        [JsonPropertyName("enableWindowEdgeClimb")] public bool EnableWindowEdgeClimb { get; set; } = true;
        [JsonPropertyName("climbTriggerDistanceX")] public double ClimbTriggerDistanceX { get; set; } = 22.0;
        [JsonPropertyName("climbProbability")] public double ClimbProbability { get; set; } = 0.38;
        [JsonPropertyName("decisionCooldownSeconds")] public double DecisionCooldownSeconds { get; set; } = 5.0;
        [JsonPropertyName("climbSpeed")] public double ClimbSpeed { get; set; } = 54.0;
        [JsonPropertyName("minClimbHeightForRestRatio")] public double MinClimbHeightForRestRatio { get; set; } = 1.6;
        [JsonPropertyName("climbRestSegmentDistanceRatio")] public double ClimbRestSegmentDistanceRatio { get; set; } = 1.35;
        [JsonPropertyName("climbRestDurationSeconds")] public double ClimbRestDurationSeconds { get; set; } = 1.25;
    }

    public sealed class WindowRidingRulesSpec
    {
        [JsonPropertyName("followMovingWindow")] public bool FollowMovingWindow { get; set; } = true;
        [JsonPropertyName("freeFallWhenOutOfScreenBounds")] public bool FreeFallWhenOutOfScreenBounds { get; set; } = true;
        [JsonPropertyName("freeFallWhenCharacterExceedsWindowEdge")] public bool FreeFallWhenCharacterExceedsWindowEdge { get; set; } = true;
        [JsonPropertyName("requireFullCharacterBodyInsideScreen")] public bool RequireFullCharacterBodyInsideScreen { get; set; } = true;
        [JsonPropertyName("pinToPrimaryScreenInMultiMonitor")] public bool PinToPrimaryScreenInMultiMonitor { get; set; } = true;
        [JsonPropertyName("hardFloorClampEnabled")] public bool HardFloorClampEnabled { get; set; } = true;
    }

    public sealed class CharacterDimensionsSpec
    {
        [JsonPropertyName("width")] public double Width { get; set; } = 84.0;
        [JsonPropertyName("height")] public double Height { get; set; } = 84.0;
        [JsonPropertyName("hitboxPadding")] public double HitboxPadding { get; set; } = 6.0;
        [JsonPropertyName("grabAnchorOffsetY")] public double GrabAnchorOffsetY { get; set; } = 56.0;
        [JsonPropertyName("dirtyRectMargin")] public double DirtyRectMargin { get; set; } = 48.0;
        [JsonPropertyName("scaleRange")] public ScaleRangeSpec ScaleRange { get; set; } = new();

        public sealed class ScaleRangeSpec
        {
            [JsonPropertyName("min")] public double Min { get; set; } = 0.50;
            [JsonPropertyName("default")] public double Default { get; set; } = 1.00;
            [JsonPropertyName("max")] public double Max { get; set; } = 1.35;
            [JsonPropertyName("detentFractions")] public List<double> DetentFractions { get; set; } = new() { 0.25, 0.50, 0.75 };
            [JsonPropertyName("detentSnapRadiusFraction")] public double DetentSnapRadiusFraction { get; set; } = 0.045;
            [JsonPropertyName("numberOfTickMarks")] public int NumberOfTickMarks { get; set; } = 5;
        }
    }

    public sealed class WindowDetectionRulesSpec
    {
        [JsonPropertyName("minWindowWidth")] public double MinWindowWidth { get; set; } = 140.0;
        [JsonPropertyName("minWindowHeight")] public double MinWindowHeight { get; set; } = 90.0;
        [JsonPropertyName("minTopClearanceFromScreenTop")] public double MinTopClearanceFromScreenTop { get; set; } = 24.0;
        [JsonPropertyName("ignoredOwnerNames")] public List<string> IgnoredOwnerNames { get; set; } = new();
        [JsonPropertyName("occludeLowerWindows")] public bool OccludeLowerWindows { get; set; } = true;
    }
}

public sealed class CharacterFSMSpec
{
    [JsonPropertyName("schemaVersion")] public string SchemaVersion { get; set; } = "";
    [JsonPropertyName("initialState")] public string InitialState { get; set; } = "FALL";
    [JsonPropertyName("maxCharacters")] public int MaxCharacters { get; set; } = 4;
    [JsonPropertyName("assetsRootDirectory")] public string AssetsRootDirectory { get; set; } = "assets";
    [JsonPropertyName("stateAssetFolders")] public Dictionary<string, string> StateAssetFolders { get; set; } = new();
    [JsonPropertyName("stateAnimationFPS")] public Dictionary<string, double> StateAnimationFPS { get; set; } = new();
    [JsonPropertyName("defaultCharacters")] public List<CharacterProfileSpec> DefaultCharacters { get; set; } = new();
    [JsonPropertyName("interactionTimings")] public InteractionTimingsSpec InteractionTimings { get; set; } = new();

    public sealed class CharacterProfileSpec
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("displayName")] public string DisplayName { get; set; } = "";
        [JsonPropertyName("assetFolder")] public string AssetFolder { get; set; } = "";
        [JsonPropertyName("audioFolder")] public string AudioFolder { get; set; } = "";
        [JsonPropertyName("playsSongOnClick")] public bool PlaysSongOnClick { get; set; } = false;
        [JsonPropertyName("clickSpeech")] public string ClickSpeech { get; set; } = "히익.. 훌쩍 ( ´•̥×•̥` )";
        [JsonPropertyName("primaryColorHex")] public string PrimaryColorHex { get; set; } = "#FFFDF9";
        [JsonPropertyName("accentColorHex")] public string AccentColorHex { get; set; } = "#FFB7C5";
        [JsonPropertyName("earStyle")] public string EarStyle { get; set; } = "round";
        [JsonPropertyName("heightMultiplier")] public double HeightMultiplier { get; set; } = 1.0;
        [JsonPropertyName("canRestDuringClimb")] public bool CanRestDuringClimb { get; set; } = true;
        [JsonPropertyName("tumbleDurationSeconds")] public double TumbleDurationSeconds { get; set; } = 1.15;
        [JsonPropertyName("tumbleFPS")] public double TumbleFPS { get; set; } = 8.0;
        [JsonPropertyName("catchphrases")] public List<string> Catchphrases { get; set; } = new();
    }

    public sealed class InteractionTimingsSpec
    {
        [JsonPropertyName("holdThresholdSeconds")] public double HoldThresholdSeconds { get; set; } = 0.18;
        [JsonPropertyName("clickCryDurationSeconds")] public double ClickCryDurationSeconds { get; set; } = 1.6;
        [JsonPropertyName("playFullSongOnClick")] public bool PlayFullSongOnClick { get; set; } = true;
        [JsonPropertyName("tumbleDurationSeconds")] public double TumbleDurationSeconds { get; set; } = 1.15;
        [JsonPropertyName("speechBubbleDurationSeconds")] public double SpeechBubbleDurationSeconds { get; set; } = 2.2;
        [JsonPropertyName("idleMinDurationSeconds")] public double IdleMinDurationSeconds { get; set; } = 2.0;
        [JsonPropertyName("idleMaxDurationSeconds")] public double IdleMaxDurationSeconds { get; set; } = 4.8;
        [JsonPropertyName("walkMinDurationSeconds")] public double WalkMinDurationSeconds { get; set; } = 2.5;
        [JsonPropertyName("walkMaxDurationSeconds")] public double WalkMaxDurationSeconds { get; set; } = 6.0;
    }
}

public sealed class SpecBundle
{
    public ArchitectureSpec Architecture { get; }
    public PhysicsAndWorldSpec PhysicsAndWorld { get; }
    public CharacterFSMSpec CharacterFSM { get; }
    public string ProjectRootDirectory { get; }

    private SpecBundle(string specDir)
    {
        ProjectRootDirectory = Directory.GetParent(specDir)?.FullName ?? AppContext.BaseDirectory;
        Architecture = JsonSerializer.Deserialize<ArchitectureSpec>(File.ReadAllText(Path.Combine(specDir, "architecture.json")))!;
        PhysicsAndWorld = JsonSerializer.Deserialize<PhysicsAndWorldSpec>(File.ReadAllText(Path.Combine(specDir, "physics_and_world.json")))!;
        CharacterFSM = JsonSerializer.Deserialize<CharacterFSMSpec>(File.ReadAllText(Path.Combine(specDir, "character_fsm.json")))!;
    }

    public static SpecBundle LoadDefault()
    {
        string[] candidates =
        {
            Path.Combine(AppContext.BaseDirectory, "spec"),
            Path.Combine(Directory.GetCurrentDirectory(), "spec"),
            Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "spec"))
        };

        foreach (var dir in candidates)
        {
            if (File.Exists(Path.Combine(dir, "physics_and_world.json")))
            {
                return new SpecBundle(dir);
            }
        }
        throw new FileNotFoundException("Could not locate spec/*.json directory.");
    }
}
