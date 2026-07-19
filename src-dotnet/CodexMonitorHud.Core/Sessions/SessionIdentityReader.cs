using System.Text.Json;

namespace CodexMonitorHud.Core.Sessions;

public sealed record SessionIdentity(
    bool MetadataFound,
    string SessionId,
    string Workspace,
    bool IsInternalSession);

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

        return new SessionIdentity(false, string.Empty, string.Empty, false);
    }

    public static SessionIdentity ParseLine(string line)
    {
        if (!line.AsSpan(0, Math.Min(64 * 1024, line.Length)).Contains("\"session_meta\"", StringComparison.Ordinal))
        {
            return new SessionIdentity(false, string.Empty, string.Empty, false);
        }

        try
        {
            using var document = JsonDocument.Parse(line);
            var root = document.RootElement;
            if (!root.TryGetProperty("type", out var type) || type.GetString() != "session_meta" ||
                !root.TryGetProperty("payload", out var payload))
            {
                return new SessionIdentity(false, string.Empty, string.Empty, false);
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
            return new SessionIdentity(true, id, workspace, internalSession);
        }
        catch (JsonException)
        {
            return new SessionIdentity(false, string.Empty, string.Empty, false);
        }
        catch (InvalidOperationException)
        {
            return new SessionIdentity(false, string.Empty, string.Empty, false);
        }
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
