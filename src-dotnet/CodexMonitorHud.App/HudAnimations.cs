using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using CodexMonitorHud.Core.Configuration;
using CodexMonitorHud.Core.Presentation;
using CodexMonitorHud.Core.State;

namespace CodexMonitorHud.App;

internal static class HudAnimations
{
    public static void ResetAttention(
        FrameworkElement container,
        Ellipse? dot = null,
        FrameworkElement? context = null,
        bool clearContainerBorder = false)
    {
        ResetAnimatedElement(container);
        if (clearContainerBorder && container is Border border)
        {
            border.BorderBrush = null;
            border.BorderThickness = new Thickness(0);
        }
        if (dot is not null)
        {
            ResetAnimatedElement(dot);
        }
        if (context is not null)
        {
            ResetAnimatedElement(context);
        }
    }

    public static void StartAttention(Ellipse? dot, FrameworkElement container, string mode, HudSettings settings)
    {
        StartDot(dot, settings);
        StartSurface(container, mode, settings);
    }

    public static void StartContext(FrameworkElement target, int level, HudSettings settings)
    {
        var spec = level switch
        {
            1 => (Color: "#FF0A84FF", Glow: 0.42, Blur: 14d, Scale: 1.012, Cycle: 760),
            2 => (Color: "#FFFF9F0A", Glow: 0.74, Blur: 28d, Scale: 1.028, Cycle: 580),
            _ => (Color: "#FFFF453A", Glow: 1d, Blur: 42d, Scale: 1.05, Cycle: 420)
        };
        var profile = Profile(settings, spec.Color, spec.Glow, spec.Blur);
        var repeat = Repeat(settings.Attention.DurationSeconds * 1000d / spec.Cycle);
        var effect = Glow(profile);
        target.Effect = effect;
        effect.BeginAnimation(DropShadowEffect.OpacityProperty, AutoReverse(profile.MinimumOpacity, profile.PeakOpacity, spec.Cycle / 2d, repeat));
        AnimateScale(target, spec.Scale, spec.Cycle / 2d, repeat);
    }

    public static void StartAgent(FrameworkElement container, AgentAnimationRecipe? requested, HudSettings settings)
    {
        var recipe = requested ?? DefaultAgentRecipe(settings);
        var profile = Profile(settings, recipe.Color, recipe.Intensity, recipe.GlowRadius);
        var repeat = new RepeatBehavior(recipe.Cycles);
        if (recipe.Layers.Contains("glow", StringComparer.Ordinal))
        {
            var effect = Glow(profile);
            container.Effect = effect;
            effect.BeginAnimation(DropShadowEffect.OpacityProperty,
                AutoReverse(profile.MinimumOpacity, profile.PeakOpacity, recipe.TempoMilliseconds, repeat));
        }
        if (recipe.Layers.Contains("pulse", StringComparer.Ordinal))
        {
            var minimum = Math.Max(0.50, 1 - recipe.Intensity * 0.42);
            container.BeginAnimation(UIElement.OpacityProperty,
                AutoReverse(minimum, 1, recipe.TempoMilliseconds, repeat));
        }
        if (recipe.Layers.Contains("breathe", StringComparer.Ordinal))
        {
            AnimateScale(container, recipe.Scale, recipe.TempoMilliseconds, repeat);
        }
        if (recipe.Layers.Contains("flow", StringComparer.Ordinal) && container is Border border)
        {
            StartFlow(border, profile, recipe.TempoMilliseconds, repeat, recipe.Direction == "right-to-left" ? 1.4 : -1.4,
                Math.Clamp(0.8 + recipe.Intensity * 1.7, 1, 2.5));
        }
    }

    public static void StartTerminalExit(FrameworkElement container, string mode, string color, HudSettings settings, TimeSpan remaining)
    {
        var milliseconds = Math.Clamp(remaining.TotalMilliseconds, 200, mode switch
        {
            "fade" => 1200,
            "focus" => 3600,
            "beacon" => 5000,
            _ => 2400
        });
        var opacityFrames = mode switch
        {
            "fade" => new[] { (0d, 1d), (0.28, 1d), (1d, 0d) },
            "focus" => new[] { (0d, 1d), (0.16, 0.72), (0.30, 1d), (0.46, 0.78), (0.60, 1d), (0.80, 0.92), (1d, 0d) },
            "beacon" => new[] { (0d, 1d), (0.10, 0.58), (0.20, 1d), (0.31, 0.66), (0.42, 1d), (0.54, 0.62), (0.66, 1d), (0.82, 0.94), (1d, 0d) },
            _ => new[] { (0d, 1d), (0.20, 0.82), (0.38, 1d), (0.58, 0.86), (0.76, 1d), (0.88, 0.94), (1d, 0d) }
        };
        container.BeginAnimation(UIElement.OpacityProperty, KeyFrames(milliseconds, opacityFrames, FillBehavior.HoldEnd));
        var scaleFrames = mode switch
        {
            "fade" => new[] { (0d, 1d), (0.75, 1d), (1d, 0.985) },
            "focus" => new[] { (0d, 1d), (0.18, 1.035), (0.34, 1d), (0.50, 1.035), (0.68, 1d), (0.84, 1.018), (1d, 0.985) },
            "beacon" => new[] { (0d, 1d), (0.12, 1.055), (0.24, 1d), (0.36, 1.055), (0.48, 1d), (0.60, 1.055), (0.73, 1d), (0.86, 1.024), (1d, 0.98) },
            _ => new[] { (0d, 1d), (0.22, 1.016), (0.42, 1d), (0.62, 1.016), (0.80, 1d), (1d, 0.985) }
        };
        container.RenderTransformOrigin = new Point(0.5, 0.5);
        var transform = new ScaleTransform(1, 1);
        container.RenderTransform = transform;
        transform.BeginAnimation(ScaleTransform.ScaleXProperty, KeyFrames(milliseconds, scaleFrames, FillBehavior.HoldEnd));
        transform.BeginAnimation(ScaleTransform.ScaleYProperty, KeyFrames(milliseconds, scaleFrames, FillBehavior.HoldEnd));
        if (mode != "fade")
        {
            var profile = Profile(settings, color, mode == "beacon" ? 1 : 0.68, mode == "beacon" ? 44 : 24);
            var effect = Glow(profile);
            container.Effect = effect;
            effect.BeginAnimation(DropShadowEffect.OpacityProperty,
                KeyFrames(milliseconds, new[] { (0d, profile.MinimumOpacity), (0.18, profile.PeakOpacity), (0.58, profile.PeakOpacity), (1d, 0d) }, FillBehavior.HoldEnd));
        }
    }

    private static void StartDot(Ellipse? dot, HudSettings settings)
    {
        if (dot is null || !settings.Attention.DotEnabled || !settings.ShowStatusDot)
        {
            return;
        }
        var cycle = settings.Attention.DotSpeed switch { "slow" => 1050, "fast" => 460, _ => 700 };
        var brightness = settings.Attention.DotBrightness switch
        {
            "subtle" => (Minimum: 0.58, Glow: 0.40, Blur: 8d, Scale: 1.10),
            "bright" => (Minimum: 0.10, Glow: 1.00, Blur: 18d, Scale: 1.28),
            _ => (Minimum: 0.28, Glow: 0.76, Blur: 13d, Scale: 1.18)
        };
        var repeat = Repeat(settings.Attention.DurationSeconds * 1000d / cycle);
        var frames = settings.Attention.DotPattern switch
        {
            "soft" => new[] { (0d, 1d), (0.5, brightness.Minimum), (1d, 1d) },
            "beacon" => new[] { (0d, brightness.Minimum), (0.7, 1d), (1d, brightness.Minimum) },
            _ => new[] { (0d, 1d), (0.16, brightness.Minimum), (0.32, 1d), (0.46, Math.Min(0.92, brightness.Minimum + 0.16)), (0.62, 1d), (1d, 1d) }
        };
        var opacity = KeyFrames(cycle, frames, FillBehavior.Stop);
        opacity.RepeatBehavior = repeat;
        dot.BeginAnimation(UIElement.OpacityProperty, opacity);
        var color = dot.Fill is SolidColorBrush solid ? solid.Color.ToString() : settings.Accent;
        var profile = Profile(settings, color, brightness.Glow, brightness.Blur);
        var effect = Glow(profile);
        dot.Effect = effect;
        effect.BeginAnimation(DropShadowEffect.OpacityProperty,
            AutoReverse(profile.MinimumOpacity, profile.PeakOpacity, cycle / 2d, repeat));
        if (settings.Attention.DotBreathing)
        {
            AnimateScale(dot, brightness.Scale, cycle / 2d, repeat);
        }
    }

    private static void StartSurface(FrameworkElement container, string mode, HudSettings settings)
    {
        if (mode == "off")
        {
            return;
        }
        var repeat = Repeat(settings.Attention.DurationSeconds / 0.9);
        if (mode == "halo")
        {
            var profile = Profile(settings, settings.Accent, 0.72, 20);
            var effect = Glow(profile);
            container.Effect = effect;
            effect.BeginAnimation(DropShadowEffect.OpacityProperty,
                AutoReverse(profile.MinimumOpacity, profile.PeakOpacity, 620, repeat));
            return;
        }
        if (mode == "flow" && container is Border border)
        {
            var profile = Profile(settings, settings.Accent, 0.78, 20);
            StartFlow(border, profile, 1050, Repeat(settings.Attention.DurationSeconds / 1.05), -1.3, 2);
            return;
        }
        var strong = mode == "focus";
        AnimateScale(container, strong ? 1.035 : 1.016, strong ? 300 : 560, repeat);
        container.BeginAnimation(UIElement.OpacityProperty,
            AutoReverse(strong ? 0.48 : 0.78, 1, strong ? 300 : 560, repeat));
    }

    private static void StartFlow(Border border, SurfaceEffectProfile profile, double milliseconds, RepeatBehavior repeat, double from, double thickness)
    {
        var color = ParseColor(profile.Color, "#FF0A84FF");
        var rgb = $"{color.R:X2}{color.G:X2}{color.B:X2}";
        var gradient = new LinearGradientBrush { StartPoint = new Point(0, 0.5), EndPoint = new Point(1, 0.5) };
        gradient.GradientStops.Add(new GradientStop(ParseColor("#00" + rgb, "#000A84FF"), 0));
        gradient.GradientStops.Add(new GradientStop(ParseColor("#22" + rgb, "#220A84FF"), 0.40));
        gradient.GradientStops.Add(new GradientStop(ParseColor(profile.FlowCore, profile.Color), 0.50));
        gradient.GradientStops.Add(new GradientStop(ParseColor("#" + profile.FlowShoulderAlpha + rgb, profile.Color), 0.60));
        gradient.GradientStops.Add(new GradientStop(ParseColor("#00" + rgb, "#000A84FF"), 1));
        var transform = new TranslateTransform(from, 0);
        gradient.RelativeTransform = transform;
        border.BorderBrush = gradient;
        border.BorderThickness = new Thickness(thickness);
        transform.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(from, -from, TimeSpan.FromMilliseconds(milliseconds))
        {
            RepeatBehavior = repeat,
            FillBehavior = FillBehavior.Stop
        });
    }

    private static AgentAnimationRecipe DefaultAgentRecipe(HudSettings settings)
    {
        var layers = settings.AgentNotifications.Mode switch
        {
            "halo" => new[] { "glow" },
            "breathe" => new[] { "glow", "breathe" },
            "flow" => new[] { "glow", "flow" },
            _ => new[] { "glow", "pulse", "breathe" }
        };
        var (intensity, radius, scale) = settings.AgentNotifications.Intensity switch
        {
            "subtle" => (0.42, 18d, 1.012),
            "strong" => (0.95, 44d, 1.055),
            _ => (0.70, 30d, 1.028)
        };
        return new AgentAnimationRecipe(
            layers,
            settings.AgentNotifications.Color,
            intensity,
            720,
            Math.Clamp((int)Math.Ceiling(settings.AgentNotifications.DurationSeconds * 1000d / 720), 1, 8),
            radius,
            scale,
            "left-to-right");
    }

    private static void AnimateScale(FrameworkElement target, double to, double milliseconds, RepeatBehavior repeat)
    {
        target.RenderTransformOrigin = new Point(0.5, 0.5);
        var transform = new ScaleTransform(1, 1);
        target.RenderTransform = transform;
        transform.BeginAnimation(ScaleTransform.ScaleXProperty, AutoReverse(1, to, milliseconds, repeat));
        transform.BeginAnimation(ScaleTransform.ScaleYProperty, AutoReverse(1, to, milliseconds, repeat));
    }

    private static void ResetAnimatedElement(FrameworkElement element)
    {
        element.BeginAnimation(UIElement.OpacityProperty, null);
        element.Opacity = 1;
        element.Effect = null;
        element.RenderTransform = Transform.Identity;
    }

    private static DoubleAnimation AutoReverse(double from, double to, double milliseconds, RepeatBehavior repeat) => new(from, to, TimeSpan.FromMilliseconds(milliseconds))
    {
        AutoReverse = true,
        RepeatBehavior = repeat,
        FillBehavior = FillBehavior.Stop
    };

    private static DoubleAnimationUsingKeyFrames KeyFrames(double milliseconds, IEnumerable<(double Percent, double Value)> frames, FillBehavior fill)
    {
        var animation = new DoubleAnimationUsingKeyFrames
        {
            Duration = TimeSpan.FromMilliseconds(milliseconds),
            FillBehavior = fill
        };
        foreach (var (percent, value) in frames)
        {
            animation.KeyFrames.Add(new LinearDoubleKeyFrame(value, KeyTime.FromPercent(percent)));
        }
        return animation;
    }

    private static RepeatBehavior Repeat(double value) => new(Math.Max(2, Math.Ceiling(value)));

    private static SurfaceEffectProfile Profile(HudSettings settings, string color, double opacity, double blur) =>
        SurfaceEffects.Create(
            settings.Background,
            settings.Foreground,
            settings.ThemeStyle.Surface,
            settings.ThemeStyle.GradientStart,
            settings.ThemeStyle.GradientEnd,
            color,
            opacity,
            blur);

    private static DropShadowEffect Glow(SurfaceEffectProfile profile) => new()
    {
        Color = ParseColor(profile.Color, "#FF0A84FF"),
        ShadowDepth = 0,
        BlurRadius = profile.Blur,
        Opacity = profile.MinimumOpacity
    };

    private static Color ParseColor(string value, string fallback)
    {
        try { return (Color)ColorConverter.ConvertFromString(value); }
        catch (Exception exception) when (exception is FormatException or NotSupportedException)
        {
            return (Color)ColorConverter.ConvertFromString(fallback);
        }
    }
}
