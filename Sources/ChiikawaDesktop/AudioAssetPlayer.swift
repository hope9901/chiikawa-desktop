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
        let validExts: Set<String> = ["mp3", "wav", "m4a", "aac", "caf", "ogg"]

        // 1st priority: Inside the .app bundle's own Contents/Resources/assets/<id>/audio
        // Reading inside Bundle.main.resourceURL NEVER triggers macOS TCC Desktop/Documents folder permission prompts!
        var candidateRoots: [URL] = []
        if let resURL = Bundle.main.resourceURL {
            candidateRoots.append(resURL)
        } else {
            candidateRoots.append(URL(fileURLWithPath: fm.currentDirectoryPath))
        }

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
    /// - If this character is already singing: stops its song and returns `nil`.
    /// - If `allowConcurrentSinging == false` and ANOTHER character is currently singing: refuses to start a second song and returns `-1.0`.
    /// - Otherwise starts playback and returns the full audio duration in seconds.
    @discardableResult
    public func toggleOrPlayClickSong(
        for profile: CharacterFSMSpec.CharacterProfileSpec,
        allowConcurrent: Bool = false
    ) -> Double? {
        guard profile.playsSongOnClick else { return nil }

        if isPlaying(for: profile.id) {
            stopSong(for: profile.id)
            return nil
        }

        if !allowConcurrent && isAnyOtherCharacterPlaying(except: profile.id) {
            return -1.0
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

    public func isAnyOtherCharacterPlaying(except characterID: String) -> Bool {
        for (id, player) in activePlayers where id != characterID {
            if player.isPlaying {
                return true
            }
        }
        return false
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
