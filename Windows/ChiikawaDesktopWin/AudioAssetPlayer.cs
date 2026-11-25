using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows.Media;

namespace ChiikawaDesktopWin;

/// Scans assets/<character_id>/audio/*.(mp3|wav|m4a) and plays character songs
/// when characters with PlaysSongOnClick=true (Hachiware, Usagi) are single-clicked.
public sealed class AudioAssetPlayer
{
    public static AudioAssetPlayer Shared { get; } = new();

    private readonly Dictionary<string, MediaPlayer> _activePlayers = new();
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

    public double? ToggleOrPlayClickSong(CharacterFSMSpec.CharacterProfileSpec profile)
    {
        if (!profile.PlaysSongOnClick) return null;

        if (_activePlayers.ContainsKey(profile.Id))
        {
            StopSong(profile.Id);
            return null;
        }

        var files = ResolveAudioFiles(profile.AudioFolder);
        if (files.Count == 0) return null;

        string selectedFile = files[Rng.Next(files.Count)];
        try
        {
            var player = new MediaPlayer();
            player.Open(new Uri(selectedFile, UriKind.Absolute));
            player.Play();
            _activePlayers[profile.Id] = player;
            player.MediaEnded += (_, _) => StopSong(profile.Id);
            return player.NaturalDuration.HasTimeSpan
                ? Math.Max(1.0, player.NaturalDuration.TimeSpan.TotalSeconds)
                : 120.0;
        }
        catch
        {
            return null;
        }
    }

    public void StopSong(string characterId)
    {
        if (_activePlayers.Remove(characterId, out var player))
        {
            try
            {
                player.Stop();
                player.Close();
            }
            catch
            {
                // Ignore close error
            }
        }
    }
}
