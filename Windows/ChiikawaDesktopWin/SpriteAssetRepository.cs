using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows.Media.Imaging;

namespace ChiikawaDesktopWin;

/// Loads and caches PNG sprite sequences from assets/<character_id>/<state_folder>/*.png
/// as defined in spec/character_fsm.json.
public sealed class SpriteAssetRepository
{
    private readonly CharacterFSMSpec _fsmSpec;
    private readonly string _assetsRootPath;
    private readonly Dictionary<string, List<BitmapSource>> _cache = new();

    public SpriteAssetRepository(CharacterFSMSpec fsmSpec, string projectRootDir)
    {
        _fsmSpec = fsmSpec;
        _assetsRootPath = ResolveAssetsRoot(fsmSpec.AssetsRootDirectory, projectRootDir);
        PreloadAll();
    }

    private static string ResolveAssetsRoot(string folderName, string projectRootDir)
    {
        string[] candidates =
        {
            Path.Combine(AppContext.BaseDirectory, folderName),
            Path.Combine(projectRootDir, folderName),
            Path.Combine(Directory.GetCurrentDirectory(), folderName)
        };

        foreach (var dir in candidates)
        {
            if (Directory.Exists(dir)) return dir;
        }
        return Path.Combine(AppContext.BaseDirectory, folderName);
    }

    public void PreloadAll()
    {
        _cache.Clear();
        var uniqueFolders = _fsmSpec.StateAssetFolders.Values.Distinct().ToList();

        foreach (var profile in _fsmSpec.DefaultCharacters)
        {
            foreach (var stateFolder in uniqueFolders)
            {
                string dirPath = Path.Combine(_assetsRootPath, profile.Id, stateFolder);
                if (!Directory.Exists(dirPath)) continue;

                var pngFiles = Directory.GetFiles(dirPath, "*.png")
                    .OrderBy(p => Path.GetFileNameWithoutExtension(p), StringComparer.OrdinalIgnoreCase)
                    .ToList();

                var frames = new List<BitmapSource>();
                foreach (var file in pngFiles)
                {
                    try
                    {
                        var bmp = new BitmapImage();
                        bmp.BeginInit();
                        bmp.CacheOption = BitmapCacheOption.OnLoad;
                        bmp.UriSource = new Uri(file, UriKind.Absolute);
                        bmp.EndInit();
                        bmp.Freeze();
                        frames.Add(bmp);
                    }
                    catch
                    {
                        // Ignore unreadable image
                    }
                }

                if (frames.Count > 0)
                {
                    _cache[$"{profile.Id}:{stateFolder}"] = frames;
                }
            }
        }
    }

    public BitmapSource? GetFrame(string characterId, CharacterStateID state, double stateElapsed, double animPhase)
    {
        string stateKey = state.ToString();
        string folderName = _fsmSpec.StateAssetFolders.TryGetValue(stateKey, out var mapped)
            ? mapped
            : stateKey.ToLowerInvariant();

        string fallbackFolder = state is CharacterStateID.JUMP_STEP or CharacterStateID.CLIMB_WALL ? "walk" : "idle";

        if (!_cache.TryGetValue($"{characterId}:{folderName}", out var frames) &&
            !_cache.TryGetValue($"{characterId}:{fallbackFolder}", out frames) &&
            !_cache.TryGetValue($"{characterId}:idle", out frames))
        {
            return null;
        }

        if (frames == null || frames.Count == 0) return null;

        double fps = _fsmSpec.StateAnimationFPS.TryGetValue(stateKey, out var f) ? f : 8.0;
        if (state == CharacterStateID.TUMBLE)
        {
            double profileFps = _fsmSpec.DefaultCharacters.FirstOrDefault(c => c.Id == characterId)?.TumbleFPS ?? fps;
            int idx = Math.Min(frames.Count - 1, (int)(stateElapsed * profileFps));
            return frames[Math.Max(0, idx)];
        }
        else
        {
            int idx = (int)(animPhase * fps) % frames.Count;
            return frames[Math.Max(0, idx)];
        }
    }
}
