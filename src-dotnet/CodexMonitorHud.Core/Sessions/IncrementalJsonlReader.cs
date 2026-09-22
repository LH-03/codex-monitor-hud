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
            1,
            FileOptions.SequentialScan);
        if (stream.Length < Offset)
        {
            Offset = 0;
            ClearPending();
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
                while (start < read)
                {
                    var newline = buffer.AsSpan(start, read - start).IndexOf((byte)'\n');
                    if (newline < 0) break;
                    var index = start + newline;
                    var segment = buffer.AsSpan(start, newline);
                    if (!_discardingOversizedLine)
                    {
                        // Most records fit in this read. Decode in place; retain
                        // bytes only when a record actually crosses a boundary.
                        if (_pending.Count == 0)
                        {
                            lines.Add(DecodeLine(segment));
                        }
                        else if (AppendPending(segment))
                        {
                            lines.Add(DecodeLine(CollectionsMarshal.AsSpan(_pending)));
                        }
                    }
                    ClearPending();
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
            if (IsCompleteJsonObject(CollectionsMarshal.AsSpan(_pending)))
            {
                lines.Add(Encoding.UTF8.GetString(CollectionsMarshal.AsSpan(_pending)).TrimEnd('\r'));
                ClearPending();
            }
        }

        return lines;
    }

    public void Reset()
    {
        Offset = 0;
        ClearPending();
        _discardingOversizedLine = false;
        HasUnreadData = false;
        LastReadBytes = 0;
    }

    private bool AppendPending(ReadOnlySpan<byte> bytes)
    {
        if (_pending.Count + (long)bytes.Length > BoundedTailReader.MaximumTailBytes)
        {
            ClearPending();
            return false;
        }
        var previousCount = _pending.Count;
        CollectionsMarshal.SetCount(_pending, previousCount + bytes.Length);
        bytes.CopyTo(CollectionsMarshal.AsSpan(_pending)[previousCount..]);
        return true;
    }

    private void ClearPending()
    {
        _pending.Clear();
        // One large tool result must not leave an 8 MiB array in every session.
        if (_pending.Capacity > 128 * 1024) _pending.Capacity = 0;
    }

    private static string DecodeLine(ReadOnlySpan<byte> line) =>
        Encoding.UTF8.GetString(line.Length > 0 && line[^1] == (byte)'\r' ? line[..^1] : line);

    private static bool IsCompleteJsonObject(ReadOnlySpan<byte> candidate)
    {
        // Match the old string.TrimEnd behavior even for non-JSON Unicode
        // whitespace at EOF, without decoding the entire pending record.
        while (!candidate.IsEmpty &&
               Rune.DecodeLastFromUtf8(candidate, out var rune, out var consumed) == OperationStatus.Done &&
               Rune.IsWhiteSpace(rune)) candidate = candidate[..^consumed];
        if (candidate.IsEmpty || candidate[0] != (byte)'{')
        {
            return false;
        }
        try
        {
            var reader = new Utf8JsonReader(candidate);
            return reader.Read() && reader.TokenType == JsonTokenType.StartObject &&
                   reader.TrySkip() && !reader.Read();
        }
        catch (JsonException)
        {
            return false;
        }
    }
}
