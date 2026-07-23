namespace CodexMonitorHud.Core.Sessions;

public sealed record JsonLineSplit(IReadOnlyList<string> CompleteLines, string PendingText);

public static class JsonLineSplitter
{
    public static JsonLineSplit Split(string? pendingText, string? text)
    {
        var combined = string.Concat(pendingText ?? string.Empty, text ?? string.Empty);
        if (combined.Length == 0)
        {
            return new JsonLineSplit(Array.Empty<string>(), string.Empty);
        }

        var parts = combined.Split('\n');
        var complete = new List<string>(parts.Length);
        for (var index = 0; index < parts.Length - 1; index++)
        {
            complete.Add(parts[index].TrimEnd('\r'));
        }

        var pending = string.Empty;
        if (!combined.EndsWith('\n'))
        {
            var candidate = parts[^1].TrimEnd('\r');
            var trimmed = candidate.TrimEnd();
            if (trimmed.StartsWith('{') && trimmed.EndsWith('}'))
            {
                complete.Add(candidate);
            }
            else
            {
                pending = parts[^1];
            }
        }

        return new JsonLineSplit(complete, pending);
    }
}
