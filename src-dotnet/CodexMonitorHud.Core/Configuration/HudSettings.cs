using System.Text.Json.Nodes;
using CodexMonitorHud.Core.State;

namespace CodexMonitorHud.Core.Configuration;

public sealed record MetricFieldSettings(
    bool Model,
    bool CallTotal,
    bool CacheHitRate,
    bool TaskTotal,
    bool EstimatedCost,
    bool Updated);

public sealed record MultiTaskSettings(
    string DisplayMode,
    string ListStyle,
    string ListDensity,
    string ListDetail,
    string NameMode,
    int MaxSplitBubbles,
    bool AutoSplitNewTasks,
    int NumberCooldownSeconds,
    MetricFieldSettings ListFields,
    MetricFieldSettings BubbleFields);

public sealed record SessionSourceSettings(
    bool Desktop,
    bool VsCode,
    bool DefaultCli,
    bool DeepSeekCli);

public sealed record IdleIndicatorSettings(
    bool Enabled,
    double AfterMinutes,
    string Layout,
    string TaskStyle,
    bool IncludeTaskBubbles);

public sealed record BehaviorSettings(
    bool OpenTaskOnDoubleClick,
    IdleIndicatorSettings IdleIndicator,
    bool ContextAlertsEnabled,
    IReadOnlyList<double> ContextThresholds);

public sealed record AttentionSettings(
    string SummaryMode,
    string ListMode,
    string TaskBubbleMode,
    bool DotEnabled,
    string DotPattern,
    string DotBrightness,
    string DotSpeed,
    bool DotBreathing,
    int DurationSeconds,
    int CompletionGraceSeconds,
    bool OnCompleted,
    bool OnAbortedOrError,
    bool OnSettled);

public sealed record AgentNotificationSettings(
    bool Enabled,
    string Permission,
    string Mode,
    int DurationSeconds,
    string Color,
    string GlowPreset,
    string Intensity);

public sealed record ThemeStyleSettings(
    string Surface,
    string GradientStart,
    string GradientEnd,
    double GradientAngle,
    string BackgroundImage,
    double ImageOpacity,
    string ImageStretch,
    string Shadow,
    double BorderWidth,
    double StatusDotSize,
    string FontFamily);

public sealed record StatusTimingSettings(
    double ActiveSeconds,
    double IdleSeconds,
    double ErrorHoldSeconds,
    double TerminalHoldSeconds,
    string TerminalExitMode);

public sealed record HudSettings
{
    public required JsonObject Document { get; init; }
    public required string Preset { get; init; }
    public required string Language { get; init; }
    public required string Layout { get; init; }
    public required string NumberFormat { get; init; }
    public required string MonitorScope { get; init; }
    public required int ActiveWindowMinutes { get; init; }
    public required SessionSourceSettings SessionSources { get; init; }
    public required MultiTaskSettings MultiTask { get; init; }
    public required BehaviorSettings Behavior { get; init; }
    public required AttentionSettings Attention { get; init; }
    public required AgentNotificationSettings AgentNotifications { get; init; }
    public required string Separator { get; init; }
    public required string Position { get; init; }
    public double? CustomLeft { get; init; }
    public double? CustomTop { get; init; }
    public required double FontSize { get; init; }
    public required double CornerRadius { get; init; }
    public required double Opacity { get; init; }
    public required string TransparencyMode { get; init; }
    public required double Scale { get; init; }
    public required bool AlwaysOnTop { get; init; }
    public required bool MousePassthrough { get; init; }
    public required bool ShowStatusDot { get; init; }
    public required bool AnimateUpdates { get; init; }
    public required ThemeStyleSettings ThemeStyle { get; init; }
    public required IReadOnlyDictionary<string, string> StatusColors { get; init; }
    public required StatusTimingSettings StatusTiming { get; init; }
    public required string Background { get; init; }
    public required string Foreground { get; init; }
    public required string Muted { get; init; }
    public required string Accent { get; init; }
    public required string Border { get; init; }
    public required string PricingPath { get; init; }
    public required IReadOnlyDictionary<string, bool> Fields { get; init; }

    public static HudSettings From(JsonObject document)
    {
        var multi = Object(document, "multiTask");
        var sources = Object(document, "sessionSources");
        var behavior = Object(document, "behavior");
        var idle = Object(behavior, "idleIndicator");
        var context = Object(behavior, "contextAlerts");
        var attention = Object(document, "attention");
        var notices = Object(document, "agentNotifications");
        var theme = Object(document, "themeStyle");
        var timing = Object(document, "statusTiming");
        return new HudSettings
        {
            Document = document,
            Preset = Text(document, "preset"),
            Language = Text(document, "language", "en"),
            Layout = Text(document, "layout", "chips"),
            NumberFormat = Text(document, "numberFormat", "exact"),
            MonitorScope = Text(document, "monitorScope", "aggregate"),
            ActiveWindowMinutes = Integer(document, "activeWindowMinutes", 30),
            SessionSources = new SessionSourceSettings(
                Boolean(sources, "desktop", true),
                Boolean(sources, "vscode", true),
                Boolean(sources, "defaultCli", true),
                Boolean(sources, "deepSeekCli", true)),
            MultiTask = new MultiTaskSettings(
                Text(multi, "displayMode", "summary"),
                Text(multi, "listStyle", "rows"),
                Text(multi, "listDensity", "compact"),
                Text(multi, "listDetail", "balanced"),
                Text(multi, "nameMode", "always"),
                Integer(multi, "maxSplitBubbles", 6),
                Boolean(multi, "autoSplitNewTasks", true),
                Integer(multi, "numberCooldownSeconds", 120),
                MetricFields(Object(multi, "listFields")),
                MetricFields(Object(multi, "bubbleFields"))),
            Behavior = new BehaviorSettings(
                Boolean(behavior, "openTaskOnDoubleClick"),
                new IdleIndicatorSettings(
                    Boolean(idle, "enabled"),
                    Number(idle, "afterMinutes", 15),
                    Text(idle, "layout", "overall"),
                    Text(idle, "taskStyle", "dot"),
                    Boolean(idle, "includeTaskBubbles", true)),
                Boolean(context, "enabled"),
                Array(context, "thresholds").Select(static node => Number(node, 0)).ToArray()),
            Attention = new AttentionSettings(
                Text(attention, "summaryMode", "halo"),
                Text(attention, "listMode", "flow"),
                Text(attention, "taskBubbleMode", "flow"),
                Boolean(attention, "dotEnabled", true),
                Text(attention, "dotPattern", "heartbeat"),
                Text(attention, "dotBrightness", "balanced"),
                Text(attention, "dotSpeed", "normal"),
                Boolean(attention, "dotBreathing", true),
                Integer(attention, "durationSeconds", 6),
                Integer(attention, "completionGraceSeconds", 8),
                Boolean(attention, "onCompleted", true),
                Boolean(attention, "onAbortedOrError", true),
                Boolean(attention, "onSettled")),
            AgentNotifications = new AgentNotificationSettings(
                Boolean(notices, "enabled"),
                Text(notices, "permission", "text"),
                Text(notices, "mode", "focus"),
                Integer(notices, "durationSeconds", 12),
                Text(notices, "color", "#FF7C3AED"),
                Text(notices, "glowPreset", "violet"),
                Text(notices, "intensity", "balanced")),
            Separator = Text(document, "separator", "dot"),
            Position = Text(document, "position", "top-right"),
            CustomLeft = NullableNumber(document, "customLeft"),
            CustomTop = NullableNumber(document, "customTop"),
            FontSize = Number(document, "fontSize", 14),
            CornerRadius = Number(document, "cornerRadius", 22),
            Opacity = Number(document, "opacity", 0.97),
            TransparencyMode = Text(document, "transparencyMode", "uniform"),
            Scale = Number(document, "scale", 1),
            AlwaysOnTop = Boolean(document, "alwaysOnTop", true),
            MousePassthrough = Boolean(document, "mousePassthrough"),
            ShowStatusDot = Boolean(document, "showStatusDot", true),
            AnimateUpdates = Boolean(document, "animateUpdates", true),
            ThemeStyle = new ThemeStyleSettings(
                Text(theme, "surface", "solid"),
                Text(theme, "gradientStart"),
                Text(theme, "gradientEnd"),
                Number(theme, "gradientAngle", 135),
                Text(theme, "backgroundImage"),
                Number(theme, "imageOpacity", 0.28),
                Text(theme, "imageStretch", "uniformToFill"),
                Text(theme, "shadow", "soft"),
                Number(theme, "borderWidth", 1),
                Number(theme, "statusDotSize", 8),
                Text(theme, "fontFamily", "Segoe UI Variable Text, Microsoft YaHei UI")),
            StatusColors = StringDictionary(Object(document, "statusColors")),
            StatusTiming = new StatusTimingSettings(
                Number(timing, "activeSeconds", 12),
                Number(timing, "idleSeconds", 90),
                Number(timing, "errorHoldSeconds", 30),
                Number(timing, "terminalHoldSeconds", 120),
                Text(timing, "terminalExitMode", "gentle")),
            Background = Text(document, "background", "#EAF7F8FA"),
            Foreground = Text(document, "foreground", "#FF111827"),
            Muted = Text(document, "muted", "#FF667085"),
            Accent = Text(document, "accent", "#FF0A84FF"),
            Border = Text(document, "border", "#33FFFFFF"),
            PricingPath = Text(Object(document, "pricing"), "path"),
            Fields = BoolDictionary(Object(document, "fields"))
        };
    }

    public HudRuntimeOptions ToRuntimeOptions() => new()
    {
        ActiveWindowMinutes = ActiveWindowMinutes,
        MaximumFiles = 64,
        DesktopSessionsEnabled = SessionSources.Desktop,
        VsCodeSessionsEnabled = SessionSources.VsCode,
        DefaultCliSessionsEnabled = SessionSources.DefaultCli,
        DeepSeekCliSessionsEnabled = SessionSources.DeepSeekCli,
        NumberCooldownSeconds = MultiTask.NumberCooldownSeconds,
        CompletionGraceSeconds = Attention.CompletionGraceSeconds,
        AttentionDurationSeconds = Attention.DurationSeconds,
        AttentionOnCompleted = Attention.OnCompleted,
        AttentionOnAbortedOrError = Attention.OnAbortedOrError,
        AttentionOnSettled = Attention.OnSettled,
        AttentionDotEnabled = Attention.DotEnabled,
        AnyAttentionSurfaceEnabled = Attention.SummaryMode != "off" || Attention.ListMode != "off" || Attention.TaskBubbleMode != "off",
        ContextAlertsEnabled = Behavior.ContextAlertsEnabled && Fields.TryGetValue("context", out var contextVisible) && contextVisible,
        ContextThresholds = Behavior.ContextThresholds,
        ActiveSeconds = StatusTiming.ActiveSeconds,
        IdleSeconds = StatusTiming.IdleSeconds,
        ErrorHoldSeconds = StatusTiming.ErrorHoldSeconds,
        TerminalHoldSeconds = StatusTiming.TerminalHoldSeconds,
        TerminalExitMode = StatusTiming.TerminalExitMode
    };

    private static MetricFieldSettings MetricFields(JsonObject node) => new(
        Boolean(node, "model"),
        Boolean(node, "callTotal"),
        Boolean(node, "cacheHitRate"),
        Boolean(node, "taskTotal"),
        Boolean(node, "estimatedCost"),
        Boolean(node, "updated"));

    private static JsonObject Object(JsonObject node, string name) => node[name] as JsonObject ?? new JsonObject();
    private static JsonArray Array(JsonObject node, string name) => node[name] as JsonArray ?? new JsonArray();
    private static string Text(JsonObject node, string name, string fallback = "") => node[name]?.GetValue<string>() ?? fallback;
    private static bool Boolean(JsonObject node, string name, bool fallback = false) => node[name]?.GetValue<bool>() ?? fallback;
    private static int Integer(JsonObject node, string name, int fallback = 0)
    {
        var number = Number(node[name], double.NaN);
        return double.IsFinite(number) && number >= int.MinValue && number <= int.MaxValue
            ? (int)Math.Round(number)
            : fallback;
    }

    private static double Number(JsonObject node, string name, double fallback = 0) => Number(node[name], fallback);

    private static double Number(JsonNode? node, double fallback)
    {
        if (node is not JsonValue value)
        {
            return fallback;
        }
        if (value.TryGetValue<double>(out var number))
        {
            return double.IsFinite(number) ? number : fallback;
        }
        if (value.TryGetValue<int>(out var integer))
        {
            return integer;
        }
        if (value.TryGetValue<long>(out var longInteger))
        {
            return longInteger;
        }
        if (value.TryGetValue<decimal>(out var decimalNumber))
        {
            number = (double)decimalNumber;
            return double.IsFinite(number) ? number : fallback;
        }
        return fallback;
    }

    private static double? NullableNumber(JsonObject node, string name)
    {
        var number = Number(node[name], double.NaN);
        return double.IsFinite(number) ? number : null;
    }

    private static IReadOnlyDictionary<string, bool> BoolDictionary(JsonObject node) =>
        node.ToDictionary(
            static pair => pair.Key,
            static pair => pair.Value?.GetValue<bool>() ?? false,
            StringComparer.Ordinal);

    private static IReadOnlyDictionary<string, string> StringDictionary(JsonObject node) =>
        node.ToDictionary(
            static pair => pair.Key,
            static pair => pair.Value?.GetValue<string>() ?? string.Empty,
            StringComparer.Ordinal);
}
