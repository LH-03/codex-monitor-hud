using System.Text;
using System.Text.Json;
using CodexMonitorHud.Core.Models;
using CodexMonitorHud.Core.Parsing;
using CodexMonitorHud.Core.Sessions;
using CodexMonitorHud.Core.State;

internal static class OptimizationRegressionTests
{
    public static void Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "hud-boundaries-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var path = Path.Combine(root, "boundary.jsonl");
            var encoding = new UTF8Encoding(false);
            var random = new Random(481);
            var records = Enumerable.Range(0, 80).Select(i =>
                JsonSerializer.Serialize(new { index = i, text = new string('x', random.Next(1, 90000)) + "边界🌍" })).ToArray();
            var text = "\uFEFF" + string.Join("\r\n\n", records) + "\r\n";
            File.WriteAllText(path, text, encoding);
            var expected = text.Split('\n')[..^1].Select(line => line.EndsWith('\r') ? line[..^1] : line).ToArray();
            foreach (var budget in new[] { 4096, 65536, 262144 })
            {
                var reader = new IncrementalJsonlReader(0);
                var actual = new List<string>();
                do { actual.AddRange(reader.ReadAppended(path, budget)); } while (reader.HasUnreadData);
                Require(expected.SequenceEqual(actual), "incremental CRLF/empty/UTF-8 boundary ordering");
            }
            foreach (var limit in new[] { 1, 7, 80, 200 })
            {
                var expectedTail = expected.Select(line => line.TrimStart('\uFEFF')).Where(line => line.Length > 0).TakeLast(limit);
                Require(expectedTail.SequenceEqual(BoundedTailReader.ReadLines(path, limit)), "reverse chunk boundary ordering");
            }

            File.WriteAllText(path, "{\"text\":\"未", encoding);
            var partial = new IncrementalJsonlReader(0);
            Require(partial.ReadAppended(path).Count == 0, "unfinished EOF retained");
            File.AppendAllText(path, "完🌍\"}", encoding);
            Require(partial.ReadAppended(path).Single() == "{\"text\":\"未完🌍\"}", "completed EOF emitted once");
            Require(partial.ReadAppended(path).Count == 0, "unchanged EOF not emitted again");
            File.WriteAllText(path, "{}\u2003", encoding);
            Require(partial.ReadAppended(path).Single() == "{}\u2003", "truncation and Unicode EOF whitespace");
            File.WriteAllText(path, "{bad}\n{}", encoding);
            partial.Reset();
            Require(partial.ReadAppended(path).SequenceEqual(new[] { "{bad}", "{}" }), "malformed delimited record does not lose following EOF");

            File.WriteAllText(path, new string('x', (int)BoundedTailReader.MaximumTailBytes + 1) + "\n{}\n", encoding);
            partial.Reset();
            var afterOversized = new List<string>();
            do { afterOversized.AddRange(partial.ReadAppended(path)); } while (partial.HasUnreadData);
            Require(afterOversized.SequenceEqual(new[] { "{}" }), "oversized record discard resumes at newline");
            Require(BoundedTailReader.ReadLines(path).SequenceEqual(new[] { "{}" }), "reverse oversized record discard");

            foreach (var message in new[] { "", " ", "\t\n\r\f", "\b", "\u00a0\u2003\u3000", "边界", " 🌍", "\\", "\"", "\u200b", new string(' ', 10000) + "Done" })
            {
                foreach (var escapeUnicode in new[] { true, false })
                {
                    var options = new JsonSerializerOptions
                    {
                        Encoder = escapeUnicode ? null : System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
                    };
                    var line = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"last_agent_message\":" + JsonSerializer.Serialize(message, options) + "}}";
                    var expectedKind = string.IsNullOrWhiteSpace(message) ? HudRecordKind.CompletedSilent : HudRecordKind.Completed;
                    Require(HudRecordParser.Parse(line)?.Kind == expectedKind, "completion whitespace visibility");
                }
            }

            var now = DateTimeOffset.Parse("2026-07-13T08:00:00Z");
            var first = new HudSnapshot { Timestamp = now, FiveHourRemainingPercent = 60, EstimatedCostUsd = 0.5, ContextPercent = double.NaN };
            var second = new HudSnapshot { Timestamp = now, FiveHourRemainingPercent = 70, WeeklyRemainingPercent = 80, ContextPercent = 5 };
            Require(SnapshotAggregator.GetLatestAllowance(new[] { first, second })?.FiveHourRemainingPercent == 60, "allowance tie retains first observation");
            var merged = SnapshotAggregator.Merge(new[] { first, second }, "{tasks}/{models}");
            Require(merged?.EstimatedCostUsd is null && merged?.ContextPercent == 5, "unknown cost and NaN aggregation semantics");
            Require(SnapshotAggregator.Merge(new[] { first }, "unused") == first with { ActiveTasks = 1 }, "single snapshot retains fields");
            try
            {
                SnapshotAggregator.Merge(new[] { first with { Input = long.MaxValue }, second with { Input = 1 } }, "unused");
                throw new InvalidOperationException("Counter overflow was silently wrapped.");
            }
            catch (OverflowException) { }
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    private static void Require(bool condition, string name)
    {
        if (!condition) throw new InvalidOperationException(name);
    }
}
