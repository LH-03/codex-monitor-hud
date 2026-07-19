using System.Text.Json;

namespace CodexMonitorHud.Mac;

internal sealed class MacLocaleCatalog
{
    private readonly string _localeRoot;
    private readonly Dictionary<string, IReadOnlyDictionary<string, string>> _cache = new(StringComparer.Ordinal);

    public MacLocaleCatalog(string localeRoot) => _localeRoot = localeRoot;

    public IReadOnlyDictionary<string, string> Get(string language)
    {
        if (_cache.TryGetValue(language, out var cached))
        {
            return cached;
        }
        var path = Path.Combine(_localeRoot, language + ".json");
        if (!File.Exists(path))
        {
            path = Path.Combine(_localeRoot, "en.json");
        }
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        var locale = document.RootElement.EnumerateObject().ToDictionary(
            static property => property.Name,
            static property => property.Value.ValueKind == JsonValueKind.String
                ? property.Value.GetString() ?? string.Empty
                : property.Value.GetRawText(),
            StringComparer.Ordinal);
        _cache[language] = locale;
        return locale;
    }
}
