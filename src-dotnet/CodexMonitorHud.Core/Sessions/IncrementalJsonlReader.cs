using System.Buffers;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace CodexMonitorHud.Core.Sessions;

public sealed class IncrementalJsonlReader
{
    public const int DefaultReadBudgetBytes = 1024 * 1024;
    private readonly List<byte> _pending = new();
    private bool _discardingOversizedLine;

    public IncrementalJsonlReader(long initialOffset)
    {
        Offset = Math.Max(0, initialOffset);
    }

    public long Offset { get; private set; }
    public bool HasUnreadData { get; private set; }
    public int LastReadBytes { get; private set; }

    public IReadOnlyList<string> ReadAppended(string path, int maximumBytes = DefaultReadBudgetBytes)
    {
        LastReadBytes = 0;
        using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete,
            64 * 1024,
            FileOptions.SequentialScan);
        if (stream.Length < Offset)
        {
            Offset = 0;
            _pending.Clear();
            _discardingOversizedLine = false;
        }

        if (stream.Length == Offset)
        {
            HasUnreadData = false;
            return Array.Empty<string>();
        }

        stream.Seek(Offset, SeekOrigin.Begin);
        var readStart = Offset;
        var buffer = ArrayPool<byte>.Shared.Rent(64 * 1024);
        var lines = new List<string>();
        try
        {
            int read;
            var remainingBudget = Math.Max(4096, maximumBytes);
            while (remainingBudget > 0 &&
                   (read = stream.Read(buffer, 0, Math.Min(buffer.Length, remainingBudget))) > 0)
            {
                remainingBudget -= read;
                var start = 0;
                for (var index = 0; index < read; index++)
                {
                    if (buffer[index] != (byte)'\n')
                    {
                        continue;
                    }

                    if (!_discardingOversizedLine && AppendPending(buffer.AsSpan(start, index - start)))
                    {
                        var count = _pending.Count;
                        if (count > 0 && _pending[count - 1] == (byte)'\r')
                        {
                            count--;
                        }
                        lines.Add(Encoding.UTF8.GetString(CollectionsMarshal.AsSpan(_pending)[..count]));
                    }
                    _pending.Clear();
                    _discardingOversizedLine = false;
                    start = index + 1;
                }

                if (start < read && !_discardingOversizedLine && !AppendPending(buffer.AsSpan(start, read - start)))
                {
                    _discardingOversizedLine = true;
                }
            }
            Offset = stream.Position;
            LastReadBytes = checked((int)Math.Min(int.MaxValue, Offset - readStart));
            HasUnreadData = Offset < stream.Length;
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(buffer);
        }

        // A budget boundary can land immediately after a complete JSON object
        // but before its following newline.  Do not emit it yet: the next
        // call would otherwise consume that newline as a second blank record.
        // A final non-newline JSON record is emitted only at actual EOF.
        if (!HasUnreadData && !_discardingOversizedLine && _pending.Count > 0)
        {
            var candidate = Encoding.UTF8.GetString(CollectionsMarshal.AsSpan(_pending));
            var trimmed = candidate.TrimEnd();
            if (IsCompleteJsonObject(trimmed))
            {
                lines.Add(candidate.TrimEnd('\r'));
                _pending.Clear();
            }
        }

        return lines;
    }

    public void Reset()
    {
        Offset = 0;
        _pending.Clear();
        _discardingOversizedLine = false;
        HasUnreadData = false;
        LastReadBytes = 0;
    }

    private bool AppendPending(ReadOnlySpan<byte> bytes)
    {
        if (_pending.Count + (long)bytes.Length > BoundedTailReader.MaximumTailBytes)
        {
            _pending.Clear();
            return false;
        }
        var previousCount = _pending.Count;
        CollectionsMarshal.SetCount(_pending, previousCount + bytes.Length);
        bytes.CopyTo(CollectionsMarshal.AsSpan(_pending)[previousCount..]);
        return true;
    }

    private static bool IsCompleteJsonObject(string candidate)
    {
        if (!candidate.StartsWith('{') || !candidate.EndsWith('}'))
        {
            return false;
        }
        try
        {
            using var document = JsonDocument.Parse(candidate);
            return document.RootElement.ValueKind == JsonValueKind.Object;
        }
        catch (JsonException)
        {
            return false;
        }
    }
}
