namespace CodexMonitorHud.Core.State;

public sealed record HudRuntimeOptions
{
    public int ActiveWindowMinutes { get; init; } = 30;
    public int MaximumFiles { get; init; } = 64;
    public bool DesktopSessionsEnabled { get; init; } = true;
    public bool VsCodeSessionsEnabled { get; init; } = true;
    public bool DefaultCliSessionsEnabled { get; init; } = true;
    public bool DeepSeekCliSessionsEnabled { get; init; } = true;
    public int NumberCooldownSeconds { get; init; } = 120;
    public int CompletionGraceSeconds { get; init; } = 8;
    public int AttentionDurationSeconds { get; init; } = 6;
    public bool AttentionOnCompleted { get; init; } = true;
    public bool AttentionOnAbortedOrError { get; init; } = true;
    public bool AttentionOnSettled { get; init; }
    public bool AttentionDotEnabled { get; init; } = true;
    public bool AnyAttentionSurfaceEnabled { get; init; } = true;
    public bool ContextAlertsEnabled { get; init; }
    public IReadOnlyList<double> ContextThresholds { get; init; } = new[] { 75d, 90d, 98d };
    public double ActiveSeconds { get; init; } = 12;
    public double IdleSeconds { get; init; } = 90;
    public double ErrorHoldSeconds { get; init; } = 30;
    public double TerminalHoldSeconds { get; init; } = 120;
    public string TerminalExitMode { get; init; } = "gentle";
}
