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

        var models = new HashSet<string>(StringComparer.Ordinal);
        var timestamp = valid[0].Timestamp;
        long input = 0, cached = 0, uncached = 0, output = 0, reasoning = 0;
        long taskInput = 0, taskCached = 0, taskUncached = 0, taskOutput = 0;
        long callTotal = 0, taskTotal = 0, contextWindow = 0;
        var contextPercent = valid[0].ContextPercent;
        double? cost = 0;
        foreach (var snapshot in valid)
        {
            if (!string.IsNullOrWhiteSpace(snapshot.Model)) models.Add(snapshot.Model);
            if (snapshot.Timestamp > timestamp) timestamp = snapshot.Timestamp;
            if (snapshot.ContextPercent > contextPercent || double.IsNaN(contextPercent))
                contextPercent = snapshot.ContextPercent;
            // Preserve Enumerable.Sum's overflow behavior for token counters.
            checked
            {
                input += snapshot.Input;
                cached += snapshot.Cached;
                uncached += snapshot.Uncached;
                output += snapshot.Output;
                reasoning += snapshot.Reasoning;
                taskInput += snapshot.TaskInput;
                taskCached += snapshot.TaskCached;
                taskUncached += snapshot.TaskUncached;
                taskOutput += snapshot.TaskOutput;
                callTotal += snapshot.CallTotal;
                taskTotal += snapshot.TaskTotal;
                contextWindow += snapshot.ContextWindow;
            }
            cost += snapshot.EstimatedCostUsd;
        }
        var summary = summaryTemplate
            .Replace("{tasks}", valid.Length.ToString(), StringComparison.Ordinal)
            .Replace("{models}", models.Count.ToString(), StringComparison.Ordinal);
        var allowance = GetLatestAllowance(valid);

        return new HudSnapshot
        {
            Timestamp = timestamp,
            Input = input,
            Cached = cached,
            Uncached = uncached,
            Output = output,
            Reasoning = reasoning,
            TaskInput = taskInput,
            TaskCached = taskCached,
            TaskUncached = taskUncached,
            TaskOutput = taskOutput,
            CallTotal = callTotal,
            TaskTotal = taskTotal,
            ContextPercent = contextPercent,
            ContextWindow = contextWindow,
            Model = summary,
            ActiveTasks = valid.Length,
            AllowanceTimestamp = allowance?.AllowanceTimestamp,
            WeeklyRemainingPercent = allowance?.WeeklyRemainingPercent,
            FiveHourRemainingPercent = allowance?.FiveHourRemainingPercent,
            EstimatedCostUsd = cost
        };
    }

    public static HudSnapshot? GetLatestAllowance(IEnumerable<HudSnapshot?> snapshots)
    {
        HudSnapshot? latest = null, weekly = null, fiveHour = null;
        foreach (var snapshot in snapshots)
        {
            if (snapshot is null) continue;
            var hasWeekly = snapshot.WeeklyRemainingPercent.HasValue;
            var hasFiveHour = snapshot.FiveHourRemainingPercent.HasValue;
            if (!hasWeekly && !hasFiveHour) continue;
            if (IsNewer(snapshot, latest)) latest = snapshot;
            if (hasWeekly && IsNewer(snapshot, weekly)) weekly = snapshot;
            if (hasFiveHour && IsNewer(snapshot, fiveHour)) fiveHour = snapshot;
        }
        if (latest is null) return null;
        return latest with
        {
            WeeklyRemainingPercent = weekly?.WeeklyRemainingPercent,
            FiveHourRemainingPercent = fiveHour?.FiveHourRemainingPercent
        };
    }

    private static bool IsNewer(HudSnapshot candidate, HudSnapshot? previous) =>
        previous is null || (candidate.AllowanceTimestamp ?? candidate.Timestamp) >
                            (previous.AllowanceTimestamp ?? previous.Timestamp);
}
