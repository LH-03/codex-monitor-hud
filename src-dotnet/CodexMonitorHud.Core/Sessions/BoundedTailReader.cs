using System.Buffers;
using System.Runtime.InteropServices;
using System.Text;
using CodexMonitorHud.Core.Models;
using CodexMonitorHud.Core.Parsing;

namespace CodexMonitorHud.Core.Sessions;

public static class BoundedTailReader
{
    // Tool/result bookkeeping can add thousands of small records after the
    // most recent token_count.  Keep a bounded but sufficiently deep record
    // horizon so those records do not displace the latest accounting event.
    public const int DefaultTailLines = 8_192;
    // Search farther than the retained-record ceiling.  Codex may append a
    // few very large response_item records after the latest token_count; those
    // records are irrelevant to the HUD and must not hide the last accounting
    // snapshot just because they occupy the final 8 MiB of a session file.
    public const long MaximumTailScanBytes = 32L * 1024 * 1024;
    public const long MaximumTailBytes = 8L * 1024 * 1024;

    public static HudSnapshot? ReadLatestSnapshot(string path, int tailLines = DefaultTailLines)
    {
        var lines = ReadLines(path, tailLines);
        HudRecord? usage = null;
        HudRecord? allowance = null;
        var model = string.Empty;
        var workspace = string.Empty;
        var lifecycleSeen = false;
        var terminalStatus = string.Empty;
        DateTimeOffset? terminalTimestamp = null;
        var terminalSilent = false;

        for (var index = lines.Count - 1; index >= 0; index--)
        {
            var item = HudRecordParser.Parse(lines[index]);
            if (item is null)
            {
                continue;
            }

            if (!lifecycleSeen && item.Kind is HudRecordKind.Started or HudRecordKind.Completed or
                HudRecordKind.Aborted)
            {
                lifecycleSeen = true;
                if (item.Kind is HudRecordKind.Completed or HudRecordKind.Aborted)
                {
                    terminalStatus = item.Kind == HudRecordKind.Aborted ? "aborted" : "completed";
                    terminalTimestamp = item.Timestamp;
                    terminalSilent = false;
                }
            }

            if (allowance is null && item.Kind is HudRecordKind.Usage or HudRecordKind.Allowance &&
                (item.WeeklyRemainingPercent.HasValue || item.FiveHourRemainingPercent.HasValue))
            {
                allowance = item;
            }

            if (usage is null && item.Kind == HudRecordKind.Usage)
            {
                usage = item;
            }

            if (item.Kind == HudRecordKind.Context)
            {
                if (string.IsNullOrWhiteSpace(model))
                {
                    model = item.Model;
                }

                if (string.IsNullOrWhiteSpace(workspace))
                {
                    workspace = item.Workspace;
                }
            }

            if (lifecycleSeen && usage is not null && allowance is not null &&
                !string.IsNullOrWhiteSpace(model) && !string.IsNullOrWhiteSpace(workspace))
            {
                break;
            }
        }

        if (usage is null)
        {
            return null;
        }

        var snapshot = HudSnapshot.FromUsage(usage) with
        {
            Model = model,
            Workspace = workspace,
            TerminalStatus = terminalStatus,
            TerminalTimestamp = terminalTimestamp,
            TerminalSilent = terminalSilent
        };
        return allowance is null
            ? snapshot
            : snapshot with
            {
                AllowanceTimestamp = allowance.AllowanceTimestamp,
                WeeklyRemainingPercent = allowance.WeeklyRemainingPercent,
                FiveHourRemainingPercent = allowance.FiveHourRemainingPercent
            };
    }

    public static IReadOnlyList<string> ReadLines(string path, int tailLines = DefaultTailLines)
    {
        var limit = Math.Max(1, tailLines);
        using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete,
            64 * 1024,
            FileOptions.RandomAccess);
        var window = Math.Min(MaximumTailScanBytes, stream.Length);
        var earliest = stream.Length - window;
        var position = stream.Length;
        var buffer = ArrayPool<byte>.Shared.Rent(64 * 1024);
        var reversedLine = new List<byte>(1024);
        var reversedLines = new List<string>(Math.Min(limit, 2_048));
        var discardingOversizedLine = false;
        try
        {
            while (position > earliest && reversedLines.Count < limit)
            {
                var readStart = Math.Max(earliest, position - buffer.Length);
                var count = checked((int)(position - readStart));
                stream.Position = readStart;
                var read = 0;
                while (read < count)
                {
                    var next = stream.Read(buffer, read, count - read);
                    if (next == 0) break;
                    read += next;
                }

                for (var index = read - 1; index >= 0 && reversedLines.Count < limit; index--)
                {
                    if (buffer[index] == (byte)'\n')
                    {
                        if (discardingOversizedLine)
                        {
                            discardingOversizedLine = false;
                        }
                        else
                        {
                            AddReversedLine(reversedLine, reversedLines);
                        }
                    }
                    else if (!discardingOversizedLine)
                    {
                        reversedLine.Add(buffer[index]);
                        if (reversedLine.Count > MaximumTailBytes)
                        {
                            reversedLine.Clear();
                            discardingOversizedLine = true;
                        }
                    }
                }
                position = readStart;
            }

            // When the byte window starts in the middle of a record, discard
            // that oldest partial record. At file start it is a complete first
            // line and must be retained even without a trailing newline.
            if (position == 0 && !discardingOversizedLine && reversedLines.Count < limit)
            {
                AddReversedLine(reversedLine, reversedLines);
            }
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(buffer);
        }

        reversedLines.Reverse();
        return reversedLines;
    }

    private static void AddReversedLine(List<byte> reversedLine, List<string> lines)
    {
        if (reversedLine.Count == 0)
        {
            return;
        }
        var span = CollectionsMarshal.AsSpan(reversedLine);
        span.Reverse();
        if (span.Length > 0 && span[^1] == (byte)'\r')
        {
            span = span[..^1];
        }
        var line = Encoding.UTF8.GetString(span).TrimStart('\uFEFF');
        if (line.Length > 0)
        {
            lines.Add(line);
        }
        reversedLine.Clear();
    }
}
