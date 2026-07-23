using System.Globalization;

namespace CodexMonitorHud.Core.Presentation;

public sealed record SurfaceEffectProfile(
    string Tone,
    string Color,
    double PeakOpacity,
    double MinimumOpacity,
    double Blur,
    string FlowCore,
    string FlowShoulderAlpha);

public static class SurfaceEffects
{
    public static SurfaceEffectProfile Create(
        string background,
        string foreground,
        string surface = "solid",
        string gradientStart = "",
        string gradientEnd = "",
        string effectColor = "#FF0A84FF",
        double baseOpacity = 0.72,
        double baseBlur = 20)
    {
        var foregroundLuminance = Luminance(ParseColor(foreground, "#FFFFFFFF"));
        var surfaceLuminance = surface switch
        {
            "gradient" =>
                (Luminance(ParseColor(gradientStart, background)) +
                 Luminance(ParseColor(gradientEnd, background))) / 2,
            "image" => 1 - foregroundLuminance,
            _ => Luminance(ParseColor(background, "#EAFFFFFF"))
        };
        var isDark = surfaceLuminance < 0.46;
        var color = ParseColor(effectColor, "#FF0A84FF");
        var target = isDark ? 255.0 : 0.0;
        var mix = isDark ? 0.22 : 0.18;
        var red = (int)Math.Round(color.R + (target - color.R) * mix);
        var green = (int)Math.Round(color.G + (target - color.G) * mix);
        var blue = (int)Math.Round(color.B + (target - color.B) * mix);
        var adaptive = $"#FF{red:X2}{green:X2}{blue:X2}";

        return isDark
            ? new SurfaceEffectProfile(
                "dark",
                adaptive,
                Math.Min(1, baseOpacity * 1.18 + 0.06),
                0.08,
                Math.Min(72, baseBlur * 1.18),
                "#FFF7FBFF",
                "C8")
            : new SurfaceEffectProfile(
                "light",
                adaptive,
                Math.Min(0.92, baseOpacity * 0.92),
                0.03,
                Math.Max(6, baseBlur * 0.86),
                adaptive,
                "98");
    }

    private static Rgb ParseColor(string? value, string fallback)
    {
        var candidate = ExtractRgb(value) ?? ExtractRgb(fallback) ?? "0A84FF";
        return new Rgb(
            int.Parse(candidate[..2], NumberStyles.HexNumber, CultureInfo.InvariantCulture),
            int.Parse(candidate.Substring(2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture),
            int.Parse(candidate.Substring(4, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture));
    }

    private static string? ExtractRgb(string? value)
    {
        if (value is null)
        {
            return null;
        }

        if (value.Length == 9 && value[0] == '#')
        {
            return value[3..];
        }

        return value.Length == 7 && value[0] == '#' ? value[1..] : null;
    }

    private static double Luminance(Rgb color) =>
        0.2126 * Linear(color.R) + 0.7152 * Linear(color.G) + 0.0722 * Linear(color.B);

    private static double Linear(int value)
    {
        var channel = value / 255.0;
        return channel <= 0.04045
            ? channel / 12.92
            : Math.Pow((channel + 0.055) / 1.055, 2.4);
    }

    private sealed record Rgb(int R, int G, int B);
}
