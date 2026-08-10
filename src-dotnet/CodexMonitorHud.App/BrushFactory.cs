using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CodexMonitorHud.Core.Configuration;

namespace CodexMonitorHud.App;

internal enum BrushRole
{
    Background,
    Primary,
    Secondary,
    Decoration,
    Status
}

internal sealed class BrushFactory
{
    private readonly Dictionary<string, ImageSource> _imageCache = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, Brush> _surfaceCache = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Brush> _brushCache = new(StringComparer.Ordinal);

    public Brush Create(
        string value,
        string fallback,
        BrushRole role,
        HudSettings settings,
        string status,
        bool hasAttention)
    {
        var key = string.Join('|', value, fallback, role, settings.TransparencyMode, settings.Opacity, status, hasAttention);
        if (_brushCache.TryGetValue(key, out var cached))
        {
            return cached;
        }
        var brush = Convert(value, fallback);
        if (settings.TransparencyMode == "uniform")
        {
            // Uniform opacity is applied to the whole window.  Make the shell
            // source color opaque first, so 100% is truly opaque instead of
            // inheriting a translucent ARGB background from a theme.
            if (role == BrushRole.Background && brush is SolidColorBrush uniformSolid)
            {
                var opaque = uniformSolid.Color;
                opaque.A = byte.MaxValue;
                brush = new SolidColorBrush(opaque);
                brush.Freeze();
            }
            CacheBrush(key, brush);
            return brush;
        }

        if (role == BrushRole.Status || brush is not SolidColorBrush solid)
        {
            CacheBrush(key, brush);
            return brush;
        }

        var color = solid.Color;
        color.A = (byte)Math.Round(color.A * GetRoleOpacity(role, settings, status, hasAttention));
        var adjusted = new SolidColorBrush(color);
        adjusted.Freeze();
        CacheBrush(key, adjusted);
        return adjusted;
    }

    public Brush CreateSurface(HudSettings settings, string status, bool hasAttention)
    {
        var imageWrite = string.Empty;
        if (settings.ThemeStyle.Surface == "image" && File.Exists(settings.ThemeStyle.BackgroundImage))
        {
            imageWrite = File.GetLastWriteTimeUtc(settings.ThemeStyle.BackgroundImage).Ticks.ToString();
        }
        var key = string.Join('|',
            settings.ThemeStyle.Surface,
            settings.Background,
            settings.ThemeStyle.GradientStart,
            settings.ThemeStyle.GradientEnd,
            settings.ThemeStyle.GradientAngle,
            settings.ThemeStyle.BackgroundImage,
            imageWrite,
            settings.ThemeStyle.ImageOpacity,
            settings.ThemeStyle.ImageStretch,
            settings.TransparencyMode,
            settings.Opacity,
            status,
            hasAttention);
        if (_surfaceCache.TryGetValue(key, out var cached))
        {
            return cached;
        }

        Brush result;
        if (settings.ThemeStyle.Surface == "image" && File.Exists(settings.ThemeStyle.BackgroundImage))
        {
            var imageKey = settings.ThemeStyle.BackgroundImage + "|" + imageWrite;
            if (!_imageCache.TryGetValue(imageKey, out var source))
            {
                var bitmap = new BitmapImage();
                bitmap.BeginInit();
                bitmap.CacheOption = BitmapCacheOption.OnLoad;
                bitmap.DecodePixelWidth = 1920;
                bitmap.UriSource = new Uri(settings.ThemeStyle.BackgroundImage, UriKind.Absolute);
                bitmap.EndInit();
                bitmap.Freeze();
                source = bitmap;
                _imageCache.Clear();
                _imageCache[imageKey] = source;
            }

            var imageBrush = new ImageBrush(source)
            {
                Stretch = ParseStretch(settings.ThemeStyle.ImageStretch),
                Opacity = settings.TransparencyMode == "uniform" ? 1 : settings.ThemeStyle.ImageOpacity
            };
            imageBrush.Freeze();
            result = imageBrush;
        }
        else if (settings.ThemeStyle.Surface == "gradient")
        {
            var start = ParseColor(settings.ThemeStyle.GradientStart, settings.Background);
            var end = ParseColor(settings.ThemeStyle.GradientEnd, settings.Background);
            var factor = GetRoleOpacity(BrushRole.Background, settings, status, hasAttention);
            start.A = (byte)Math.Round(start.A * factor);
            end.A = (byte)Math.Round(end.A * factor);
            if (settings.TransparencyMode == "uniform")
            {
                start.A = byte.MaxValue;
                end.A = byte.MaxValue;
            }
            var angle = settings.ThemeStyle.GradientAngle * Math.PI / 180;
            var dx = Math.Cos(angle) * 0.5;
            var dy = Math.Sin(angle) * 0.5;
            var gradient = new LinearGradientBrush
            {
                StartPoint = new Point(0.5 - dx, 0.5 - dy),
                EndPoint = new Point(0.5 + dx, 0.5 + dy)
            };
            gradient.GradientStops.Add(new GradientStop(start, 0));
            gradient.GradientStops.Add(new GradientStop(end, 1));
            gradient.Freeze();
            result = gradient;
        }
        else
        {
            result = Create(settings.Background, "#EAFFFFFF", BrushRole.Background, settings, status, hasAttention);
        }

        if (_surfaceCache.Count > 32)
        {
            _surfaceCache.Clear();
        }
        _surfaceCache[key] = result;
        return result;
    }

    public static Brush Convert(string value, string fallback)
    {
        try
        {
            var brush = (Brush)new BrushConverter().ConvertFromString(value)!;
            if (brush.CanFreeze)
            {
                brush.Freeze();
            }
            return brush;
        }
        catch (Exception exception) when (exception is FormatException or NotSupportedException)
        {
            var brush = (Brush)new BrushConverter().ConvertFromString(fallback)!;
            if (brush.CanFreeze)
            {
                brush.Freeze();
            }
            return brush;
        }
    }

    private static double GetRoleOpacity(
        BrushRole role,
        HudSettings settings,
        string status,
        bool hasAttention)
    {
        if (settings.TransparencyMode == "uniform")
        {
            return 1;
        }

        var level = Math.Clamp(settings.Opacity, 0, 1);
        if (settings.TransparencyMode == "layered")
        {
            return role switch
            {
                BrushRole.Background => 0.18 + 0.55 * level,
                BrushRole.Primary => 1,
                BrushRole.Secondary => 0.54 + 0.25 * level,
                BrushRole.Decoration => 0.28 + 0.27 * level,
                _ => 1
            };
        }

        var focused = hasAttention || status is "active" or "completed" or "aborted" or "error";
        var listening = status == "listening";
        return role switch
        {
            BrushRole.Background => focused ? 0.62 + 0.30 * level : listening ? 0.36 + 0.25 * level : 0.14 + 0.22 * level,
            BrushRole.Primary => focused ? 1 : listening ? 0.94 : 0.84,
            BrushRole.Secondary => focused ? 0.84 : listening ? 0.68 : 0.52,
            BrushRole.Decoration => focused ? 0.70 : listening ? 0.48 : 0.30,
            _ => 1
        };
    }

    private void CacheBrush(string key, Brush brush)
    {
        if (_brushCache.Count >= 256)
        {
            _brushCache.Clear();
        }
        _brushCache[key] = brush;
    }

    private static Color ParseColor(string value, string fallback)
    {
        try
        {
            return (Color)ColorConverter.ConvertFromString(value);
        }
        catch (FormatException)
        {
            return (Color)ColorConverter.ConvertFromString(fallback);
        }
    }

    private static Stretch ParseStretch(string value) => value switch
    {
        "uniform" => Stretch.Uniform,
        "fill" => Stretch.Fill,
        "none" => Stretch.None,
        _ => Stretch.UniformToFill
    };
}
