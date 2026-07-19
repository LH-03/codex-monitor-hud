namespace CodexMonitorHud.Core.State;

public sealed class TaskNumberPool
{
    private readonly Queue<ReleasedNumber> _released = new();
    private readonly HashSet<int> _releasedSet = new();
    private int _nextNumber = 1;

    public TaskNumberPool(int maximumReleased = 512)
    {
        MaximumReleased = Math.Max(32, maximumReleased);
    }

    public int MaximumReleased { get; }
    public int ReleasedCount => _released.Count;

    public int Acquire(DateTimeOffset? now = null)
    {
        var current = now ?? DateTimeOffset.Now;
        if (_released.TryPeek(out var candidate) && candidate.AvailableAt <= current)
        {
            _ = _released.Dequeue();
            _releasedSet.Remove(candidate.Number);
            return candidate.Number;
        }

        return _nextNumber++;
    }

    public void Release(int number, int cooldownSeconds = 120, DateTimeOffset? now = null)
    {
        if (number <= 0 || _releasedSet.Contains(number) || _released.Count >= MaximumReleased)
        {
            return;
        }

        _released.Enqueue(new ReleasedNumber(
            number,
            (now ?? DateTimeOffset.Now).AddSeconds(Math.Max(0, cooldownSeconds))));
        _releasedSet.Add(number);
    }

    private sealed record ReleasedNumber(int Number, DateTimeOffset AvailableAt);
}
