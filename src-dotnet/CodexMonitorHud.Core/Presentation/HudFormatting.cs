using System.Globalization;
using CodexMonitorHud.Core.Models;

namespace CodexMonitorHud.Core.Presentation;

public static class HudFormatting
{
    private static readonly CultureInfo English = CultureInfo.GetCultureInfo("en-US");
    private static readonly HashSet<string> SummaryMetricKeys = new(StringComparer.Ordinal)
    {
        "input",
        "cached",
        "uncached",
        "output",
        "reasoning",
        "callTotal",
        "activeTasks",
        "weeklyRemaining",
        "fiveHourRemaining",
        "estimatedCost"
    };

    public static string FormatNumber(long value, string mode = "exact")
    {
        if (mode == "exact" || mode == "auto" && Math.Abs((double)value) < 1_000_000)
        {
            return value.ToString("N0", English);
        }

        var absolute = Math.Abs((double)value);
        return absolute switch
        {
            >= 1_000_000_000 => (value / 1_000_000_000.0).ToString("0.#", English) + "B",
            >= 1_000_000 => (value / 1_000_000.0).ToString("0.#", English) + "M",
            >= 1_000 => (value / 1_000.0).ToString("0.#", English) + "K",
            _ => value.ToString(CultureInfo.InvariantCulture)
        };
    }

    public static string FormatCost(double? value)
    {
        if (!value.HasValue)
        {
            return "--";
        }

        var format = value.Value switch
        {
            < 0.01 => "0.0000",
            < 1 => "0.000",
            _ => "0.00"
        };
        return "~$" + value.Value.ToString(format, CultureInfo.InvariantCulture);
    }

    public static string FormatCacheHitRate(long input, long cached)
    {
        if (input <= 0)
        {
            return "--";
        }

        var boundedCached = Math.Clamp(cached, 0, input);
        return FormatPercent(boundedCached * 100.0 / input);
    }

    public static string FormatPercent(double value)
    {
        if (!double.IsFinite(value))
        {
            return "--";
        }

        var bounded = Math.Clamp(value, 0, 100);
        var rounded = Math.Round(bounded, 1, MidpointRounding.AwayFromZero);
        if (bounded is > 0 and < 100 && rounded >= 100)
        {
            // A rounded 100% falsely implies a perfect hit/full-context state.
            // Truncate to two decimals only at the upper boundary so the HUD
            // stays compact while preserving the important distinction.
            var belowBoundary = Math.Floor(bounded * 100) / 100;
            return belowBoundary.ToString("0.##", English) + "%";
        }

        if (bounded > 0 && rounded == 0)
        {
            return "<0.1%";
        }

        return rounded.ToString("0.#", English) + "%";
    }

    public static int GetContextAlertLevel(double contextPercent, IEnumerable<double> thresholds)
    {
        var level = thresholds.Order().Count(threshold => contextPercent >= threshold);
        return Math.Min(3, level);
    }

    public static IReadOnlyList<int>? ParseContextAlertThresholds(IEnumerable<string?> values)
    {
        var thresholds = new SortedSet<int>();
        foreach (var raw in values)
        {
            var text = (raw ?? string.Empty).Trim().TrimEnd('%').Trim();
            if (text.Length == 0)
            {
                continue;
            }

            if (!int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) ||
                value is < 1 or > 99)
            {
                return null;
            }

            thresholds.Add(value);
        }

        return thresholds.Count is >= 1 and <= 3 ? thresholds.ToArray() : null;
    }

    public static string? GetTaskDeepLink(string? sessionId)
    {
        if (string.IsNullOrWhiteSpace(sessionId) ||
            sessionId.Any(static character =>
                !(char.IsLetterOrDigit(character) || character is '.' or '_' or '-')))
        {
            return null;
        }

        return "codex://threads/" + Uri.EscapeDataString(sessionId);
    }

    public static IReadOnlyList<HudMetric> GetMetrics(
        HudSnapshot snapshot,
        IReadOnlyDictionary<string, bool> fields,
        IReadOnlyDictionary<string, string> locale,
        string numberFormat)
    {
        var values = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["input"] = FormatNumber(snapshot.Input, numberFormat),
            ["cached"] = FormatNumber(snapshot.Cached, numberFormat),
            ["cacheHitRate"] = FormatCacheHitRate(snapshot.Input, snapshot.Cached),
            ["uncached"] = FormatNumber(snapshot.Uncached, numberFormat),
            ["output"] = FormatNumber(snapshot.Output, numberFormat),
            ["reasoning"] = FormatNumber(snapshot.Reasoning, numberFormat),
            ["callTotal"] = FormatNumber(snapshot.CallTotal, numberFormat),
            ["taskTotal"] = FormatNumber(snapshot.TaskTotal, numberFormat),
            ["context"] = snapshot.ContextWindow > 0 ? FormatPercent(snapshot.ContextPercent) : "--",
            ["model"] = string.IsNullOrWhiteSpace(snapshot.Model) ? "-" : snapshot.Model,
            ["updated"] = snapshot.Timestamp.ToString("HH:mm:ss", CultureInfo.InvariantCulture),
            ["activeTasks"] = FormatNumber(snapshot.ActiveTasks, numberFormat),
            ["weeklyRemaining"] = snapshot.WeeklyRemainingPercent.HasValue
                ? FormatPercent(snapshot.WeeklyRemainingPercent.Value)
                : "--",
            ["fiveHourRemaining"] = snapshot.FiveHourRemainingPercent.HasValue
                ? FormatPercent(snapshot.FiveHourRemainingPercent.Value)
                : "--",
            ["estimatedCost"] = FormatCost(snapshot.EstimatedCostUsd)
        };

        var metrics = new List<HudMetric>();
        foreach (var (key, value) in values)
        {
            if (fields.TryGetValue(key, out var visible) && visible)
            {
                metrics.Add(new HudMetric(
                    key,
                    locale.TryGetValue(key, out var label) ? label : key,
                    value));
            }
        }

        return metrics;
    }

    public static IReadOnlyList<HudMetric> GetSummaryMetrics(
        HudSnapshot snapshot,
        IReadOnlyDictionary<string, bool> fields,
        IReadOnlyDictionary<string, string> locale,
        string numberFormat) =>
        GetMetrics(snapshot, fields, locale, numberFormat)
            .Where(metric => SummaryMetricKeys.Contains(metric.Key))
            .ToArray();

    public static TaskListMetricSet GetTaskListMetrics(
        HudSnapshot snapshot,
        string detail,
        IReadOnlyDictionary<string, string> locale,
        string numberFormat)
    {
        var primary = new List<HudMetric>
        {
            Metric("context", snapshot.ContextWindow > 0 ? FormatPercent(snapshot.ContextPercent) : "--", locale)
        };
        var diagnostics = new List<HudMetric>();

        // The compact tier carries the identity and saturation data an agent
        // operator needs first: status is rendered by the caller, then model
        // and context.  Accounting detail is progressively disclosed below.
        if (!string.IsNullOrWhiteSpace(snapshot.Model))
        {
            primary.Add(Metric("model", snapshot.Model, locale));
        }
        primary.Add(Metric("cacheHitRate", FormatCacheHitRate(snapshot.Input, snapshot.Cached), locale));

        if (detail is "balanced" or "detailed")
        {
            primary.Add(Metric("callTotal", FormatNumber(snapshot.CallTotal, numberFormat), locale));
        }

        if (detail == "detailed")
        {
            diagnostics.Add(Metric("input", FormatNumber(snapshot.Input, numberFormat), locale));
            diagnostics.Add(Metric("cached", FormatNumber(snapshot.Cached, numberFormat), locale));
            diagnostics.Add(Metric("uncached", FormatNumber(snapshot.Uncached, numberFormat), locale));
            diagnostics.Add(Metric("output", FormatNumber(snapshot.Output, numberFormat), locale));
            diagnostics.Add(Metric("taskTotal", FormatNumber(snapshot.TaskTotal, numberFormat), locale));
            diagnostics.Add(Metric(
                "contextWindow",
                snapshot.ContextWindow > 0 ? FormatNumber(snapshot.ContextWindow, numberFormat) : "--",
                locale));
            if (snapshot.Reasoning > 0)
            {
                diagnostics.Add(Metric("reasoning", FormatNumber(snapshot.Reasoning, numberFormat), locale));
            }
            if (snapshot.EstimatedCostUsd.HasValue)
            {
                diagnostics.Add(Metric("estimatedCost", FormatCost(snapshot.EstimatedCostUsd), locale));
            }
            diagnostics.Add(Metric("updated", snapshot.Timestamp.ToString("HH:mm:ss", CultureInfo.InvariantCulture), locale));
        }

        return new TaskListMetricSet(primary, diagnostics);
    }

    private static HudMetric Metric(
        string key,
        string value,
        IReadOnlyDictionary<string, string> locale) =>
        new(key, locale.TryGetValue(key, out var label) ? label : key, value);
}

public sealed record TaskListMetricSet(
    IReadOnlyList<HudMetric> Primary,
    IReadOnlyList<HudMetric> Diagnostics);
