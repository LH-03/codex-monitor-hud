using CodexMonitorHud.Core.Models;

namespace CodexMonitorHud.Core.State;

public static class SnapshotAggregator
{
    public static HudSnapshot? Merge(IEnumerable<HudSnapshot?> snapshots, string summaryTemplate)
    {
        var valid = snapshots.OfType<HudSnapshot>().ToArray();
        if (valid.Length == 0)
        {
            return null;
        }

        if (valid.Length == 1)
        {
            return valid[0] with { ActiveTasks = 1 };
        }

        var modelCount = valid
            .Select(static snapshot => snapshot.Model)
            .Where(static model => !string.IsNullOrWhiteSpace(model))
            .Distinct(StringComparer.Ordinal)
            .Count();
        var summary = summaryTemplate
            .Replace("{tasks}", valid.Length.ToString(), StringComparison.Ordinal)
            .Replace("{models}", modelCount.ToString(), StringComparison.Ordinal);
        var allowance = GetLatestAllowance(valid);
        var allCostsAvailable = valid.All(static snapshot => snapshot.EstimatedCostUsd.HasValue);

        return new HudSnapshot
        {
            Timestamp = valid.Max(static snapshot => snapshot.Timestamp),
            Input = valid.Sum(static snapshot => snapshot.Input),
            Cached = valid.Sum(static snapshot => snapshot.Cached),
            Uncached = valid.Sum(static snapshot => snapshot.Uncached),
            Output = valid.Sum(static snapshot => snapshot.Output),
            Reasoning = valid.Sum(static snapshot => snapshot.Reasoning),
            TaskInput = valid.Sum(static snapshot => snapshot.TaskInput),
            TaskCached = valid.Sum(static snapshot => snapshot.TaskCached),
            TaskUncached = valid.Sum(static snapshot => snapshot.TaskUncached),
            TaskOutput = valid.Sum(static snapshot => snapshot.TaskOutput),
            CallTotal = valid.Sum(static snapshot => snapshot.CallTotal),
            TaskTotal = valid.Sum(static snapshot => snapshot.TaskTotal),
            ContextPercent = valid.Max(static snapshot => snapshot.ContextPercent),
            ContextWindow = valid.Sum(static snapshot => snapshot.ContextWindow),
            Model = summary,
            ActiveTasks = valid.Length,
            AllowanceTimestamp = allowance?.AllowanceTimestamp,
            WeeklyRemainingPercent = allowance?.WeeklyRemainingPercent,
            FiveHourRemainingPercent = allowance?.FiveHourRemainingPercent,
            EstimatedCostUsd = allCostsAvailable
                ? valid.Sum(static snapshot => snapshot.EstimatedCostUsd!.Value)
                : null
        };
    }

    public static HudSnapshot? GetLatestAllowance(IEnumerable<HudSnapshot?> snapshots)
    {
        var observed = snapshots
            .OfType<HudSnapshot>()
            .Where(static snapshot =>
                snapshot.WeeklyRemainingPercent.HasValue || snapshot.FiveHourRemainingPercent.HasValue)
            .OrderByDescending(static snapshot => snapshot.AllowanceTimestamp ?? snapshot.Timestamp)
            .ToArray();
        if (observed.Length == 0)
        {
            return null;
        }

        var latest = observed[0];
        var weekly = observed.FirstOrDefault(static snapshot => snapshot.WeeklyRemainingPercent.HasValue);
        var fiveHour = observed.FirstOrDefault(static snapshot => snapshot.FiveHourRemainingPercent.HasValue);
        return latest with
        {
            WeeklyRemainingPercent = weekly?.WeeklyRemainingPercent,
            FiveHourRemainingPercent = fiveHour?.FiveHourRemainingPercent
        };
    }
}
