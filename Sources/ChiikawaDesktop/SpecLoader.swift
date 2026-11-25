import Foundation
import CoreGraphics

// MARK: - Physics & World Specification (spec/physics_and_world.json)

public struct PhysicsAndWorldSpec: Codable {
    public let schemaVersion: String
    public let coordinateSystem: CoordinateSystemSpec
    public let populationLimits: PopulationLimitsSpec
    public let physicsConstants: PhysicsConstantsSpec
    public let jumpAndClimbRules: JumpAndClimbRulesSpec
    public let windowRidingRules: WindowRidingRulesSpec
    public let characterDimensions: CharacterDimensionsSpec
    public let windowDetectionRules: WindowDetectionRulesSpec

    public struct CoordinateSystemSpec: Codable {
        public let origin: String
        public let units: String
        public let activeFrameRate: Int
        public let normalFrameRate: Int
        public let idleFrameRate: Int
        public let windowPollIntervalSeconds: Double
    }

    public struct PopulationLimitsSpec: Codable {
        public let maxConcurrentCharacters: Int
        public let allowDuplicateCharacters: Bool
        public let initialSpawnCharacters: [String]
    }

    public struct PhysicsConstantsSpec: Codable {
        public let gravity: Double
        public let terminalVelocity: Double
        public let airResistance: Double
        public let groundFriction: Double
        public let walkSpeed: Double
        public let landingSnapTolerance: Double
        public let windowTrackingMaxSnapDeltaY: Double
        public let edgeDropProbability: Double
        public let bounceRestitution: Double
    }

    public struct JumpAndClimbRulesSpec: Codable {
        public let enableStepJump: Bool
        public let maxStepJumpHeightRatio: Double
        public let minStepJumpHeightPoints: Double
        public let stepJumpHorizontalReach: Double
        public let stepJumpDurationSeconds: Double
        public let stepJumpArcPeakOffset: Double
        public let stepJumpProbability: Double
        public let enableWindowEdgeClimb: Bool
        public let climbTriggerDistanceX: Double
        public let climbProbability: Double
        public let decisionCooldownSeconds: Double
        public let climbSpeed: Double
        public let minClimbHeightForRestRatio: Double
        public let climbRestSegmentDistanceRatio: Double
        public let climbRestDurationSeconds: Double
        public let description: String
    }

    public struct WindowRidingRulesSpec: Codable {
        public let followMovingWindow: Bool
        public let freeFallWhenOutOfScreenBounds: Bool
        public let freeFallWhenCharacterExceedsWindowEdge: Bool
        public let requireFullCharacterBodyInsideScreen: Bool
        public let spanAllMonitors: Bool
        public let hardFloorClampEnabled: Bool
        public let description: String
    }

    public struct CharacterDimensionsSpec: Codable {
        public let width: Double
        public let height: Double
        public let hitboxPadding: Double
        public let grabAnchorOffsetY: Double
        public let dirtyRectMargin: Double
        public let scaleRange: ScaleRangeSpec
        public let availableScales: [String: Double]

        public struct ScaleRangeSpec: Codable {
            public let min: Double
            public let `default`: Double
            public let max: Double
            public let detentFractions: [Double]
            public let detentSnapRadiusFraction: Double
            public let numberOfTickMarks: Int
            public let tierLabels: [String]
        }
    }

    public struct WindowDetectionRulesSpec: Codable {
        public let allowedWindowLayers: [Int]
        public let minWindowWidth: Double
        public let minWindowHeight: Double
        public let minTopClearanceFromScreenTop: Double
        public let ignoredOwnerNames: [String]
        public let occludeLowerWindows: Bool
        public let description: String
    }
}

// MARK: - Character FSM Specification (spec/character_fsm.json)

public struct CharacterFSMSpec: Codable {
    public let schemaVersion: String
    public let initialState: String
    public let maxCharacters: Int
    public let assetsRootDirectory: String
    public let stateAssetFolders: [String: String]
    public let stateAnimationFPS: [String: Double]
    public let defaultCharacters: [CharacterProfileSpec]
    public let interactionTimings: InteractionTimingsSpec
    public let states: [String: StateDefinitionSpec]

    public struct CharacterProfileSpec: Codable {
        public let id: String
        public let displayName: String
        public let assetFolder: String
        public let audioFolder: String
        public let playsSongOnClick: Bool
        public let clickSpeech: String
        public let primaryColorHex: String
        public let accentColorHex: String
        public let earStyle: String
        public let heightMultiplier: Double
        public let baseSpriteScale: Double
        public let songSpriteScale: Double
        public let canRestDuringClimb: Bool
        public let tumbleDurationSeconds: Double
        public let tumbleFPS: Double
        public let catchphrases: [String]
    }

    public struct InteractionTimingsSpec: Codable {
        public let holdThresholdSeconds: Double
        public let clickCryDurationSeconds: Double
        public let playFullSongOnClick: Bool
        public let allowConcurrentSinging: Bool
        public let tumbleDurationSeconds: Double
        public let speechBubbleDurationSeconds: Double
        public let idleMinDurationSeconds: Double
        public let idleMaxDurationSeconds: Double
        public let walkMinDurationSeconds: Double
        public let walkMaxDurationSeconds: Double
    }

    public struct StateDefinitionSpec: Codable {
        public let description: String
        public let gravityEnabled: Bool
        public let horizontalMovement: Bool
        public let ridesMovingWindow: Bool?
        public let followsMouseCursor: Bool?
        public let visualExpression: String
        public let transitions: [StateTransitionSpec]
    }

    public struct StateTransitionSpec: Codable {
        public let event: String
        public let targetState: String
        public let description: String
    }
}

// MARK: - Architecture Specification (spec/architecture.json)

public struct ArchitectureSpec: Codable {
    public let schemaVersion: String
    public let projectName: String
    public let description: String
    public let resourceOptimizationPolicy: ResourceOptimizationPolicySpec

    public struct ResourceOptimizationPolicySpec: Codable {
        public let activeFrameRate: Int
        public let normalFrameRate: Int
        public let idleFrameRate: Int
        public let windowPollIntervalSeconds: Double
        public let useDirtyRectInvalidation: Bool
        public let sleepOnScreenLock: Bool
        public let maxConcurrentCharacters: Int
        public let allowDuplicateCharacters: Bool
    }
}

// MARK: - SpecLoader

public final class SpecBundle {
    public let architecture: ArchitectureSpec
    public let physicsAndWorld: PhysicsAndWorldSpec
    public let characterFSM: CharacterFSMSpec

    public init(specDirectoryURL: URL) throws {
        let decoder = JSONDecoder()

        let archData = try Data(contentsOf: specDirectoryURL.appendingPathComponent("architecture.json"))
        self.architecture = try decoder.decode(ArchitectureSpec.self, from: archData)

        let physicsData = try Data(contentsOf: specDirectoryURL.appendingPathComponent("physics_and_world.json"))
        self.physicsAndWorld = try decoder.decode(PhysicsAndWorldSpec.self, from: physicsData)

        let fsmData = try Data(contentsOf: specDirectoryURL.appendingPathComponent("character_fsm.json"))
        self.characterFSM = try decoder.decode(CharacterFSMSpec.self, from: fsmData)
    }

    public static func loadDefault() throws -> SpecBundle {
        let fileManager = FileManager.default
        let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let projectDirFromSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidateDirs: [URL] = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("spec"),
            projectDirFromSource.appendingPathComponent("spec"),
            currentDir.appendingPathComponent("spec"),
            Bundle.main.resourceURL?.appendingPathComponent("spec")
        ].compactMap { $0 }

        for dir in candidateDirs {
            if fileManager.fileExists(atPath: dir.appendingPathComponent("physics_and_world.json").path) {
                return try SpecBundle(specDirectoryURL: dir)
            }
        }
        throw NSError(
            domain: "SpecLoader",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate spec/*.json directory."]
        )
    }
}
