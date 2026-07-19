namespace CodexMonitorHud.Core.Models;

public sealed record HudSnapshot
{
    public DateTimeOffset Timestamp { get; init; }
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
    public string Model { get; init; } = string.Empty;
    public string Workspace { get; init; } = string.Empty;
    public int ActiveTasks { get; init; } = 1;
    public DateTimeOffset? AllowanceTimestamp { get; init; }
    public double? WeeklyRemainingPercent { get; init; }
    public double? FiveHourRemainingPercent { get; init; }
    public double? EstimatedCostUsd { get; init; }
    public string TerminalStatus { get; init; } = string.Empty;
    public DateTimeOffset? TerminalTimestamp { get; init; }
    public bool TerminalSilent { get; init; }

    public bool AccountingIsValid =>
        Cached + Uncached == Input && Input + Output == CallTotal;

    public static HudSnapshot FromUsage(HudRecord usage) => new()
    {
        Timestamp = usage.Timestamp,
        Input = usage.Input,
        Cached = usage.Cached,
        Uncached = usage.Uncached,
        Output = usage.Output,
        Reasoning = usage.Reasoning,
        TaskInput = usage.TaskInput,
        TaskCached = usage.TaskCached,
        TaskUncached = usage.TaskUncached,
        TaskOutput = usage.TaskOutput,
        CallTotal = usage.CallTotal,
        TaskTotal = usage.TaskTotal,
        ContextPercent = usage.ContextPercent,
        ContextWindow = usage.ContextWindow,
        Model = usage.Model,
        AllowanceTimestamp = usage.AllowanceTimestamp,
        WeeklyRemainingPercent = usage.WeeklyRemainingPercent,
        FiveHourRemainingPercent = usage.FiveHourRemainingPercent
    };
}
