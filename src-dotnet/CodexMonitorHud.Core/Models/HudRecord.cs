namespace CodexMonitorHud.Core.Models;

public enum HudRecordKind
{
    Context,
    Started,
    Completed,
    CompletedSilent,
    Aborted,
    Usage,
    Allowance
}

public sealed record HudRecord
{
    public required HudRecordKind Kind { get; init; }
    public DateTimeOffset Timestamp { get; init; }
    public string TurnId { get; init; } = string.Empty;
    public string Model { get; init; } = string.Empty;
    public string Workspace { get; init; } = string.Empty;
    public long Input { get; init; }
    public long Cached { get; init; }
    public long Uncached { get; init; }
    public long Output { get; init; }
    public long Reasoning { get; init; }
    public long TaskInput { get; init; }
    public long TaskCached { get; init; }
    public long TaskUncached { get; init; }
    public long TaskOutput { get; init; }
    public long CallTotal { get; init; }
    public long TaskTotal { get; init; }
    public double ContextPercent { get; init; }
    public long ContextWindow { get; init; }
    public DateTimeOffset? AllowanceTimestamp { get; init; }
    public double? WeeklyRemainingPercent { get; init; }
    public double? FiveHourRemainingPercent { get; init; }
}
