namespace CodexMonitorHud.Core.Sessions;

public sealed record SessionFile(
    string FullName,
    DateTime LastWriteTimeUtc,
    long Length,
    bool ReadBlocked = false);

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
        // Opening every historical rollout on every refresh would defeat the
        // HUD's lightweight contract. Keep a bounded set of the newest files
        // as lock probes so a long tool call can remain discoverable after its
        // normal write-time window has elapsed.
        var probeLimit = Math.Max(256, maximum * 8);
        var probes = new PriorityQueue<SessionFile, DateTime>();
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

                probes.Enqueue(candidate, candidate.LastWriteTimeUtc);
                if (probes.Count > probeLimit)
                {
                    _ = probes.Dequeue();
                }
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }

        var selected = active.UnorderedItems
            .Select(static item => item.Element)
            .ToDictionary(static file => file.FullName, SessionChangeTracker.GetPlatformPathComparer());
        var probed = new HashSet<string>(SessionChangeTracker.GetPlatformPathComparer());
        foreach (var candidate in probes.UnorderedItems.Select(static item => item.Element))
        {
            probed.Add(candidate.FullName);
            if (IsReadBlocked(candidate.FullName))
            {
                selected[candidate.FullName] = candidate with { ReadBlocked = true };
            }
        }

        foreach (var path in selected.Keys.ToArray())
        {
            if (!probed.Contains(path) && !selected[path].ReadBlocked && IsReadBlocked(path))
            {
                selected[path] = selected[path] with { ReadBlocked = true };
            }
        }

        if (selected.Count == 0)
        {
            return latest is null
                ? Array.Empty<SessionFile>()
                : new[] { latest with { ReadBlocked = IsReadBlocked(latest.FullName) } };
        }

        return selected.Values
            .OrderByDescending(static file => file.ReadBlocked)
            .ThenByDescending(static file => file.LastWriteTimeUtc)
            .Take(maximum)
            .ToArray();
    }

    public static bool IsReadBlocked(string path)
    {
        try
        {
            using var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete,
                1,
                FileOptions.None);
            return false;
        }
        catch (IOException exception) when (IsSharingViolation(exception))
        {
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }

    public static SessionFile? GetLatestFile(string sessionsRoot)
    {
        if (!Directory.Exists(sessionsRoot))
        {
            return null;
        }

        SessionFile? latest = null;
        foreach (var path in EnumerateJsonlFilesSafe(sessionsRoot))
        {
            try
            {
                var file = new FileInfo(path);
                if (latest is null || file.LastWriteTimeUtc > latest.LastWriteTimeUtc)
                {
                    latest = new SessionFile(file.FullName, file.LastWriteTimeUtc, file.Length);
                }
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }

        return latest is null
            ? null
            : latest with { ReadBlocked = IsReadBlocked(latest.FullName) };
    }

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

    private static bool IsSharingViolation(IOException exception)
    {
        var nativeCode = exception.HResult & 0xFFFF;
        return nativeCode is 32 or 33;
    }
}
