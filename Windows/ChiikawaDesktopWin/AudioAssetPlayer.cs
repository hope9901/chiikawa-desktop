using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows.Media;

namespace ChiikawaDesktopWin;

/// Scans assets/<character_id>/audio/*.(mp3|wav|m4a) and plays character songs
/// when characters with PlaysSongOnClick=true (Hachiware, Usagi) are single-clicked.
///
/// WPF MediaPlayer opens media asynchronously: right after Open()/Play() the
/// NaturalDuration is not known yet, so the caller cannot rely on a returned
/// duration. Instead, callers poll <see cref="IsSongActive"/> every frame; a song
/// is considered finished when MediaEnded/MediaFailed fires, when the playback
/// position reaches the end, or when the media never opens (e.g. Windows N/KN
/// editions without the Media Feature Pack).
public sealed class AudioAssetPlayer
{
    public static AudioAssetPlayer Shared { get; } = new();

    /// Upper bound used only as a safety net by the caller's state timer.
    public const double FallbackMaxSongSeconds = 300.0;

    /// If MediaOpened has not fired within this time, treat playback as failed.
    private const double OpenTimeoutSeconds = 6.0;

    private sealed class ActiveSong
    {
        public required MediaPlayer Player { get; init; }
        public DateTime StartedUtc { get; } = DateTime.UtcNow;
        public bool Opened { get; set; }
    }

    private readonly Dictionary<string, ActiveSong> _activeSongs = new();
    private static readonly Random Rng = new();
    private static readonly HashSet<string> ValidExts = new(StringComparer.OrdinalIgnoreCase)
    {
        ".mp3", ".wav", ".m4a", ".aac", ".ogg"
    };

    private AudioAssetPlayer() { }

    private static List<string> ResolveAudioFiles(string audioFolder)
    {
        string[] candidateRoots =
        {
            AppContext.BaseDirectory,
            Directory.GetCurrentDirectory(),
            Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", ".."))
        };

        foreach (var root in candidateRoots)
        {
            string dir = Path.Combine(root, audioFolder.Replace('/', Path.DirectorySeparatorChar));
            if (!Directory.Exists(dir)) continue;

            var files = Directory.GetFiles(dir)
                .Where(f => ValidExts.Contains(Path.GetExtension(f)))
                .OrderBy(f => f, StringComparer.OrdinalIgnoreCase)
                .ToList();
            if (files.Count > 0) return files;
        }
        return new List<string>();
    }

    /// Returns null when no song was started (or a playing song was toggled off),
    /// -1 when another character is already singing, otherwise a fallback upper
    /// bound in seconds. The real end of the song is reported by IsSongActive().
    public double? ToggleOrPlayClickSong(CharacterFSMSpec.CharacterProfileSpec profile, bool allowConcurrent = false)
    {
        if (!profile.PlaysSongOnClick) return null;

        if (IsSongActive(profile.Id))
        {
            StopSong(profile.Id);
            return null;
        }

        if (!allowConcurrent && _activeSongs.Keys.ToList().Any(id => id != profile.Id && IsSongActive(id)))
        {
            return -1.0;
        }

        var files = ResolveAudioFiles(profile.AudioFolder);
        if (files.Count == 0) return null;

        string selectedFile = files[Rng.Next(files.Count)];
        MediaPlayer? player = null;
        try
        {
            player = new MediaPlayer();
            var song = new ActiveSong { Player = player };
            string id = profile.Id;

            // Subscribe before Open() so no event can be missed.
            player.MediaOpened += (_, _) => song.Opened = true;
            player.MediaEnded += (_, _) => StopSongIfCurrent(id, song);
            player.MediaFailed += (_, _) => StopSongIfCurrent(id, song);

            _activeSongs[id] = song;
            player.Open(new Uri(selectedFile, UriKind.Absolute));
            player.Play();
            return FallbackMaxSongSeconds;
        }
        catch
        {
            _activeSongs.Remove(profile.Id);
            try { player?.Close(); } catch { /* ignore */ }
            return null;
        }
    }

    /// True while the character's song is actually playing (or still opening).
    /// Also detects end-of-media by position, because MediaEnded is not raised
    /// reliably for every codec/OS combination (observed on Windows 10).
    public bool IsSongActive(string characterId)
    {
        if (!_activeSongs.TryGetValue(characterId, out var song)) return false;

        try
        {
            var player = song.Player;
            if (!song.Opened)
            {
                if ((DateTime.UtcNow - song.StartedUtc).TotalSeconds > OpenTimeoutSeconds)
                {
                    StopSong(characterId);
                    return false;
                }
                return true;
            }

            if (player.NaturalDuration.HasTimeSpan)
            {
                var total = player.NaturalDuration.TimeSpan;
                if (total > TimeSpan.Zero && player.Position >= total - TimeSpan.FromMilliseconds(80))
                {
                    StopSong(characterId);
                    return false;
                }
            }
            return true;
        }
        catch
        {
            StopSong(characterId);
            return false;
        }
    }

    private void StopSongIfCurrent(string characterId, ActiveSong song)
    {
        // A finished/failed old player must not stop a newer song for the same character.
        if (_activeSongs.TryGetValue(characterId, out var current) && ReferenceEquals(current, song))
        {
            StopSong(characterId);
        }
    }

    public void StopSong(string characterId)
    {
        if (_activeSongs.Remove(characterId, out var song))
        {
            try
            {
                song.Player.Stop();
                song.Player.Close();
            }
            catch
            {
                // Ignore close error
            }
        }
    }
}
