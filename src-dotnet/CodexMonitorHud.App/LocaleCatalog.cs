using System.Text.Json;

namespace CodexMonitorHud.App;

internal sealed class LocaleCatalog
{
    private readonly string _localeRoot;
    private readonly Dictionary<string, IReadOnlyDictionary<string, string>> _cache = new(StringComparer.Ordinal);

    public LocaleCatalog(string localeRoot)
    {
        _localeRoot = localeRoot;
    }

    public IReadOnlyDictionary<string, string> Get(string language)
    {
        if (_cache.TryGetValue(language, out var locale))
        {
            return locale;
        }

        var path = Path.Combine(_localeRoot, language + ".json");
        if (!File.Exists(path))
        {
            path = Path.Combine(_localeRoot, "en.json");
        }

        using var document = JsonDocument.Parse(File.ReadAllText(path));
        var dictionary = document.RootElement.EnumerateObject().ToDictionary(
            static property => property.Name,
            static property => property.Value.ValueKind == JsonValueKind.String
                ? property.Value.GetString() ?? string.Empty
                : property.Value.GetRawText(),
            StringComparer.Ordinal);
        _cache[language] = dictionary;
        return dictionary;
    }
}
