using System.Text.Json;

namespace CodexMonitorHud.Core.Sessions;

public sealed record SessionIdentity(
    bool MetadataFound,
    string SessionId,
    string Workspace,
    bool IsInternalSession,
    string ClientSurface,
    string ModelProvider);

public static class SessionIdentityReader
{
    public static SessionIdentity Read(string path, int maximumLines = 64)
    {
        try
        {
            using var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete,
                4096,
                FileOptions.SequentialScan);
            using var reader = new StreamReader(stream, detectEncodingFromByteOrderMarks: true);
            for (var index = 0; index < Math.Max(1, maximumLines) && reader.ReadLine() is { } line; index++)
            {
                var identity = ParseLine(line);
                if (identity.MetadataFound)
                {
                    return identity;
                }
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }

        return Empty;
    }

    public static SessionIdentity ParseLine(string line)
    {
        if (!line.AsSpan(0, Math.Min(64 * 1024, line.Length)).Contains("\"session_meta\"", StringComparison.Ordinal))
        {
            return Empty;
        }

        try
        {
            using var document = JsonDocument.Parse(line);
            var root = document.RootElement;
            if (!root.TryGetProperty("type", out var type) || type.GetString() != "session_meta" ||
                !root.TryGetProperty("payload", out var payload))
            {
                return Empty;
            }

            var id = GetString(payload, "id");
            if (string.IsNullOrWhiteSpace(id))
            {
                id = GetString(payload, "session_id");
            }

            var workspace = PortableLeaf(GetString(payload, "cwd"));
            var internalSession = payload.TryGetProperty("source", out var source) &&
                                  source.ValueKind == JsonValueKind.Object &&
                                  source.TryGetProperty("subagent", out _);
            var originator = GetString(payload, "originator");
            var sourceName = source.ValueKind == JsonValueKind.String
                ? source.GetString() ?? string.Empty
                : string.Empty;
            var clientSurface = GetClientSurface(originator, sourceName);
            return new SessionIdentity(
                true,
                id,
                workspace,
                internalSession,
                clientSurface,
                NormalizeProvider(GetString(payload, "model_provider")));
        }
        catch (JsonException)
        {
            return Empty;
        }
        catch (InvalidOperationException)
        {
            return Empty;
        }
    }

    private static readonly SessionIdentity Empty = new(
        false,
        string.Empty,
        string.Empty,
        false,
        "unknown",
        string.Empty);

    private static string GetClientSurface(string originator, string source)
    {
        // The VS Code extension writes source=vscode for both surfaces, but its
        // own session header has the distinct codex_vscode originator.
        if (originator.Equals("codex_vscode", StringComparison.OrdinalIgnoreCase) ||
            originator.Equals("Codex VS Code", StringComparison.OrdinalIgnoreCase))
        {
            return "vscode";
        }

        if (originator.Equals("Codex Desktop", StringComparison.OrdinalIgnoreCase) ||
            source.Equals("vscode", StringComparison.OrdinalIgnoreCase))
        {
            return "desktop";
        }

        if (originator.Contains("codex-tui", StringComparison.OrdinalIgnoreCase) ||
            source.Equals("cli", StringComparison.OrdinalIgnoreCase))
        {
            return "cli";
        }

        return "unknown";
    }

    private static string NormalizeProvider(string value)
    {
        var normalized = value.Trim();
        if (normalized.Length == 0)
        {
            return string.Empty;
        }

        return normalized.Length <= 40 ? normalized : normalized[..40];
    }

    private static string GetString(JsonElement element, string name) =>
        element.TryGetProperty(name, out var node) && node.ValueKind == JsonValueKind.String
            ? node.GetString() ?? string.Empty
            : string.Empty;

    private static string PortableLeaf(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return string.Empty;
        }

        var trimmed = path.TrimEnd('\\', '/');
        var separator = Math.Max(trimmed.LastIndexOf('\\'), trimmed.LastIndexOf('/'));
        return separator >= 0 ? trimmed[(separator + 1)..] : trimmed;
    }
}
