using System.Diagnostics;
using System.Text;
using System.Text.Json;
using CodexMonitorHud.Core.Models;
using CodexMonitorHud.Core.Parsing;
using CodexMonitorHud.Core.Presentation;
using CodexMonitorHud.Core.Pricing;
using CodexMonitorHud.Core.Sessions;
using CodexMonitorHud.Core.State;

internal static class PerformanceBenchmarks
{
    // Synthetic fixtures only. Run the same executable against both revisions.
    public static void Run(string repositoryRoot)
    {
        var root = Path.Combine(Path.GetTempPath(), "hud-benchmark-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var now = DateTimeOffset.UtcNow;
            var snapshots = Enumerable.Range(0, 64).Select(i => new HudSnapshot
            {
                Timestamp = now.AddSeconds(i), Model = "gpt-5", Input = 1000, Cached = 700,
                Uncached = 300, Output = 100, CallTotal = 1100, TaskTotal = 11000,
                TaskInput = 10000, TaskCached = 7000, TaskOutput = 1000,
                ContextWindow = 200000, ContextPercent = 0.5, EstimatedCostUsd = 0.01,
                WeeklyRemainingPercent = i % 2 == 0 ? 80 : null,
                FiveHourRemainingPercent = i % 2 != 0 ? 75 : null
            }).ToArray();
            var usage = """{"timestamp":"2026-07-13T08:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":20},"total_token_usage":{"total_tokens":120}}}}""";
            var burst = Path.Combine(root, "burst.jsonl");
            File.WriteAllText(burst, string.Concat(Enumerable.Repeat(usage + "\n", 5000)), new UTF8Encoding(false));
            var tail = Path.Combine(root, "tail.jsonl");
            File.WriteAllText(tail, usage + "\n" + "{\"type\":\"response_item\",\"payload\":\"" + new string('x', 4 * 1024 * 1024) + "\"}\n", new UTF8Encoding(false));
            var completion = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"last_agent_message\":\"" + new string('x', 512 * 1024) + "\"}}";
            var sessions = Path.Combine(root, "sessions");
            Directory.CreateDirectory(sessions);
            for (var i = 0; i < 2000; i++) File.WriteAllText(Path.Combine(sessions, $"{i:D4}.jsonl"), "{}");
            var catalog = PricingCatalog.Load(repositoryRoot);
            var fields = new Dictionary<string, bool> { ["callTotal"] = true, ["activeTasks"] = true, ["context"] = true };
            var locale = new Dictionary<string, string>();
            Measure("aggregate_64", 10000, () => GC.KeepAlive(SnapshotAggregator.Merge(snapshots, "{tasks} tasks / {models} models")));
            Measure("allowance_64", 10000, () => GC.KeepAlive(SnapshotAggregator.GetLatestAllowance(snapshots)));
            Measure("incremental_5000", 20, () =>
            {
                var reader = new IncrementalJsonlReader(0);
                do { GC.KeepAlive(reader.ReadAppended(burst)); } while (reader.HasUnreadData);
            });
            Measure("tail_4MiB", 15, () => GC.KeepAlive(BoundedTailReader.ReadLatestSnapshot(tail)));
            Measure("completion_512KiB", 100, () => GC.KeepAlive(HudRecordParser.Parse(completion)));
            Measure("discovery_2000", 5, () => GC.KeepAlive(SessionDiscovery.GetActiveFiles(sessions)));
            Measure("pricing", 10000, () => GC.KeepAlive(catalog.Estimate(snapshots[0])));
            Measure("summary_formatting", 10000, () => GC.KeepAlive(HudFormatting.GetSummaryMetrics(snapshots[0], fields, locale, "exact")));
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    private static void Measure(string name, int iterations, Action action)
    {
        for (var i = 0; i < 5; i++) action();
        GC.Collect();
        GC.WaitForPendingFinalizers();
        var allocated = GC.GetAllocatedBytesForCurrentThread();
        var timer = Stopwatch.StartNew();
        for (var i = 0; i < iterations; i++) action();
        timer.Stop();
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            name, iterations, elapsed_ms = timer.Elapsed.TotalMilliseconds,
            bytes_per_operation = (GC.GetAllocatedBytesForCurrentThread() - allocated) / iterations
        }));
    }
}
