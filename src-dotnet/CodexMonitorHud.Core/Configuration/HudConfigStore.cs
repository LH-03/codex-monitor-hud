using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using CodexMonitorHud.Core.Models;

namespace CodexMonitorHud.Core.Configuration;

public static partial class HudConfigStore
{
    private static readonly JsonDocumentOptions ReadOptions = new()
    {
        AllowTrailingCommas = true,
        CommentHandling = JsonCommentHandling.Skip
    };

    private static readonly JsonSerializerOptions WriteOptions = new()
    {
        WriteIndented = true
    };

    public static JsonObject Load(HudPaths paths)
    {
        var defaults = ParseObject(File.ReadAllText(paths.DefaultConfigPath, Encoding.UTF8));
        var result = (JsonObject)defaults.DeepClone();
        if (File.Exists(paths.ConfigPath))
        {
            try
            {
                var saved = ParseObject(File.ReadAllText(paths.ConfigPath, Encoding.UTF8));
                var hadMultiTask = saved["multiTask"] is JsonObject;
                var legacyTaskFields = (saved["multiTask"] as JsonObject)?["taskFields"] as JsonObject;
                var hadBubbleFields = (saved["multiTask"] as JsonObject)?["bubbleFields"] is JsonObject;
                MergeInto(result, saved);
                if (!hadMultiTask)
                {
                    result["monitorScope"] = "aggregate";
                }

                if (!hadBubbleFields && legacyTaskFields is not null)
                {
                    var bubbles = GetObject(result, "multiTask", "bubbleFields");
                    foreach (var field in new[] { "model", "callTotal", "taskTotal", "updated" })
                    {
                        if (legacyTaskFields[field] is JsonValue value && value.TryGetValue<bool>(out var enabled))
                        {
                            bubbles[field] = enabled;
                        }
                    }
                }
            }
            catch (JsonException)
            {
                result = (JsonObject)defaults.DeepClone();
            }
            catch (IOException)
            {
                result = (JsonObject)defaults.DeepClone();
            }
        }

        Normalize(result, paths.LocaleRoot);
        return result;
    }

    public static void Save(HudPaths paths, JsonObject config)
    {
        Directory.CreateDirectory(paths.StateRoot);
        var temporary = paths.ConfigPath + $".{Environment.ProcessId}.{Guid.NewGuid():N}.tmp";
        try
        {
            File.WriteAllText(temporary, config.ToJsonString(WriteOptions), new UTF8Encoding(false));
            File.Move(temporary, paths.ConfigPath, overwrite: true);
        }
        finally
        {
            try { File.Delete(temporary); } catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    public static JsonObject Merge(JsonObject defaults, JsonObject saved)
    {
        var result = (JsonObject)defaults.DeepClone();
        MergeInto(result, saved);
        return result;
    }

    public static void Normalize(JsonObject result, string localeRoot)
    {
        SetAllowed(result, "summary", new[] { "summary", "list", "split" }, "multiTask", "displayMode");
        SetBool(result, GetBool(result, true, "sessionSources", "desktop"), "sessionSources", "desktop");
        SetBool(result, GetBool(result, true, "sessionSources", "vscode"), "sessionSources", "vscode");
        SetBool(result, GetBool(result, true, "sessionSources", "defaultCli"), "sessionSources", "defaultCli");
        SetBool(result, GetBool(result, true, "sessionSources", "deepSeekCli"), "sessionSources", "deepSeekCli");
        SetAllowed(result, "rows", new[] { "rows", "cards", "rail" }, "multiTask", "listStyle");
        SetAllowed(result, "compact", new[] { "compact", "balanced", "relaxed" }, "multiTask", "listDensity");
        SetAllowed(result, "balanced", new[] { "compact", "balanced", "detailed" }, "multiTask", "listDetail");
        // "hover" was the old default. Normalize it to "always" so existing
        // installations gain an immediately readable conversation subtitle.
        SetAllowed(result, "always", new[] { "always", "hidden" }, "multiTask", "nameMode");
        SetInt(result, Math.Clamp(GetInt(result, 6, "multiTask", "maxSplitBubbles"), 1, 12), "multiTask", "maxSplitBubbles");
        SetInt(result, Math.Clamp(GetInt(result, 120, "multiTask", "numberCooldownSeconds"), 0, 3600), "multiTask", "numberCooldownSeconds");

        var language = GetString(result, "en", "language");
        if (language is not ("zh-CN" or "en" or "symbols") &&
            !File.Exists(Path.Combine(localeRoot, language + ".json")))
        {
            result["language"] = "en";
        }

        SetBool(result, GetBool(result, false, "behavior", "openTaskOnDoubleClick"), "behavior", "openTaskOnDoubleClick");
        SetBool(result, GetBool(result, false, "behavior", "idleIndicator", "enabled"), "behavior", "idleIndicator", "enabled");
        SetBool(result, GetBool(result, true, "behavior", "idleIndicator", "includeTaskBubbles"), "behavior", "idleIndicator", "includeTaskBubbles");
        SetDouble(result, Math.Clamp(GetDouble(result, 15, "behavior", "idleIndicator", "afterMinutes"), 0.01, 1440), "behavior", "idleIndicator", "afterMinutes");
        SetAllowed(result, "overall", new[] { "overall", "horizontal", "vertical" }, "behavior", "idleIndicator", "layout");
        SetAllowed(result, "dot", new[] { "dot", "bar" }, "behavior", "idleIndicator", "taskStyle");
        var contextEnabled = GetBool(result, false, "behavior", "contextAlerts", "enabled") &&
                             GetBool(result, false, "fields", "context");
        SetBool(result, contextEnabled, "behavior", "contextAlerts", "enabled");
        SetThresholds(result);

        foreach (var property in new[] { "summaryMode", "listMode", "taskBubbleMode" })
        {
            var mode = GetString(result, string.Empty, "attention", property);
            if (mode == "dot")
            {
                SetString(result, "off", "attention", property);
                SetBool(result, true, "attention", "dotEnabled");
            }
            else if (mode == "bubble")
            {
                SetString(result, "breathe", "attention", property);
            }
            else if (mode is not ("off" or "halo" or "breathe" or "flow" or "focus"))
            {
                SetString(result, property == "summaryMode" ? "halo" : "flow", "attention", property);
            }
        }

        SetAllowed(result, "heartbeat", new[] { "soft", "heartbeat", "beacon" }, "attention", "dotPattern");
        SetAllowed(result, "balanced", new[] { "subtle", "balanced", "bright" }, "attention", "dotBrightness");
        SetAllowed(result, "normal", new[] { "slow", "normal", "fast" }, "attention", "dotSpeed");
        SetBool(result, GetBool(result, true, "attention", "dotEnabled"), "attention", "dotEnabled");
        SetBool(result, GetBool(result, true, "attention", "dotBreathing"), "attention", "dotBreathing");
        SetInt(result, Math.Clamp(GetInt(result, 6, "attention", "durationSeconds"), 2, 15), "attention", "durationSeconds");
        SetInt(result, Math.Clamp(GetInt(result, 8, "attention", "completionGraceSeconds"), 0, 30), "attention", "completionGraceSeconds");

        SetAllowed(result, "text", new[] { "text", "expressive" }, "agentNotifications", "permission");
        SetAllowed(result, "focus", new[] { "halo", "breathe", "flow", "focus" }, "agentNotifications", "mode");
        SetAllowed(result, "violet", new[] { "violet", "aqua", "amber", "custom" }, "agentNotifications", "glowPreset");
        SetAllowed(result, "balanced", new[] { "subtle", "balanced", "strong" }, "agentNotifications", "intensity");
        SetBool(result, GetBool(result, false, "agentNotifications", "enabled"), "agentNotifications", "enabled");
        SetInt(result, Math.Clamp(GetInt(result, 12, "agentNotifications", "durationSeconds"), 4, 60), "agentNotifications", "durationSeconds");
        var noticeColor = GetString(result, "#FF7C3AED", "agentNotifications", "color");
        if (!HexColorRegex().IsMatch(noticeColor))
        {
            SetString(result, "#FF7C3AED", "agentNotifications", "color");
        }

        SetBool(result, GetBool(result, false, "quotaGuard", "enabled"), "quotaGuard", "enabled");
        var prepareFiveHour = Math.Clamp(GetInt(result, 15, "quotaGuard", "prepareFiveHourPercent"), 1, 99);
        var prepareWeekly = Math.Clamp(GetInt(result, 10, "quotaGuard", "prepareWeeklyPercent"), 1, 99);
        var handoffFiveHour = Math.Min(Math.Clamp(GetInt(result, 5, "quotaGuard", "handoffFiveHourPercent"), 1, 99), prepareFiveHour);
        var handoffWeekly = Math.Min(Math.Clamp(GetInt(result, 3, "quotaGuard", "handoffWeeklyPercent"), 1, 99), prepareWeekly);
        SetInt(result, prepareFiveHour, "quotaGuard", "prepareFiveHourPercent");
        SetInt(result, prepareWeekly, "quotaGuard", "prepareWeeklyPercent");
        SetInt(result, handoffFiveHour, "quotaGuard", "handoffFiveHourPercent");
        SetInt(result, handoffWeekly, "quotaGuard", "handoffWeeklyPercent");
        SetString(result, Trim(GetString(result, string.Empty, "quotaGuard", "prepareInstruction"), 1200), "quotaGuard", "prepareInstruction");
        SetString(result, Trim(GetString(result, string.Empty, "quotaGuard", "handoffInstruction"), 1200), "quotaGuard", "handoffInstruction");
        SetBool(result, GetBool(result, false, "officialAllowance", "enabled"), "officialAllowance", "enabled");

        SetAllowed(result, "uniform", new[] { "uniform", "layered", "focus" }, "transparencyMode");
        SetDouble(result, Math.Clamp(GetDouble(result, 0.97, "opacity"), 0, 1), "opacity");
        SetAllowed(result, "solid", new[] { "solid", "gradient", "image" }, "themeStyle", "surface");
        SetAllowed(result, "uniformToFill", new[] { "uniform", "uniformToFill", "fill", "none" }, "themeStyle", "imageStretch");
        SetAllowed(result, "soft", new[] { "none", "soft", "deep" }, "themeStyle", "shadow");
        var angle = GetDouble(result, 135, "themeStyle", "gradientAngle");
        SetDouble(result, (angle % 360 + 360) % 360, "themeStyle", "gradientAngle");
        SetDouble(result, Math.Clamp(GetDouble(result, 0.28, "themeStyle", "imageOpacity"), 0.05, 1), "themeStyle", "imageOpacity");
        SetDouble(result, Math.Clamp(GetDouble(result, 1, "themeStyle", "borderWidth"), 0, 4), "themeStyle", "borderWidth");
        SetDouble(result, Math.Clamp(GetDouble(result, 8, "themeStyle", "statusDotSize"), 5, 18), "themeStyle", "statusDotSize");
        if (string.IsNullOrWhiteSpace(GetString(result, string.Empty, "themeStyle", "fontFamily")))
        {
            SetString(result, "Segoe UI Variable Text, Microsoft YaHei UI", "themeStyle", "fontFamily");
        }

        SetInt(result, Math.Clamp(GetInt(result, 120, "statusTiming", "terminalHoldSeconds"), 0, 1800), "statusTiming", "terminalHoldSeconds");
        SetAllowed(result, "gentle", new[] { "fade", "gentle", "focus", "beacon" }, "statusTiming", "terminalExitMode");
        SetString(result, GetString(result, string.Empty, "pricing", "path"), "pricing", "path");
    }

    private static JsonObject ParseObject(string json) =>
        JsonNode.Parse(json, nodeOptions: null, documentOptions: ReadOptions) as JsonObject ??
        throw new JsonException("HUD configuration root must be an object.");

    private static void MergeInto(JsonObject target, JsonObject saved)
    {
        foreach (var property in saved)
        {
            if (!target.TryGetPropertyValue(property.Key, out var defaultValue) || property.Value is null)
            {
                continue;
            }

            if (defaultValue is JsonObject defaultObject)
            {
                if (property.Value is JsonObject savedObject)
                {
                    MergeInto(defaultObject, savedObject);
                }

                continue;
            }

            if (defaultValue is JsonArray && property.Value is not JsonArray)
            {
                continue;
            }

            if (defaultValue is JsonValue defaultScalar)
            {
                if (property.Value is not JsonValue savedScalar ||
                    !SameScalarKind(defaultScalar.GetValueKind(), savedScalar.GetValueKind()))
                {
                    continue;
                }
            }

            target[property.Key] = property.Value.DeepClone();
        }
    }

    private static bool SameScalarKind(JsonValueKind defaultKind, JsonValueKind savedKind) =>
        defaultKind == savedKind ||
        defaultKind is JsonValueKind.True or JsonValueKind.False &&
        savedKind is JsonValueKind.True or JsonValueKind.False;

    private static void SetThresholds(JsonObject result)
    {
        var node = GetNode(result, "behavior", "contextAlerts", "thresholds") as JsonArray;
        var values = node?
            .Select(static value => value?.ToString())
            .ToArray() ?? Array.Empty<string?>();
        var parsed = Presentation.HudFormatting.ParseContextAlertThresholds(values) ?? new[] { 75, 90, 98 };
        GetObject(result, "behavior", "contextAlerts")["thresholds"] =
            new JsonArray(parsed.Select(static value => JsonValue.Create(value)).ToArray());
    }

    private static void SetAllowed(JsonObject root, string fallback, IEnumerable<string> allowed, params string[] path)
    {
        var value = GetString(root, fallback, path);
        SetString(root, allowed.Contains(value, StringComparer.Ordinal) ? value : fallback, path);
    }

    private static JsonNode? GetNode(JsonObject root, params string[] path)
    {
        JsonNode? current = root;
        foreach (var part in path)
        {
            current = (current as JsonObject)?[part];
            if (current is null)
            {
                return null;
            }
        }

        return current;
    }

    private static JsonObject GetObject(JsonObject root, params string[] path)
    {
        var current = root;
        foreach (var part in path)
        {
            if (current[part] is not JsonObject child)
            {
                child = new JsonObject();
                current[part] = child;
            }

            current = child;
        }

        return current;
    }

    private static void SetNode(JsonObject root, JsonNode? value, params string[] path)
    {
        if (path.Length == 0)
        {
            throw new ArgumentException("A configuration path is required.", nameof(path));
        }

        var parent = GetObject(root, path[..^1]);
        parent[path[^1]] = value;
    }

    private static string GetString(JsonObject root, string fallback, params string[] path)
    {
        var node = GetNode(root, path);
        return node is JsonValue value && value.TryGetValue<string>(out var text) ? text : fallback;
    }

    private static string Trim(string value, int maximum) => value.Length <= maximum ? value : value[..maximum];

    private static int GetInt(JsonObject root, int fallback, params string[] path)
    {
        var node = GetNode(root, path);
        if (node is JsonValue value)
        {
            if (value.TryGetValue<int>(out var integer))
            {
                return integer;
            }

            if (value.TryGetValue<double>(out var number))
            {
                return checked((int)number);
            }
        }

        return fallback;
    }

    private static double GetDouble(JsonObject root, double fallback, params string[] path)
    {
        var node = GetNode(root, path);
        if (node is JsonValue value)
        {
            if (value.TryGetValue<double>(out var number))
            {
                return number;
            }

            if (value.TryGetValue<int>(out var integer))
            {
                return integer;
            }
        }

        return fallback;
    }

    private static bool GetBool(JsonObject root, bool fallback, params string[] path)
    {
        var node = GetNode(root, path);
        return node is JsonValue value && value.TryGetValue<bool>(out var enabled) ? enabled : fallback;
    }

    private static void SetString(JsonObject root, string value, params string[] path) => SetNode(root, JsonValue.Create(value), path);
    private static void SetInt(JsonObject root, int value, params string[] path) => SetNode(root, JsonValue.Create(value), path);
    private static void SetDouble(JsonObject root, double value, params string[] path) => SetNode(root, JsonValue.Create(value), path);
    private static void SetBool(JsonObject root, bool value, params string[] path) => SetNode(root, JsonValue.Create(value), path);

    [GeneratedRegex("^#[0-9A-Fa-f]{8}$", RegexOptions.CultureInvariant)]
    private static partial Regex HexColorRegex();
}
