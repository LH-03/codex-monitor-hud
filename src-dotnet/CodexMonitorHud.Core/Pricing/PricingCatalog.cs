using System.Text.Json;
using CodexMonitorHud.Core.Models;

namespace CodexMonitorHud.Core.Pricing;

public sealed record PricingRate(double Input, double Cached, double Output, bool Estimated);
public sealed record CostEstimate(double CostUsd, string PricedAs, bool Estimated);

public sealed class PricingCatalog
{
    private readonly Dictionary<string, PricingRate> _models = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> _aliases = new(StringComparer.Ordinal);

    public bool Loaded => _models.Count > 0;
    public required string Path { get; init; }
    public required string Kind { get; init; }
    public string Error { get; private set; } = string.Empty;
    public JsonElement? Source { get; private set; }

    public static PricingCatalog Load(string pluginRoot, string? configuredPath = null)
    {
        var isCustom = !string.IsNullOrWhiteSpace(configuredPath);
        var path = isCustom
            ? Environment.ExpandEnvironmentVariables(configuredPath!.Trim())
            : System.IO.Path.Combine(pluginRoot, "pricing.default.json");
        if (path.StartsWith("~" + System.IO.Path.DirectorySeparatorChar, StringComparison.Ordinal))
        {
            path = System.IO.Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                path[2..]);
        }

        var catalog = new PricingCatalog { Path = path, Kind = isCustom ? "custom" : "built-in" };
        if (!File.Exists(path))
        {
            catalog.Error = "not_found";
            return catalog;
        }

        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            var root = document.RootElement;
            var models = root.TryGetProperty("models", out var modelsNode) ? modelsNode : root;
            foreach (var model in models.EnumerateObject())
            {
                if (model.Name.StartsWith('_') || model.Value.ValueKind == JsonValueKind.Null)
                {
                    continue;
                }

                if (!TryRate(model.Value, "input_per_million", out var input) ||
                    !TryRate(model.Value, "output_per_million", out var output))
                {
                    throw new JsonException($"Missing required rate for {model.Name}.");
                }

                var cached = TryRate(model.Value, "cached_input_per_million", out var cachedRate)
                    ? cachedRate
                    : input;
                if (input < 0 || cached < 0 || output < 0)
                {
                    throw new JsonException($"Negative rate for {model.Name}.");
                }

                var estimated = model.Value.TryGetProperty("estimated", out var estimatedNode) &&
                                estimatedNode.ValueKind is JsonValueKind.True;
                catalog._models[model.Name] = new PricingRate(input, cached, output, estimated);
            }

            if (root.TryGetProperty("aliases", out var aliases))
            {
                foreach (var alias in aliases.EnumerateObject())
                {
                    var target = alias.Value.GetString();
                    if (!string.IsNullOrWhiteSpace(target))
                    {
                        catalog._aliases[alias.Name] = target;
                    }
                }
            }

            if (root.TryGetProperty("_source", out var source))
            {
                catalog.Source = source.Clone();
            }
        }
        catch (Exception exception) when (exception is JsonException or IOException or InvalidOperationException)
        {
            catalog._models.Clear();
            catalog._aliases.Clear();
            catalog.Error = exception.Message;
        }

        return catalog;
    }

    public CostEstimate? Estimate(HudSnapshot snapshot)
    {
        if (!Loaded)
        {
            return null;
        }

        var pricedAs = snapshot.Model;
        if (!_models.ContainsKey(pricedAs) && _aliases.TryGetValue(snapshot.Model, out var alias))
        {
            pricedAs = alias;
        }

        if (!_models.TryGetValue(pricedAs, out var rates))
        {
            return null;
        }

        var uncached = Math.Max(0, snapshot.TaskInput - snapshot.TaskCached);
        var cost = (uncached * rates.Input + snapshot.TaskCached * rates.Cached + snapshot.TaskOutput * rates.Output) / 1_000_000.0;
        return new CostEstimate(cost, pricedAs, rates.Estimated);
    }

    private static bool TryRate(JsonElement element, string name, out double value)
    {
        value = 0;
        return element.TryGetProperty(name, out var node) && node.TryGetDouble(out value);
    }
}
