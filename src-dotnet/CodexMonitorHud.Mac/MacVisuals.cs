using Avalonia.Media;
using CodexMonitorHud.Core.Configuration;

namespace CodexMonitorHud.Mac;

internal static class MacVisuals
{
    public static IBrush Brush(string value, string fallback = "#FF111827")
    {
        try { return new SolidColorBrush(Color.Parse(value)); }
        catch (FormatException) { return new SolidColorBrush(Color.Parse(fallback)); }
    }

    public static IBrush StatusBrush(HudSettings settings, string status) =>
        Brush(settings.StatusColors.TryGetValue(status, out var value) ? value : settings.Accent, settings.Accent);

    public static string Text(IReadOnlyDictionary<string, string> locale, string key) =>
        locale.TryGetValue(key, out var value) ? value : key;
}
