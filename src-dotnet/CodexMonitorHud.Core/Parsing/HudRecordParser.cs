using System.Globalization;
using System.Text.Json;
using CodexMonitorHud.Core.Models;

namespace CodexMonitorHud.Core.Parsing;

public static class HudRecordParser
{
    private const int PrefixLimit = 64 * 1024;

    public static HudRecord? Parse(string? line)
    {
        if (string.IsNullOrWhiteSpace(line))
        {
            return null;
        }

        var prefix = line.AsSpan(0, Math.Min(PrefixLimit, line.Length));
        var isContext = prefix.Contains("\"turn_context\"", StringComparison.Ordinal);
        var isEvent = prefix.Contains("\"event_msg\"", StringComparison.Ordinal);
        var isRelevantEvent = isEvent &&
            (prefix.Contains("\"task_started\"", StringComparison.Ordinal) ||
             prefix.Contains("\"task_complete\"", StringComparison.Ordinal) ||
             prefix.Contains("\"turn_aborted\"", StringComparison.Ordinal) ||
             prefix.Contains("\"token_count\"", StringComparison.Ordinal));
        if (!isContext && !isRelevantEvent)
        {
            return null;
        }

        try
        {
            using var document = JsonDocument.Parse(line);
            var root = document.RootElement;
            if (!TryGetString(root, "type", out var topLevelType) ||
                !root.TryGetProperty("payload", out var payload))
            {
                return null;
            }

            if (topLevelType == "turn_context")
            {
                var cwd = GetString(payload, "cwd");
                return new HudRecord
                {
                    Kind = HudRecordKind.Context,
                    Model = GetString(payload, "model"),
                    Workspace = GetPortableLeafName(cwd)
                };
            }

            if (topLevelType != "event_msg" || !TryGetString(payload, "type", out var eventType))
            {
                return null;
            }

            if (eventType is "task_started" or "task_complete" or "turn_aborted")
            {
                var timestamp = ParseTimestampOrNow(root);
                var kind = eventType switch
                {
                    "task_started" => HudRecordKind.Started,
                    "turn_aborted" => HudRecordKind.Aborted,
                    _ => string.IsNullOrWhiteSpace(GetString(payload, "last_agent_message"))
                        ? HudRecordKind.CompletedSilent
                        : HudRecordKind.Completed
                };
                return new HudRecord
                {
                    Kind = kind,
                    Timestamp = timestamp,
                    TurnId = GetString(payload, "turn_id")
                };
            }

            if (eventType != "token_count")
            {
                return null;
            }

            // Codex accounting is still useful when a writer emits a
            // temporarily malformed or newly formatted timestamp.  Use the
            // observation time rather than dropping an otherwise complete
            // token_count record and leaving the HUD stuck on "waiting".
            var usageTimestamp = TryParseTimestamp(root, out var parsedUsageTimestamp)
                ? parsedUsageTimestamp
                : DateTimeOffset.Now;

            var (weeklyRemaining, fiveHourRemaining) = ParseAllowances(payload);
            var hasAllowance = weeklyRemaining.HasValue || fiveHourRemaining.HasValue;
            if (!payload.TryGetProperty("info", out var info) ||
                !info.TryGetProperty("last_token_usage", out var last) ||
                last.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined ||
                !info.TryGetProperty("total_token_usage", out var total) ||
                total.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
            {
                return hasAllowance
                    ? NewAllowance(usageTimestamp, weeklyRemaining, fiveHourRemaining)
                    : null;
            }

            var input = GetInt64(last, "input_tokens");
            var cached = GetInt64(last, "cached_input_tokens");
            var output = GetInt64(last, "output_tokens");
            if (input == 0 && output == 0)
            {
                return hasAllowance
                    ? NewAllowance(usageTimestamp, weeklyRemaining, fiveHourRemaining)
                    : null;
            }

            var taskInput = GetInt64(total, "input_tokens", input);
            var taskCached = GetInt64(total, "cached_input_tokens", cached);
            var taskOutput = GetInt64(total, "output_tokens", output);
            var contextWindow = GetInt64(info, "model_context_window");
            var contextPercent = contextWindow > 0
                ? Math.Min(100, input * 100.0 / contextWindow)
                : 0;

            return new HudRecord
            {
                Kind = HudRecordKind.Usage,
                Timestamp = usageTimestamp,
                Input = input,
                Cached = cached,
                Uncached = Math.Max(0, input - cached),
                Output = output,
                Reasoning = GetInt64(last, "reasoning_output_tokens"),
                TaskInput = taskInput,
                TaskCached = taskCached,
                TaskUncached = Math.Max(0, taskInput - taskCached),
                TaskOutput = taskOutput,
                CallTotal = input + output,
                TaskTotal = GetInt64(total, "total_tokens"),
                ContextPercent = contextPercent,
                ContextWindow = contextWindow,
                AllowanceTimestamp = hasAllowance ? usageTimestamp : null,
                WeeklyRemainingPercent = weeklyRemaining,
                FiveHourRemainingPercent = fiveHourRemaining
            };
        }
        catch (JsonException)
        {
            return null;
        }
        catch (InvalidOperationException)
        {
            return null;
        }
        catch (FormatException)
        {
            return null;
        }
        catch (OverflowException)
        {
            return null;
        }
    }

    private static HudRecord NewAllowance(
        DateTimeOffset timestamp,
        double? weeklyRemaining,
        double? fiveHourRemaining) => new()
    {
        Kind = HudRecordKind.Allowance,
        Timestamp = timestamp,
        AllowanceTimestamp = timestamp,
        WeeklyRemainingPercent = weeklyRemaining,
        FiveHourRemainingPercent = fiveHourRemaining
    };

    private static (double? Weekly, double? FiveHour) ParseAllowances(JsonElement payload)
    {
        // `rate_limits` is optional and the live writer may emit it as null
        // while the account window is being refreshed.  It is enrichment only:
        // a missing/empty value must never discard the accompanying usage.
        if (payload.ValueKind != JsonValueKind.Object ||
            !payload.TryGetProperty("rate_limits", out var rateLimits) ||
            rateLimits.ValueKind != JsonValueKind.Object)
        {
            return (null, null);
        }

        double? weekly = null;
        double? fiveHour = null;
        foreach (var windowName in new[] { "primary", "secondary" })
        {
            if (!rateLimits.TryGetProperty(windowName, out var window) ||
                window.ValueKind != JsonValueKind.Object ||
                !TryGetDouble(window, "used_percent", out var usedPercent) ||
                !TryGetInt32(window, "window_minutes", out var windowMinutes))
            {
                continue;
            }

            var remaining = Math.Clamp(Math.Round(100.0 - usedPercent, 1), 0, 100);
            if (windowMinutes >= 10_080)
            {
                weekly = remaining;
            }
            else if (windowMinutes is >= 240 and <= 360)
            {
                fiveHour = remaining;
            }
        }

        return (weekly, fiveHour);
    }

    private static string GetPortableLeafName(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return string.Empty;
        }

        var trimmed = path.TrimEnd('\\', '/');
        var separator = Math.Max(trimmed.LastIndexOf('\\'), trimmed.LastIndexOf('/'));
        return separator >= 0 && separator < trimmed.Length - 1
            ? trimmed[(separator + 1)..]
            : trimmed;
    }

    private static DateTimeOffset ParseTimestampOrNow(JsonElement root) =>
        TryParseTimestamp(root, out var timestamp) ? timestamp : DateTimeOffset.Now;

    private static bool TryParseTimestamp(JsonElement root, out DateTimeOffset timestamp)
    {
        timestamp = default;
        return TryGetString(root, "timestamp", out var raw) &&
               DateTimeOffset.TryParse(
                   raw,
                   CultureInfo.InvariantCulture,
                   DateTimeStyles.AllowWhiteSpaces | DateTimeStyles.AssumeUniversal,
                   out timestamp) &&
               (timestamp = timestamp.ToLocalTime()) != default;
    }

    private static string GetString(JsonElement element, string name) =>
        TryGetString(element, name, out var value) ? value : string.Empty;

    private static bool TryGetString(JsonElement element, string name, out string value)
    {
        value = string.Empty;
        if (!element.TryGetProperty(name, out var property) || property.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        value = property.GetString() ?? string.Empty;
        return true;
    }

    private static long GetInt64(JsonElement element, string name, long fallback = 0)
    {
        if (!element.TryGetProperty(name, out var property))
        {
            return fallback;
        }

        if (property.ValueKind == JsonValueKind.Number && property.TryGetInt64(out var number))
        {
            return number;
        }

        return property.ValueKind == JsonValueKind.String &&
               long.TryParse(property.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out number)
            ? number
            : fallback;
    }

    private static bool TryGetInt32(JsonElement element, string name, out int value)
    {
        value = 0;
        return element.TryGetProperty(name, out var property) &&
               ((property.ValueKind == JsonValueKind.Number && property.TryGetInt32(out value)) ||
                (property.ValueKind == JsonValueKind.String &&
                 int.TryParse(property.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out value)));
    }

    private static bool TryGetDouble(JsonElement element, string name, out double value)
    {
        value = 0;
        return element.TryGetProperty(name, out var property) &&
               ((property.ValueKind == JsonValueKind.Number && property.TryGetDouble(out value)) ||
                (property.ValueKind == JsonValueKind.String &&
                 double.TryParse(property.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out value)));
    }
}
