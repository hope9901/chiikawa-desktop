using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace ChiikawaDesktopWin;

/// Persists user-configured default startup characters (multi-select up to 4 characters)
/// and default startup scale across app launches in %APPDATA%\ChiikawaDesktop\preferences.json.
public sealed class UserPreferencesStore
{
    public static UserPreferencesStore Shared { get; } = new();

    private sealed class PreferencesData
    {
        public List<string> StartupCharacters { get; set; } = new();
        public double StartupScale { get; set; } = 0.0;
    }

    private readonly string _prefsFilePath;
    private PreferencesData _data = new();

    private UserPreferencesStore()
    {
        string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        string dir = Path.Combine(appData, "ChiikawaDesktop");
        Directory.CreateDirectory(dir);
        _prefsFilePath = Path.Combine(dir, "preferences.json");
        Load();
    }

    private void Load()
    {
        try
        {
            if (File.Exists(_prefsFilePath))
            {
                _data = JsonSerializer.Deserialize<PreferencesData>(File.ReadAllText(_prefsFilePath)) ?? new PreferencesData();
            }
        }
        catch
        {
            _data = new PreferencesData();
        }
    }

    private void Save()
    {
        try
        {
            File.WriteAllText(_prefsFilePath, JsonSerializer.Serialize(_data, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch
        {
            // Ignore write errors
        }
    }

    public List<string> DefaultStartupCharacters(List<string> fallback)
    {
        return _data.StartupCharacters.Count > 0 ? _data.StartupCharacters : fallback;
    }

    public bool IsStartupCharacterSelected(string id, List<string> fallback)
    {
        return DefaultStartupCharacters(fallback).Contains(id);
    }

    public void ToggleStartupCharacter(string id, List<string> fallback, List<string> orderedValidIds)
    {
        var set = new HashSet<string>(DefaultStartupCharacters(fallback));
        if (set.Contains(id))
        {
            if (set.Count > 1) set.Remove(id);
        }
        else
        {
            set.Add(id);
        }
        _data.StartupCharacters = orderedValidIds.Where(set.Contains).ToList();
        Save();
    }

    public double DefaultStartupScale(double fallback)
    {
        return _data.StartupScale > 0.1 ? _data.StartupScale : fallback;
    }

    public void SetDefaultStartupScale(double scale)
    {
        _data.StartupScale = scale;
        Save();
    }
}
