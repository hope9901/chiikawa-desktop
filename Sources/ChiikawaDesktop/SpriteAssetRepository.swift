import AppKit
import CoreGraphics

/// Loads and caches PNG sprite sequences from `assets/<character_id>/<state_folder>/*.png`
/// as defined in `spec/character_fsm.json`. If a folder is empty, returns nil so `OverlayView`
/// gracefully falls back to the lightweight procedural vector drawing.
public final class SpriteAssetRepository {
    private let fsmSpec: CharacterFSMSpec
    private let assetsRootURL: URL
    // Cache key: "<character_id>:<state_folder>" -> sorted array of CGImages
    private var cache: [String: [CGImage]] = [:]

    public init(fsmSpec: CharacterFSMSpec) {
        self.fsmSpec = fsmSpec
        self.assetsRootURL = SpriteAssetRepository.resolveAssetsRoot(folderName: fsmSpec.assetsRootDirectory)
        preloadAll()
    }

    private static func resolveAssetsRoot(folderName: String) -> URL {
        let fm = FileManager.default
        let currentDir = URL(fileURLWithPath: fm.currentDirectoryPath)
        let projectDirFromSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        // Prioritize live project assets/ directory before frozen .app bundle Resources
        let candidates: [URL] = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(folderName),
            projectDirFromSource.appendingPathComponent(folderName),
            currentDir.appendingPathComponent(folderName),
            Bundle.main.resourceURL?.appendingPathComponent(folderName)
        ].compactMap { $0 }

        for dir in candidates {
            if fm.fileExists(atPath: dir.path) {
                return dir
            }
        }
        return currentDir.appendingPathComponent(folderName)
    }

    public func preloadAll() {
        cache.removeAll()
        let fm = FileManager.default
        let uniqueFolders = Set(fsmSpec.stateAssetFolders.values)

        for profile in fsmSpec.defaultCharacters {
            for stateFolder in uniqueFolders {
                let dirURL = assetsRootURL
                    .appendingPathComponent(profile.id)
                    .appendingPathComponent(stateFolder)
                guard let items = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) else {
                    continue
                }
                let pngFiles = items
                    .filter { $0.pathExtension.lowercased() == "png" }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

                var frames: [CGImage] = []
                for url in pngFiles {
                    if let nsImage = NSImage(contentsOf: url),
                       let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        frames.append(cgImage)
                    }
                }
                if !frames.isEmpty {
                    cache["\(profile.id):\(stateFolder)"] = frames
                }
            }
        }
    }

    /// Returns the active sprite frame `CGImage` for the character's current state and elapsed time,
    /// or `nil` if no PNG files have been placed in that folder yet.
    public func frame(for characterID: String, state: CharacterStateID, stateElapsed: Double, animPhase: Double) -> CGImage? {
        let folderName = fsmSpec.stateAssetFolders[state.rawValue] ?? state.rawValue.lowercased()
        let key = "\(characterID):\(folderName)"

        // Intelligent fallback chain if custom sprites for a new state (like jump/climb/climb_rest) aren't added yet
        let fallbackFolder: String
        switch state {
        case .jumpStep, .climbWall:
            fallbackFolder = "walk"
        case .climbRest:
            fallbackFolder = "idle"
        default:
            fallbackFolder = "idle"
        }

        let frames = cache[key] ?? cache["\(characterID):\(fallbackFolder)"] ?? cache["\(characterID):idle"]
        guard let validFrames = frames, !validFrames.isEmpty else {
            return nil
        }

        let fps = fsmSpec.stateAnimationFPS[state.rawValue] ?? 8.0
        if state == .tumble {
            let profileTumbleFPS = fsmSpec.defaultCharacters.first(where: { $0.id == characterID })?.tumbleFPS ?? fps
            let idx = min(validFrames.count - 1, Int(stateElapsed * profileTumbleFPS))
            return validFrames[max(0, idx)]
        } else {
            let idx = Int(animPhase * fps) % validFrames.count
            return validFrames[max(0, idx)]
        }
    }
}
