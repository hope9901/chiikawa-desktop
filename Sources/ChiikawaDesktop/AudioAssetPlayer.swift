import Foundation
import AVFoundation

/// Loads and plays character song audio files from `assets/<character_id>/audio/*.(mp3|wav|m4a)`
/// when a character with `playsSongOnClick == true` (Hachiware, Usagi) is single-clicked.
public final class AudioAssetPlayer {
    public static let shared = AudioAssetPlayer()

    private var activePlayers: [String: AVAudioPlayer] = [:]

    private init() {}

    private func resolveAudioFiles(for audioFolder: String) -> [URL] {
        let fm = FileManager.default
        let currentDir = URL(fileURLWithPath: fm.currentDirectoryPath)
        let projectDirFromSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        // Prioritize the live project directory (next to ChiikawaDesktop.app) before the frozen .app bundle Resources
        let candidateRoots: [URL] = [
            Bundle.main.bundleURL.deletingLastPathComponent(),
            projectDirFromSource,
            currentDir,
            Bundle.main.resourceURL
        ].compactMap { $0 }

        let validExts: Set<String> = ["mp3", "wav", "m4a", "aac", "caf", "ogg"]

        for root in candidateRoots {
            let folderURL = root.appendingPathComponent(audioFolder)
            guard let items = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
                continue
            }
            let audioFiles = items
                .filter { validExts.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            if !audioFiles.isEmpty {
                return audioFiles
            }
        }
        return []
    }

    /// Toggles or plays a song in `profile.audioFolder` for the given character.
    /// If already playing, stops the song and returns `nil` (so clicking again stops singing).
    /// Otherwise starts playback and returns the full audio duration in seconds.
    @discardableResult
    public func toggleOrPlayClickSong(for profile: CharacterFSMSpec.CharacterProfileSpec) -> Double? {
        guard profile.playsSongOnClick else { return nil }

        if isPlaying(for: profile.id) {
            stopSong(for: profile.id)
            return nil
        }

        let files = resolveAudioFiles(for: profile.audioFolder)
        guard let selectedURL = files.randomElement() else {
            return nil
        }

        do {
            let player = try AVAudioPlayer(contentsOf: selectedURL)
            player.prepareToPlay()
            player.play()
            activePlayers[profile.id] = player
            return max(1.0, player.duration)
        } catch {
            NSLog("[ChiikawaDesktop] Failed to play audio \(selectedURL.lastPathComponent): \(error)")
            return nil
        }
    }

    public func stopSong(for characterID: String) {
        if let player = activePlayers.removeValue(forKey: characterID) {
            player.stop()
        }
    }

    public func isPlaying(for characterID: String) -> Bool {
        return activePlayers[characterID]?.isPlaying ?? false
    }
}
