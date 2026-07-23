using System.Globalization;
using CodexMonitorHud.Core.Models;

namespace CodexMonitorHud.Core.Presentation;

public static class HudFormatting
{
    private static readonly CultureInfo English = CultureInfo.GetCultureInfo("en-US");

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
            ["uncached"] = FormatNumber(snapshot.Uncached, numberFormat),
            ["output"] = FormatNumber(snapshot.Output, numberFormat),
            ["reasoning"] = FormatNumber(snapshot.Reasoning, numberFormat),
            ["callTotal"] = FormatNumber(snapshot.CallTotal, numberFormat),
            ["taskTotal"] = FormatNumber(snapshot.TaskTotal, numberFormat),
            ["context"] = snapshot.ContextPercent.ToString("0.#", English) + "%",
            ["model"] = string.IsNullOrWhiteSpace(snapshot.Model) ? "-" : snapshot.Model,
            ["updated"] = snapshot.Timestamp.ToString("HH:mm:ss", CultureInfo.InvariantCulture),
            ["activeTasks"] = FormatNumber(snapshot.ActiveTasks, numberFormat),
            ["weeklyRemaining"] = snapshot.WeeklyRemainingPercent.HasValue
                ? snapshot.WeeklyRemainingPercent.Value.ToString("0.#", English) + "%"
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
}
