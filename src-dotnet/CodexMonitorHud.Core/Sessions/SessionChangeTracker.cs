using System.Collections.Concurrent;

namespace CodexMonitorHud.Core.Sessions;

public sealed class SessionChangeTracker : IDisposable
{
    private readonly FileSystemWatcher? _watcher;
    private int _dirty = 1;
    private int _overflowed;
    private int _structural = 1;
    private readonly ConcurrentDictionary<string, byte> _changedPaths;

    public event Action? ChangeAvailable;

    public SessionChangeTracker(
        string sessionsRoot,
        string filter = "*.jsonl",
        bool includeSubdirectories = true,
        StringComparer? pathComparer = null)
    {
        _changedPaths = new ConcurrentDictionary<string, byte>(pathComparer ?? GetPlatformPathComparer());
        var watchRoot = sessionsRoot;
        var effectiveIncludeSubdirectories = includeSubdirectories;
        if (!Directory.Exists(watchRoot))
        {
            var parent = Directory.GetParent(watchRoot)?.FullName;
            if (string.IsNullOrWhiteSpace(parent) || !Directory.Exists(parent))
            {
                return;
            }
            watchRoot = parent;
            effectiveIncludeSubdirectories = true;
        }

        _watcher = new FileSystemWatcher(watchRoot, filter)
        {
            IncludeSubdirectories = effectiveIncludeSubdirectories,
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size,
            InternalBufferSize = 16 * 1024,
            EnableRaisingEvents = true
        };
        _watcher.Changed += MarkDirty;
        _watcher.Created += MarkStructural;
        _watcher.Deleted += MarkStructural;
        _watcher.Renamed += MarkStructural;
        _watcher.Error += (_, _) =>
        {
            Interlocked.Exchange(ref _overflowed, 1);
            Interlocked.Exchange(ref _dirty, 1);
            Interlocked.Exchange(ref _structural, 1);
            NotifyChangeAvailable();
        };
    }

    public static StringComparer GetPlatformPathComparer() =>
        OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;

    public bool ConsumeDirty() => Interlocked.Exchange(ref _dirty, 0) == 1;
    public bool ConsumeOverflowed() => Interlocked.Exchange(ref _overflowed, 0) == 1;
    public bool ConsumeStructural() => Interlocked.Exchange(ref _structural, 0) == 1;
    public IReadOnlyList<string> DrainChangedPaths()
    {
        var paths = _changedPaths.Keys.ToArray();
        foreach (var path in paths)
        {
            _changedPaths.TryRemove(path, out _);
        }
        return paths;
    }
    public void ForceReconciliation()
    {
        Interlocked.Exchange(ref _dirty, 1);
        Interlocked.Exchange(ref _structural, 1);
    }

    public void Dispose()
    {
        _watcher?.Dispose();
    }

    private void MarkDirty(object sender, FileSystemEventArgs args)
    {
        TrackPath(args.FullPath);
        Interlocked.Exchange(ref _dirty, 1);
        NotifyChangeAvailable();
    }

    private void MarkStructural(object sender, FileSystemEventArgs args)
    {
        TrackPath(args.FullPath);
        Interlocked.Exchange(ref _structural, 1);
        Interlocked.Exchange(ref _dirty, 1);
        NotifyChangeAvailable();
    }

    private void TrackPath(string path)
    {
        if (_changedPaths.Count >= 256)
        {
            Interlocked.Exchange(ref _overflowed, 1);
            return;
        }
        _changedPaths.TryAdd(path, 0);
    }

    private void NotifyChangeAvailable()
    {
        ChangeAvailable?.Invoke();
    }
}
