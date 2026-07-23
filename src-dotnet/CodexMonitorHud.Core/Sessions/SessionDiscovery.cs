namespace CodexMonitorHud.Core.Sessions;

public sealed record SessionFile(string FullName, DateTime LastWriteTimeUtc, long Length);

public static class SessionDiscovery
{
    public static IReadOnlyList<SessionFile> GetActiveFiles(
        string sessionsRoot,
        int activeWindowMinutes = 30,
        int maximumFiles = 64,
        DateTime? utcNow = null)
    {
        if (!Directory.Exists(sessionsRoot))
        {
            return Array.Empty<SessionFile>();
        }

        var cutoff = (utcNow ?? DateTime.UtcNow).AddMinutes(-Math.Max(1, activeWindowMinutes));
        var maximum = Math.Max(1, maximumFiles);
        var active = new PriorityQueue<SessionFile, DateTime>();
        SessionFile? latest = null;

        foreach (var path in EnumerateJsonlFilesSafe(sessionsRoot))
        {
            try
            {
                var file = new FileInfo(path);
                var candidate = new SessionFile(file.FullName, file.LastWriteTimeUtc, file.Length);
                if (latest is null || candidate.LastWriteTimeUtc > latest.LastWriteTimeUtc)
                {
                    latest = candidate;
                }

                if (candidate.LastWriteTimeUtc >= cutoff)
                {
                    active.Enqueue(candidate, candidate.LastWriteTimeUtc);
                    if (active.Count > maximum)
                    {
                        _ = active.Dequeue();
                    }
                }
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }

        if (active.Count == 0)
        {
            return latest is null ? Array.Empty<SessionFile>() : new[] { latest };
        }

        return active.UnorderedItems
            .Select(static item => item.Element)
            .OrderByDescending(static file => file.LastWriteTimeUtc)
            .ToArray();
    }

    public static SessionFile? GetLatestFile(string sessionsRoot) =>
        GetActiveFiles(sessionsRoot, 1, 1, DateTime.MaxValue).FirstOrDefault();

    private static IEnumerable<string> EnumerateJsonlFilesSafe(string root)
    {
        var pending = new Stack<string>();
        pending.Push(root);
        while (pending.Count > 0)
        {
            var current = pending.Pop();
            IEnumerable<string> files;
            try
            {
                files = Directory.EnumerateFiles(current, "*.jsonl", SearchOption.TopDirectoryOnly).ToArray();
            }
            catch (IOException)
            {
                files = Array.Empty<string>();
            }
            catch (UnauthorizedAccessException)
            {
                files = Array.Empty<string>();
            }

            foreach (var file in files)
            {
                yield return file;
            }

            IEnumerable<string> directories;
            try
            {
                directories = Directory.EnumerateDirectories(current).ToArray();
            }
            catch (IOException)
            {
                directories = Array.Empty<string>();
            }
            catch (UnauthorizedAccessException)
            {
                directories = Array.Empty<string>();
            }

            foreach (var directory in directories)
            {
                pending.Push(directory);
            }
        }
    }
}
