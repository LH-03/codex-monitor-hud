namespace CodexMonitorHud.Core.Models;

public sealed record HudMetric(string Key, string Label, string Value);

public enum HudPlatform
{
    Windows,
    MacOS,
    Linux
}

public sealed record HudPaths(
    string PluginRoot,
    string SessionsRoot,
    string StateRoot,
    string ConfigPath,
    string DefaultConfigPath,
    string LocaleRoot)
{
    public static HudPaths Create(string pluginRoot, string? localAppData = null, string? home = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(pluginRoot);
        var platform = OperatingSystem.IsMacOS()
            ? HudPlatform.MacOS
            : OperatingSystem.IsWindows() ? HudPlatform.Windows : HudPlatform.Linux;
        return CreateForPlatform(pluginRoot, platform, home, localAppData);
    }

    public static HudPaths CreateForPlatform(
        string pluginRoot,
        HudPlatform platform,
        string? home = null,
        string? localAppData = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(pluginRoot);
        home ??= Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        ArgumentException.ThrowIfNullOrWhiteSpace(home);
        var stateRoot = platform switch
        {
            HudPlatform.MacOS => Path.Combine(home, "Library", "Application Support", "CodexMonitorHUD"),
            HudPlatform.Windows => Path.Combine(
                localAppData ?? Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "CodexMonitorHUD"),
            _ => Path.Combine(
                localAppData ?? Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "CodexMonitorHUD")
        };
        return new HudPaths(
            Path.GetFullPath(pluginRoot),
            Path.Combine(home, ".codex", "sessions"),
            stateRoot,
            Path.Combine(stateRoot, "settings.json"),
            Path.Combine(pluginRoot, "config.default.json"),
            Path.Combine(pluginRoot, "locales"));
    }
}
