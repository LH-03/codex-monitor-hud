using System.Text;
using System.Text.Json.Nodes;
using CodexMonitorHud.Core.Configuration;
using CodexMonitorHud.Core.Models;
using CodexMonitorHud.Core.Parsing;
using CodexMonitorHud.Core.Presentation;
using CodexMonitorHud.Core.Pricing;
using CodexMonitorHud.Core.Sessions;
using CodexMonitorHud.Core.State;

var repositoryRoot = args.Length > 0 ? Path.GetFullPath(args[0]) : FindRepositoryRoot();
var tests = new (string Name, Action Run)[]
{
    ("record parsing", TestRecordParsing),
    ("official allowance protocol", TestOfficialAllowanceProtocol),
    ("JSON line splitting", TestLineSplitting),
    ("incremental title index", TestTitleIndex),
    ("bounded tail snapshot", TestBoundedTail),
    ("multi-date discovery and cap", TestDiscovery),
    ("snapshot aggregation", TestAggregation),
    ("task number cooldown", TestTaskNumbers),
    ("session state engine", TestSessionEngine),
    ("locked long-running session recovery", TestLockedSessionRecovery),
    ("state database long-running session heartbeat", TestStateDatabaseHeartbeat),
    ("desktop, VS Code, and CLI source identity", TestSessionSources),
    ("formatting and deep links", TestFormatting),
    ("direct HUD placement", TestPlacement),
    ("surface effect adaptation", TestSurfaceEffects),
    ("structural config recovery", TestConfiguration),
    ("macOS path and watcher portability", TestMacPortability),
    ("pricing", TestPricing)
};

foreach (var test in tests)
{
    test.Run();
    Console.WriteLine($"Core {test.Name}: OK");
}

Console.WriteLine($"CodexMonitorHud.Core tests: OK ({tests.Length})");
return;

void TestRecordParsing()
{
    var context = HudRecordParser.Parse("""{"type":"turn_context","payload":{"cwd":"C:\\Synthetic\\pro-workspace","model":"gpt-test"}}""");
    Equal(HudRecordKind.Context, context?.Kind, "context kind");
    Equal("pro-workspace", context?.Workspace, "privacy-safe workspace leaf");
    Equal("gpt-test", context?.Model, "model");

    var completed = HudRecordParser.Parse("""{"timestamp":"2026-07-13T08:00:00Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"visible","last_agent_message":"Done."}}""");
    var silent = HudRecordParser.Parse("""{"timestamp":"2026-07-13T08:00:00Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"silent","last_agent_message":""}}""");
    Equal(HudRecordKind.Completed, completed?.Kind, "visible completion");
    Equal(HudRecordKind.CompletedSilent, silent?.Kind, "silent completion");

    var usage = HudRecordParser.Parse("""{"timestamp":"2026-07-13T08:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120},"total_token_usage":{"input_tokens":1000,"cached_input_tokens":600,"output_tokens":200,"total_tokens":1200},"model_context_window":1000},"rate_limits":{"primary":{"used_percent":14,"window_minutes":300},"secondary":{"used_percent":18,"window_minutes":10080}}}}""");
    NotNull(usage, "usage record");
    Equal(40L, usage!.Uncached, "uncached input");
    Equal(120L, usage.CallTotal, "call total");
    Equal(10d, usage.ContextPercent, "context percent");
    Equal(86d, usage.FiveHourRemainingPercent, "five-hour allowance");
    Equal(82d, usage.WeeklyRemainingPercent, "weekly allowance");
    IsTrue(HudSnapshot.FromUsage(usage).AccountingIsValid, "accounting invariant");
    var usageWithoutLimits = HudRecordParser.Parse("""{"timestamp":"2026-07-13T08:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":null,"info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":20},"total_token_usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":20,"total_tokens":120},"model_context_window":1000}}}""");
    Equal(HudRecordKind.Usage, usageWithoutLimits?.Kind, "null rate limits do not hide usage");
    Equal(120L, usageWithoutLimits?.CallTotal, "null rate limits keep call totals");
    var reserveOnly = HudRecordParser.Parse("""{"timestamp":"2026-08-29T08:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"output_tokens":2},"total_token_usage":{"total_tokens":12}},"rate_limits":{"limit_id":"base_model_inference","limit_name":"gpt-reserve","primary":{"used_percent":0,"window_minutes":10080},"secondary":null}}}""");
    Equal<HudRecordKind?>(HudRecordKind.Usage, reserveOnly?.Kind, "reserve record keeps token usage");
    Equal<double?>(null, reserveOnly?.WeeklyRemainingPercent, "reserve window is not weekly Codex allowance");
    Equal<double?>(null, reserveOnly?.FiveHourRemainingPercent, "reserve window is not five-hour Codex allowance");
    Equal<HudRecord?>(null, HudRecordParser.Parse("""{"type":"response_item","payload":{"text":"private"}}"""), "irrelevant content is rejected");
    var padded = HudRecordParser.Parse("{" + new string(' ', 4096) + "\"timestamp\":\"2026-07-13T08:00:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"padded\"}}");
    Equal(HudRecordKind.Started, padded?.Kind, "relevant type beyond the old 1 KiB prefix is accepted");
    var largeCompletion = HudRecordParser.Parse("{\"timestamp\":\"2026-07-13T08:00:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"large\",\"last_agent_message\":\"" + new string('x', 512 * 1024) + "\"}}");
    Equal(HudRecordKind.Completed, largeCompletion?.Kind, "large completion message is reduced to lifecycle state");
}

void TestLineSplitting()
{
    var complete = JsonLineSplitter.Split(string.Empty, "{\"type\":\"event_msg\"}");
    Equal(1, complete.CompleteLines.Count, "complete no-newline JSON");
    Equal(string.Empty, complete.PendingText, "no pending complete JSON");
    var partial = JsonLineSplitter.Split(string.Empty, "{\"type\":\"event_msg\"");
    Equal(0, partial.CompleteLines.Count, "partial record count");
    IsTrue(partial.PendingText.Length > 0, "partial record retained");
    WithTemporaryDirectory(root =>
    {
        var path = Path.Combine(root, "burst.jsonl");
        var payload = string.Join('\n', Enumerable.Range(0, 5000).Select(index => $"{{\"index\":{index}}}")) + "\n";
        File.WriteAllText(path, payload, new UTF8Encoding(false));
        var reader = new IncrementalJsonlReader(0);
        var lines = reader.ReadAppended(path);
        Equal(5000, lines.Count, "streaming burst line count");
        Equal(new FileInfo(path).Length, reader.Offset, "streaming burst offset");

        reader.Reset();
        var budgetedLines = new List<string>();
        do
        {
            budgetedLines.AddRange(reader.ReadAppended(path, 4096));
        } while (reader.HasUnreadData);
        Equal(5000, budgetedLines.Count, "budgeted streaming burst line count");
        Equal(new FileInfo(path).Length, reader.Offset, "budgeted streaming burst offset");
    });
}

void TestTitleIndex()
{
    WithTemporaryDirectory(root =>
    {
        var path = Path.Combine(root, "session_index.jsonl");
        var encoding = new UTF8Encoding(false);
        File.WriteAllText(path, "{\"id\":\"one\",\"thread_name\":\"First title\"}\n", encoding);
        var index = new SessionTitleIndex();
        IsTrue(index.Refresh(path), "initial title index refresh");
        Equal("First title", index.GetTitle("one"), "initial title");

        File.AppendAllText(path, "{\"id\":\"one\",\"thread_name\":\"Updated title\"}\n{\"id\":\"two\",\"thread_name\":\"Second title\"}\n", encoding);
        IsTrue(index.Refresh(path), "appended title index refresh");
        Equal("Updated title", index.GetTitle("one"), "appended title replaces prior value");
        Equal("Second title", index.GetTitle("two"), "appended title is added");
        IsTrue(!index.Refresh(path), "unchanged title index is skipped");

        File.WriteAllText(path, "{\"id\":\"three\",\"thread_name\":\"Replacement title\"}\n", encoding);
        IsTrue(index.Refresh(path), "truncated title index rebuild");
        Equal(string.Empty, index.GetTitle("one"), "truncation removes stale title");
        Equal("Replacement title", index.GetTitle("three"), "truncation replacement title");

        var burst = string.Concat(Enumerable.Range(0, 30_000).Select(value =>
            $"{{\"id\":\"burst-{value}\",\"thread_name\":\"Burst title {value}\"}}\n"));
        File.WriteAllText(path, burst, encoding);
        IsTrue(index.Refresh(path), "large title index starts a bounded refresh");
        IsTrue(index.HasBacklog, "large title index exposes unread backlog");
        for (var pass = 0; pass < 8 && index.HasBacklog; pass++)
        {
            _ = index.Refresh(path);
        }
        IsTrue(!index.HasBacklog, "large title index backlog drains across bounded passes");
        Equal(string.Empty, index.GetTitle("three"), "larger replacement removes stale title");
        Equal("Burst title 29999", index.GetTitle("burst-29999"), "last title survives bounded backlog");
    });
}

void TestBoundedTail()
{
    WithTemporaryDirectory(root =>
    {
        var path = Path.Combine(root, "tail.jsonl");
        var records = new[]
        {
            """{"timestamp":"2026-07-13T08:00:00Z","type":"turn_context","payload":{"cwd":"C:\\Synthetic\\tail-workspace","model":"gpt-test"}}""",
            """{"timestamp":"2026-07-13T08:00:01Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}""",
            """{"timestamp":"2026-07-13T08:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":200,"cached_input_tokens":150,"output_tokens":30,"reasoning_output_tokens":7,"total_tokens":230},"total_token_usage":{"total_tokens":2000},"model_context_window":2000}}}""",
            """{"timestamp":"2026-07-13T08:00:03Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1","last_agent_message":"Done."}}"""
        };
        File.WriteAllText(path, string.Join('\n', records), new UTF8Encoding(false));
        var snapshot = BoundedTailReader.ReadLatestSnapshot(path);
        NotNull(snapshot, "tail snapshot");
        Equal("tail-workspace", snapshot!.Workspace, "tail workspace");
        Equal("gpt-test", snapshot.Model, "tail model");
        Equal("completed", snapshot.TerminalStatus, "terminal status");
        Equal(2000L, snapshot.TaskTotal, "task total");

        var splitAllowancePath = Path.Combine(root, "split-allowance-tail.jsonl");
        var splitAllowanceRecords = new[]
        {
            """{"timestamp":"2026-07-13T08:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":20,"output_tokens":3},"total_token_usage":{"total_tokens":23},"model_context_window":200},"rate_limits":{"primary":{"used_percent":29,"window_minutes":300},"secondary":null}}}""",
            """{"timestamp":"2026-07-13T08:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":20,"output_tokens":3},"total_token_usage":{"total_tokens":23},"model_context_window":200},"rate_limits":{"primary":{"used_percent":12,"window_minutes":10080},"secondary":null}}}"""
        };
        File.WriteAllText(splitAllowancePath, string.Join('\n', splitAllowanceRecords), new UTF8Encoding(false));
        var splitAllowanceSnapshot = BoundedTailReader.ReadLatestSnapshot(splitAllowancePath);
        Equal(71d, splitAllowanceSnapshot?.FiveHourRemainingPercent, "separate five-hour allowance is retained");
        Equal(88d, splitAllowanceSnapshot?.WeeklyRemainingPercent, "separate weekly allowance is retained");

        var silentPath = Path.Combine(root, "silent-tail.jsonl");
        File.WriteAllText(silentPath, string.Join('\n', records[..^1]) + "\n" +
            """{"timestamp":"2026-07-13T08:00:03Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1","last_agent_message":""}}""",
            new UTF8Encoding(false));
        var silentSnapshot = BoundedTailReader.ReadLatestSnapshot(silentPath);
        Equal(string.Empty, silentSnapshot?.TerminalStatus, "silent completion is not a terminal snapshot");

        var unicodePath = Path.Combine(root, "unicode-tail.jsonl");
        var oldPadding = Enumerable.Range(0, 2500).Select(index => $"{{\"ignored\":{index}}}");
        var unicodeRecords = oldPadding.Concat(new[]
        {
            """{"timestamp":"2026-07-13T08:00:00Z","type":"turn_context","payload":{"cwd":"C:\\Synthetic\\中文项目","model":"gpt-test"}}""",
            """{"timestamp":"2026-07-13T08:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":20,"cached_input_tokens":10,"output_tokens":3,"total_tokens":23},"total_token_usage":{"total_tokens":23},"model_context_window":200}}}"""
        });
        File.WriteAllText(unicodePath, string.Join('\n', unicodeRecords), new UTF8Encoding(false));
        var unicodeSnapshot = BoundedTailReader.ReadLatestSnapshot(unicodePath);
        NotNull(unicodeSnapshot, "reverse chunk tail snapshot");
        Equal("中文项目", unicodeSnapshot!.Workspace, "UTF-8 tail survives chunk boundaries and no final newline");

        var largeTrailingPath = Path.Combine(root, "large-trailing-response.jsonl");
        var usage = """{"timestamp":"2026-07-17T08:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":321,"cached_input_tokens":120,"output_tokens":45,"total_tokens":366},"total_token_usage":{"input_tokens":321,"cached_input_tokens":120,"output_tokens":45,"total_tokens":366},"model_context_window":1000}}}""";
        var manyTrailingPath = Path.Combine(root, "many-trailing-records.jsonl");
        var irrelevantRecords = string.Concat(Enumerable.Repeat("{\"type\":\"response_item\",\"payload\":{}}\n", 2_001));
        File.WriteAllText(manyTrailingPath, usage + "\n" + irrelevantRecords, new UTF8Encoding(false));
        var deepSnapshot = BoundedTailReader.ReadLatestSnapshot(manyTrailingPath);
        Equal(366L, deepSnapshot?.TaskTotal, "many irrelevant trailing records do not hide latest token snapshot");
        var oversizedIrrelevantRecord = "{\"type\":\"response_item\",\"payload\":\"" + new string('x', checked((int)BoundedTailReader.MaximumTailBytes + 1)) + "\"}";
        File.WriteAllText(largeTrailingPath, usage + "\n" + oversizedIrrelevantRecord + "\n", new UTF8Encoding(false));
        var recoveredSnapshot = BoundedTailReader.ReadLatestSnapshot(largeTrailingPath);
        Equal(366L, recoveredSnapshot?.TaskTotal, "oversized irrelevant trailing record does not hide latest token snapshot");
    });
}

void TestDiscovery()
{
    WithTemporaryDirectory(root =>
    {
        var now = DateTime.UtcNow;
        for (var index = 0; index < 70; index++)
        {
            var folder = Path.Combine(root, "2026", "07", (index % 3 + 1).ToString("00"));
            Directory.CreateDirectory(folder);
            var path = Path.Combine(folder, $"session-{index:00}.jsonl");
            File.WriteAllText(path, "{}", Encoding.UTF8);
            File.SetLastWriteTimeUtc(path, now.AddSeconds(-index));
        }

        var files = SessionDiscovery.GetActiveFiles(root, 30, 64, now);
        Equal(64, files.Count, "64-file cap");
        IsTrue(files.Zip(files.Skip(1), static (left, right) => left.LastWriteTimeUtc >= right.LastWriteTimeUtc).All(static ordered => ordered), "discovery order");
    });
}

void TestAggregation()
{
    var first = NewSnapshot(100, 60, 20, 1000, "model-a", DateTimeOffset.Parse("2026-07-13T08:00:00Z"));
    var second = NewSnapshot(200, 150, 30, 2000, "model-b", DateTimeOffset.Parse("2026-07-13T08:01:00Z"));
    var aggregate = SnapshotAggregator.Merge(new[] { first, second }, "{tasks} tasks / {models} models");
    NotNull(aggregate, "aggregate");
    Equal(300L, aggregate!.Input, "aggregate input");
    Equal(210L, aggregate.Cached, "aggregate cached");
    Equal(90L, aggregate.Uncached, "aggregate uncached");
    Equal(350L, aggregate.CallTotal, "aggregate call total");
    Equal(3000L, aggregate.TaskTotal, "aggregate task total");
    Equal(2, aggregate.ActiveTasks, "aggregate active task count");
    Equal("2 tasks / 2 models", aggregate.Model, "aggregate label");

    var fiveHourOnly = first with { AllowanceTimestamp = DateTimeOffset.Parse("2026-07-13T08:02:00Z"), FiveHourRemainingPercent = 71, WeeklyRemainingPercent = null };
    var weeklyOnly = second with { AllowanceTimestamp = DateTimeOffset.Parse("2026-07-13T08:03:00Z"), FiveHourRemainingPercent = null, WeeklyRemainingPercent = 88 };
    var splitAllowanceAggregate = SnapshotAggregator.GetLatestAllowance(new[] { fiveHourOnly, weeklyOnly });
    Equal(71d, splitAllowanceAggregate?.FiveHourRemainingPercent, "aggregate retains latest five-hour allowance");
    Equal(88d, splitAllowanceAggregate?.WeeklyRemainingPercent, "aggregate retains latest weekly allowance");
}

void TestOfficialAllowanceProtocol()
{
    var parsed = OfficialCodexAllowanceReader.TryParse(
        """{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":2,"windowDurationMins":300},"secondary":{"usedPercent":0,"windowDurationMins":10080}}}}""",
        out var allowance);
    IsTrue(parsed, "official app-server rate-limit response is accepted");
    Equal(98d, allowance?.FiveHourRemainingPercent, "official five-hour remaining");
    Equal(100d, allowance?.WeeklyRemainingPercent, "official weekly remaining");
    IsTrue(!OfficialCodexAllowanceReader.TryParse("""{"id":1,"result":{}}""", out _), "non-rate-limit response is rejected");
}

void TestTaskNumbers()
{
    var pool = new TaskNumberPool();
    var now = DateTimeOffset.Parse("2026-07-13T08:00:00Z");
    Equal(1, pool.Acquire(now), "first task number");
    pool.Release(1, 120, now);
    Equal(2, pool.Acquire(now.AddSeconds(119)), "cooldown prevents early reuse");
    Equal(1, pool.Acquire(now.AddSeconds(120)), "released number is reused");
    for (var index = 0; index < 10_000; index++)
    {
        var number = pool.Acquire(now.AddHours(index + 1));
        pool.Release(number, 0, now.AddHours(index + 1));
    }
    IsTrue(pool.ReleasedCount <= pool.MaximumReleased, "released number queue remains bounded");
}

void TestSessionEngine()
{
    WithTemporaryDirectory(root =>
    {
        var profile = Path.Combine(root, "profile");
        var sessions = Path.Combine(profile, ".codex", "sessions", "2026", "07", "17");
        Directory.CreateDirectory(sessions);
        var indexPath = Path.Combine(profile, ".codex", "session_index.jsonl");
        var sessionPath = Path.Combine(sessions, "session.jsonl");
        var now = DateTimeOffset.Parse("2026-07-17T08:00:00Z");
        var initial = new[]
        {
            """{"timestamp":"2026-07-17T07:59:00Z","type":"session_meta","payload":{"id":"session-1","cwd":"C:\\Synthetic\\engine-workspace","originator":"Codex Desktop","source":"vscode"}}""",
            """{"timestamp":"2026-07-17T07:59:01Z","type":"turn_context","payload":{"cwd":"C:\\Synthetic\\engine-workspace","model":"gpt-test"}}""",
            """{"timestamp":"2026-07-17T07:59:02Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}""",
            """{"timestamp":"2026-07-17T07:59:03Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120},"total_token_usage":{"total_tokens":1000},"model_context_window":1000}}}"""
        };
        File.WriteAllText(sessionPath, string.Join('\n', initial) + "\n", new UTF8Encoding(false));
        File.WriteAllText(
            indexPath,
            "{\"id\":\"session-1\",\"thread_name\":\"Synthetic engine title\",\"updated_at\":\"2026-07-17T08:00:00Z\"}\n",
            new UTF8Encoding(false));

        var engine = new SessionMonitorEngine(
            Path.Combine(profile, ".codex", "sessions"),
            indexPath,
            new HudRuntimeOptions
            {
                ActiveWindowMinutes = 60,
                CompletionGraceSeconds = 8,
                TerminalHoldSeconds = 0,
                AttentionOnCompleted = false,
                AttentionOnSettled = true
            });
        IsTrue(engine.RefreshActiveSessions(now), "initial engine discovery");
        var state = engine.GetVisibleStates(now).Single();
        Equal("session-1", state.SessionId, "engine session id");
        Equal("Synthetic engine title", state.ConversationLabel, "official session index title");
        Equal("engine-workspace", state.Workspace, "engine workspace");

        var waitingPath = Path.Combine(sessions, "waiting-session.jsonl");
        File.WriteAllText(waitingPath, string.Join('\n', new[]
        {
            """{"timestamp":"2026-07-17T08:00:00Z","type":"session_meta","payload":{"id":"waiting-1","cwd":"C:\\Synthetic\\waiting-workspace","originator":"Codex Desktop","source":"vscode"}}""",
            """{"timestamp":"2026-07-17T08:00:01Z","type":"turn_context","payload":{"cwd":"C:\\Synthetic\\waiting-workspace","model":"gpt-test"}}""",
            """{"timestamp":"2026-07-17T08:00:02Z","type":"event_msg","payload":{"type":"task_started","turn_id":"waiting-turn"}}"""
        }) + '\n', new UTF8Encoding(false));
        IsTrue(engine.RefreshActiveSessions(now), "identity-confirmed waiting session discovery");
        var waiting = engine.GetVisibleStates(now).Single(item => item.SessionId == "waiting-1");
        Equal<HudSnapshot?>(null, waiting.Snapshot, "waiting session has no token snapshot yet");
        Equal("waiting-workspace", waiting.Workspace, "waiting session keeps metadata workspace");
        File.AppendAllText(indexPath, "{\"id\":\"session-1\",\"thread_name\":\"Updated engine title\",\"updated_at\":\"2026-07-17T08:00:01Z\"}\n", new UTF8Encoding(false));
        IsTrue(engine.RefreshTitles(), "incremental engine title refresh");
        Equal("Updated engine title", state.ConversationLabel, "incremental official title update");

        File.AppendAllText(sessionPath, """{"timestamp":"2026-07-17T08:00:01Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1","last_agent_message":"Done."}}""", new UTF8Encoding(false));
        IsTrue(engine.Poll(now), "completion record consumed");
        Equal(DateTimeOffset.MinValue, state.TerminalAt, "completion grace retained");
        engine.HoldTerminalExits = true;
        IsTrue(engine.Poll(now.AddSeconds(8)), "completion grace advanced");
        Equal("completed", state.TerminalStatus, "completion confirmed");
        IsTrue(!state.TerminalExitStarted, "quiet task layout holds terminal exit");
        engine.HoldTerminalExits = false;
        IsTrue(engine.Poll(now.AddSeconds(8.1)), "terminal exit starts after quiet layout expands");
        IsTrue(state.TerminalExitStarted, "terminal exit released");

        File.AppendAllText(sessionPath, "\n" + """{"timestamp":"2026-07-17T08:00:09Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-2"}}""", new UTF8Encoding(false));
        IsTrue(engine.Poll(now.AddSeconds(9)), "continuation consumed");
        Equal(string.Empty, state.TerminalStatus, "new turn clears terminal state");
        Equal("active", engine.GetStatus(state, paused: false, now.AddSeconds(9)), "new turn is active");

        File.AppendAllText(sessionPath, "\n" + """{"timestamp":"2026-07-17T08:00:09.5Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-2","last_agent_message":""}}""", new UTF8Encoding(false));
        IsTrue(engine.Poll(now.AddSeconds(9.5)), "silent completion record consumed");
        Equal(string.Empty, state.TerminalStatus, "silent completion keeps the task monitorable");

        var irrelevant = "{\"timestamp\":\"2026-07-17T08:00:10Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"internal_progress\"}}\n";
        var burst = "\n" + string.Concat(Enumerable.Repeat(irrelevant, 5_000)) +
            "{\"timestamp\":\"2026-07-17T08:00:11Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":700,\"cached_input_tokens\":500,\"output_tokens\":77,\"total_tokens\":777},\"total_token_usage\":{\"total_tokens\":7777},\"model_context_window\":1000}}}";
        File.AppendAllText(sessionPath, burst, new UTF8Encoding(false));
        _ = engine.Poll(now.AddSeconds(11));
        IsTrue(engine.HasBacklog, "large appended burst is deferred by the per-session budget");
        for (var pass = 0; pass < 8 && engine.HasBacklog; pass++)
        {
            _ = engine.PollBacklog(now.AddSeconds(11));
        }
        IsTrue(!engine.HasBacklog, "session backlog drains across responsive passes");
        Equal(7777L, state.Snapshot?.TaskTotal, "record after bounded burst is eventually consumed");
        IsTrue(engine.AdvanceLifecycleOnly(now.AddSeconds(200)), "per-task active-to-idle transition is material");
        Equal("idle", engine.GetStatus(state, paused: false, now.AddSeconds(200)), "lifecycle-only transition reaches idle");
        Equal("settled", state.AttentionReason, "settled transition records targeted attention");
        IsTrue(engine.AdvanceLifecycleOnly(now.AddSeconds(207)), "expired attention is material");
        Equal(string.Empty, state.AttentionReason, "expired attention restores the normal surface");

        var recipe = new AgentAnimationRecipe(new[] { "glow", "flow" }, "#FF7C3AED", 0.8, 420, 3, 34, 1.03, "right-to-left");
        IsTrue(engine.AcceptAgentNotice(state.Number, "Synthetic notice", 12, recipe, now.AddSeconds(208)), "agent notice accepted");
        Equal(recipe, state.AgentNoticeRecipe, "expressive recipe retained by platform-neutral state");
    });
}

void TestSessionSources()
{
    var desktopIdentity = SessionIdentityReader.ParseLine("""{"type":"session_meta","payload":{"id":"desktop","cwd":"C:\\Synthetic\\desktop","originator":"Codex Desktop","source":"vscode","model_provider":"openai"}}""");
    Equal("desktop", desktopIdentity.ClientSurface, "desktop source classification");
    Equal("openai", desktopIdentity.ModelProvider, "desktop provider classification");
    var vsCodeIdentity = SessionIdentityReader.ParseLine("""{"type":"session_meta","payload":{"id":"vscode","cwd":"C:\\Synthetic\\vscode","originator":"codex_vscode","source":"vscode","model_provider":"openai"}}""");
    Equal("vscode", vsCodeIdentity.ClientSurface, "VS Code source classification");
    Equal("openai", vsCodeIdentity.ModelProvider, "VS Code provider classification");
    var cliIdentity = SessionIdentityReader.ParseLine("""{"type":"session_meta","payload":{"id":"cli","cwd":"C:\\Synthetic\\cli","originator":"codex-tui","source":"cli","model_provider":"openai"}}""");
    Equal("cli", cliIdentity.ClientSurface, "CLI source classification");
    Equal("openai", cliIdentity.ModelProvider, "CLI OpenAI provider classification");
    var deepSeekIdentity = SessionIdentityReader.ParseLine("""{"type":"session_meta","payload":{"id":"deepseek","cwd":"C:\\Synthetic\\deepseek","originator":"codex-tui","source":"cli","model_provider":"deepseek"}}""");
    Equal("cli", deepSeekIdentity.ClientSurface, "DeepSeek remains a CLI task");
    Equal("deepseek", deepSeekIdentity.ModelProvider, "DeepSeek provider classification");
    var internalIdentity = SessionIdentityReader.ParseLine("""{"type":"session_meta","payload":{"id":"internal","source":{"subagent":{"kind":"review"}},"originator":"codex-tui","model_provider":"deepseek"}}""");
    IsTrue(internalIdentity.IsInternalSession, "CLI subagent remains excluded");

    WithTemporaryDirectory(root =>
    {
        var defaultRoot = Path.Combine(root, ".codex");
        var deepSeekRoot = Path.Combine(root, ".codex-deepseek");
        var defaultSessions = Path.Combine(defaultRoot, "sessions", "2026", "08", "10");
        var deepSeekSessions = Path.Combine(deepSeekRoot, "sessions", "2026", "08", "10");
        Directory.CreateDirectory(defaultSessions);
        Directory.CreateDirectory(deepSeekSessions);
        var now = DateTimeOffset.Parse("2026-08-10T08:00:00Z");

        static string Session(string id, string workspace, string originator, string source, string provider, string model) => string.Join('\n', new[]
        {
            $"{{\"timestamp\":\"2026-08-10T07:59:00Z\",\"type\":\"session_meta\",\"payload\":{{\"id\":\"{id}\",\"cwd\":\"C:\\\\Synthetic\\\\{workspace}\",\"originator\":\"{originator}\",\"source\":\"{source}\",\"model_provider\":\"{provider}\"}}}}",
            $"{{\"timestamp\":\"2026-08-10T07:59:01Z\",\"type\":\"turn_context\",\"payload\":{{\"cwd\":\"C:\\\\Synthetic\\\\{workspace}\",\"model\":\"{model}\"}}}}",
            "{\"timestamp\":\"2026-08-10T07:59:02Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":100,\"cached_input_tokens\":60,\"output_tokens\":20,\"total_tokens\":120},\"total_token_usage\":{\"total_tokens\":120},\"model_context_window\":1000}}}"
        }) + '\n';

        var desktopPath = Path.Combine(defaultSessions, "desktop.jsonl");
        var vsCodePath = Path.Combine(defaultSessions, "vscode.jsonl");
        var cliPath = Path.Combine(defaultSessions, "cli.jsonl");
        var deepSeekPath = Path.Combine(deepSeekSessions, "deepseek.jsonl");
        File.WriteAllText(desktopPath, Session("desktop-1", "desktop-project", "Codex Desktop", "vscode", "openai", "gpt-future"), new UTF8Encoding(false));
        File.WriteAllText(vsCodePath, Session("vscode-1", "vscode-project", "codex_vscode", "vscode", "openai", "gpt-future"), new UTF8Encoding(false));
        File.WriteAllText(cliPath, Session("cli-1", "cli-project", "codex-tui", "cli", "openai", "gpt-next"), new UTF8Encoding(false));
        File.WriteAllText(deepSeekPath, Session("deepseek-1", "deepseek-project", "codex-tui", "cli", "deepseek", "deepseek-next"), new UTF8Encoding(false));
        foreach (var path in new[] { desktopPath, vsCodePath, cliPath, deepSeekPath }) File.SetLastWriteTimeUtc(path, now.UtcDateTime);

        var profiles = new[]
        {
            new SessionProfile("codex", "Codex", Path.Combine(defaultRoot, "sessions"), Path.Combine(defaultRoot, "session_index.jsonl"), "unknown", string.Empty),
            new SessionProfile("deepseek", "DeepSeek", Path.Combine(deepSeekRoot, "sessions"), Path.Combine(deepSeekRoot, "session_index.jsonl"), "cli", "deepseek")
        };
        var options = new HudRuntimeOptions { ActiveWindowMinutes = 60, DesktopSessionsEnabled = true, VsCodeSessionsEnabled = true, DefaultCliSessionsEnabled = true, DeepSeekCliSessionsEnabled = true };
        var engine = new SessionMonitorEngine(profiles, options);
        IsTrue(engine.RefreshActiveSessions(now), "multi-profile discovery");
        var states = engine.GetVisibleStates(now);
        Equal(4, states.Count, "desktop, VS Code, OpenAI CLI and DeepSeek CLI are all visible");
        Equal(4, states.Select(static state => state.Number).Distinct().Count(), "task numbering is global across profiles");
        Equal("desktop", states.Single(state => state.SessionId == "desktop-1").ClientSurface, "desktop state source");
        Equal("vscode", states.Single(state => state.SessionId == "vscode-1").ClientSurface, "VS Code state source");
        Equal("openai", states.Single(state => state.SessionId == "cli-1").ModelProvider, "default CLI provider");
        Equal("deepseek", states.Single(state => state.SessionId == "deepseek-1").ModelProvider, "DeepSeek profile provider");

        engine.UpdateOptions(options with { DefaultCliSessionsEnabled = false });
        Equal(3, engine.GetVisibleStates(now).Count, "default CLI filter does not hide desktop, VS Code, or DeepSeek");
        engine.UpdateOptions(options with { DeepSeekCliSessionsEnabled = false });
        Equal(3, engine.GetVisibleStates(now).Count, "DeepSeek filter does not hide default-profile tasks");
        engine.UpdateOptions(options with { DesktopSessionsEnabled = false, VsCodeSessionsEnabled = false, DefaultCliSessionsEnabled = true, DeepSeekCliSessionsEnabled = false });
        var cliOnly = engine.GetVisibleStates(now);
        Equal(1, cliOnly.Count, "source filters isolate default CLI");
        Equal("cli-1", cliOnly.Single().SessionId, "correct default CLI task remains");
    });
}

void TestLockedSessionRecovery()
{
    WithTemporaryDirectory(root =>
    {
        const string sessionId = "019f5f91-0027-7023-81cb-db9224ab26ed";
        const string unknownId = "019f5f91-0027-7023-81cb-db9224ab26ee";
        const string activeId = "019f5f91-0027-7023-81cb-db9224ab26ef";
        var profile = Path.Combine(root, ".codex");
        var sessionsRoot = Path.Combine(profile, "sessions");
        var sessions = Path.Combine(sessionsRoot, "2026", "08", "10");
        Directory.CreateDirectory(sessions);
        var indexPath = Path.Combine(profile, "session_index.jsonl");
        var sessionPath = Path.Combine(sessions, $"rollout-2026-08-10T08-00-00-{sessionId}.jsonl");
        var unknownPath = Path.Combine(sessions, $"rollout-2026-08-10T07-59-00-{unknownId}.jsonl");
        var activePath = Path.Combine(sessions, $"rollout-2026-08-10T09-29-00-{activeId}.jsonl");
        var now = DateTimeOffset.Parse("2026-08-10T09:30:00Z");

        static string Session(string id, string workspace) => string.Join('\n', new[]
        {
            $"{{\"timestamp\":\"2026-08-10T08:00:00Z\",\"type\":\"session_meta\",\"payload\":{{\"id\":\"{id}\",\"cwd\":\"C:\\\\Synthetic\\\\{workspace}\",\"originator\":\"Codex Desktop\",\"source\":\"vscode\",\"model_provider\":\"openai\"}}}}",
            $"{{\"timestamp\":\"2026-08-10T08:00:01Z\",\"type\":\"turn_context\",\"payload\":{{\"cwd\":\"C:\\\\Synthetic\\\\{workspace}\",\"model\":\"gpt-future\"}}}}",
            "{\"timestamp\":\"2026-08-10T08:00:02Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-1\"}}",
            "{\"timestamp\":\"2026-08-10T08:00:03Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":100,\"cached_input_tokens\":60,\"output_tokens\":20,\"total_tokens\":120},\"total_token_usage\":{\"total_tokens\":1000},\"model_context_window\":1000}}}"
        }) + '\n';

        File.WriteAllText(sessionPath, Session(sessionId, "locked-project"), new UTF8Encoding(false));
        File.WriteAllText(unknownPath, Session(unknownId, "unindexed-project"), new UTF8Encoding(false));
        File.WriteAllText(activePath, Session(activeId, "foreground-project"), new UTF8Encoding(false));
        File.SetLastWriteTimeUtc(sessionPath, now.UtcDateTime.AddMinutes(-90));
        File.SetLastWriteTimeUtc(unknownPath, now.UtcDateTime.AddMinutes(-91));
        File.SetLastWriteTimeUtc(activePath, now.UtcDateTime);
        File.WriteAllText(
            indexPath,
            $"{{\"id\":\"{sessionId}\",\"thread_name\":\"Long running indexed task\",\"updated_at\":\"2026-08-10T08:00:00Z\"}}\n" +
            $"{{\"id\":\"{activeId}\",\"thread_name\":\"Foreground active task\",\"updated_at\":\"2026-08-10T09:29:00Z\"}}\n",
            new UTF8Encoding(false));

        var engine = new SessionMonitorEngine(
            sessionsRoot,
            indexPath,
            new HudRuntimeOptions { ActiveWindowMinutes = 30, MaximumFiles = 64 });

        using (var locked = new FileStream(sessionPath, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        using (var unknownLocked = new FileStream(unknownPath, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            var discovery = SessionDiscovery.GetActiveFiles(sessionsRoot, 30, 64, now.UtcDateTime);
            IsTrue(discovery.Any(file => file.FullName == sessionPath && file.ReadBlocked), "old sharing-blocked file bypasses write window");
            IsTrue(engine.RefreshActiveSessions(now), "locked session engine discovery");
            var visible = engine.GetVisibleStates(now);
            Equal(2, visible.Count, "readable foreground and locked background tasks coexist");
            IsTrue(visible.Any(state => state.SessionId == activeId && !state.IdentityProvisional), "normal active task remains visible");
            IsTrue(visible.All(state => state.SessionId != unknownId), "unindexed locked file stays behind the privacy boundary");
            var provisional = visible.Single(state => state.SessionId == sessionId);
            Equal(sessionId, provisional.SessionId, "rollout filename supplies provisional session id");
            Equal("Long running indexed task", provisional.ConversationLabel, "official index supplies provisional title");
            IsTrue(provisional.IdentityProvisional, "locked identity remains explicitly provisional");
            IsTrue(provisional.IsReadBlocked, "sharing lock is retained in state");
            Equal<HudSnapshot?>(null, provisional.Snapshot, "locked task does not fabricate usage");
            Equal("listening", engine.GetStatus(provisional, paused: false, now), "locked task renders as listening");
        }

        IsTrue(engine.RefreshActiveSessions(now.AddSeconds(1)), "unlock refresh resolves provisional task");
        var resolved = engine.GetVisibleStates(now.AddSeconds(1)).Single(state => state.SessionId == sessionId);
        IsTrue(!resolved.IdentityProvisional, "real session metadata replaces provisional identity");
        IsTrue(!resolved.IsReadBlocked, "unlock clears sharing-block state");
        Equal("desktop", resolved.ClientSurface, "resolved task restores desktop source");
        Equal("locked-project", resolved.Workspace, "resolved task restores workspace");
        Equal(1000L, resolved.Snapshot?.TaskTotal, "bounded tail hydration restores usage");
    });
}

void TestStateDatabaseHeartbeat()
{
    WithTemporaryDirectory(root =>
    {
        var now = DateTimeOffset.UtcNow;
        var codexRoot = Path.Combine(root, ".codex");
        var sessionsRoot = Path.Combine(codexRoot, "sessions");
        var dateRoot = Path.Combine(sessionsRoot, "2026", "08", "10");
        Directory.CreateDirectory(dateRoot);
        var indexPath = Path.Combine(codexRoot, "session_index.jsonl");
        var activeId = "019fe824-013e-7222-939e-3c06be0ca511";
        var internalId = "019fe836-6e7d-7d63-b7e0-86ee82704fa5";
        var staleId = "019fe7f0-e8c6-7241-9404-d61924f04adf";
        var activePath = Path.Combine(dateRoot, $"rollout-2026-08-10T04-08-21-{activeId}.jsonl");
        var internalPath = Path.Combine(dateRoot, $"rollout-2026-08-10T04-28-29-{internalId}.jsonl");
        var stalePath = Path.Combine(dateRoot, $"rollout-2026-08-10T03-12-33-{staleId}.jsonl");
        var encoding = new UTF8Encoding(false);

        File.WriteAllText(activePath,
            $"{{\"timestamp\":\"{now.AddHours(-10):O}\",\"type\":\"session_meta\",\"payload\":{{\"id\":\"{activeId}\",\"cwd\":\"C:\\\\Synthetic\\\\heartbeat-project\",\"originator\":\"Codex Desktop\",\"source\":\"vscode\",\"model_provider\":\"openai\"}}}}\n" +
            $"{{\"timestamp\":\"{now.AddHours(-10):O}\",\"type\":\"event_msg\",\"payload\":{{\"type\":\"token_count\",\"info\":{{\"last_token_usage\":{{\"input_tokens\":100,\"cached_input_tokens\":80,\"output_tokens\":5,\"total_tokens\":105}},\"total_token_usage\":{{\"input_tokens\":1000,\"cached_input_tokens\":800,\"output_tokens\":50,\"total_tokens\":1050}},\"model_context_window\":200000}}}}}}\n" +
            $"{{\"timestamp\":\"{now.AddHours(-9):O}\",\"type\":\"event_msg\",\"payload\":{{\"type\":\"task_complete\",\"turn_id\":\"old-turn\",\"last_agent_message\":\"done\"}}}}\n",
            encoding);
        File.WriteAllText(internalPath, "{}\n", encoding);
        File.WriteAllText(stalePath, "{}\n", encoding);
        File.SetLastWriteTimeUtc(activePath, now.AddHours(-9).UtcDateTime);
        File.SetLastWriteTimeUtc(internalPath, now.AddMinutes(-1).UtcDateTime);
        File.SetLastWriteTimeUtc(stalePath, now.AddHours(-8).UtcDateTime);
        File.WriteAllText(indexPath,
            $"{{\"id\":\"{activeId}\",\"thread_name\":\"Background parent task\"}}\n" +
            $"{{\"id\":\"{staleId}\",\"thread_name\":\"Stale task\"}}\n",
            encoding);

        var activitySource = new SyntheticSessionActivitySource(new[]
        {
            new SessionActivity(activeId, @"\\?\" + activePath, now.AddSeconds(-20)),
            new SessionActivity(internalId, internalPath, now.AddSeconds(-10)),
            new SessionActivity(staleId, stalePath, now.AddHours(-8))
        });

        var profile = new SessionProfile(
            SessionProfile.DefaultId,
            "Codex",
            sessionsRoot,
            indexPath,
            "unknown",
            string.Empty);
        var engine = new SessionMonitorEngine(
            new[] { profile },
            new HudRuntimeOptions { ActiveWindowMinutes = 30, MaximumFiles = 64 },
            activitySource: activitySource);
        IsTrue(engine.RefreshActiveSessions(now), "database heartbeat discovers old parent rollout");
        var visible = engine.GetVisibleStates(now);
        Equal(1, visible.Count, "guardian and stale rows stay hidden");
        Equal(activeId, visible[0].SessionId, "old parent remains visible");
        Equal("active", engine.GetStatus(visible[0], paused: false, now), "runtime heartbeat overrides stale completed tail");
        Equal(string.Empty, visible[0].TerminalStatus, "stale terminal state is cleared without fabricating completion");

        var fastEngine = new SessionMonitorEngine(
            new[] { profile },
            new HudRuntimeOptions { ActiveWindowMinutes = 30, MaximumFiles = 64 },
            activitySource: activitySource);
        IsTrue(fastEngine.RefreshRuntimeSessions(now), "fast runtime reconciliation discovers a missing active task");
        Equal(activeId, fastEngine.GetVisibleStates(now).Single().SessionId, "fast runtime discovery preserves identity");

        IsTrue(!engine.RefreshActiveSessions(now.AddMinutes(4)), "aged runtime activity remains discoverable inside the configured window");
        Equal(1, engine.GetVisibleStates(now.AddMinutes(4)).Count, "long-running resumed task is not dropped after the three-minute active-color window");
        Equal("idle", engine.GetStatus(engine.GetVisibleStates(now.AddMinutes(4)).Single(), paused: false, now.AddMinutes(4)), "aged runtime activity is retained without staying falsely active");

        var agedFastEngine = new SessionMonitorEngine(
            new[] { profile },
            new HudRuntimeOptions { ActiveWindowMinutes = 30, MaximumFiles = 64 },
            activitySource: activitySource);
        IsTrue(agedFastEngine.RefreshRuntimeSessions(now.AddMinutes(4)), "fast runtime reconciliation discovers a resumed task older than three minutes");
        Equal(activeId, agedFastEngine.GetVisibleStates(now.AddMinutes(4)).Single().SessionId, "aged fast discovery preserves the resumed task");

        IsTrue(engine.RefreshActiveSessions(now.AddMinutes(31)), "expired discovery window removes old parent");
        Equal(0, engine.GetVisibleStates(now.AddMinutes(31)).Count, "expired discovery activity does not leave a ghost task");
    });
}

void TestFormatting()
{
    Equal("999,999", HudFormatting.FormatNumber(999_999, "auto"), "auto exact threshold");
    Equal("1M", HudFormatting.FormatNumber(1_000_000, "auto"), "compact million");
    Equal("~$1.15", HudFormatting.FormatCost(1.15), "cost format");
    Equal("60%", HudFormatting.FormatCacheHitRate(100, 60), "cache hit rate");
    Equal("99.99%", HudFormatting.FormatCacheHitRate(1_000_000, 999_999), "near-perfect cache hit does not round to 100 percent");
    Equal("99.99%", HudFormatting.FormatPercent(99.9999), "near-full context does not round to 100 percent");
    Equal("--", HudFormatting.FormatCacheHitRate(0, 0), "cache hit rate without input");
    Equal("100%", HudFormatting.FormatCacheHitRate(100, 120), "cache hit rate clamps malformed cached input");
    var futureMetrics = HudFormatting.GetMetrics(
        new HudSnapshot { Input = 200, Cached = 150, Model = "gpt-9.9-nebula" },
        new Dictionary<string, bool> { ["model"] = true, ["cacheHitRate"] = true },
        new Dictionary<string, string> { ["model"] = "Model", ["cacheHitRate"] = "Cache hit rate" },
        "exact");
    Equal("gpt-9.9-nebula", futureMetrics.Single(metric => metric.Key == "model").Value, "unknown future model remains monitorable");
    Equal("75%", futureMetrics.Single(metric => metric.Key == "cacheHitRate").Value, "unknown future model keeps generic token metrics");
    var metrics = HudFormatting.GetMetrics(
        new HudSnapshot { FiveHourRemainingPercent = 86, WeeklyRemainingPercent = 82 },
        new Dictionary<string, bool> { ["fiveHourRemaining"] = true },
        new Dictionary<string, string> { ["fiveHourRemaining"] = "5-hour remaining" },
        "exact");
    Equal("86%", metrics.Single().Value, "five-hour allowance formatting");
    var hierarchySnapshot = new HudSnapshot
    {
        Input = 10_000,
        Cached = 9_500,
        Uncached = 500,
        Output = 250,
        CallTotal = 10_250,
        TaskTotal = 50_000,
        ContextPercent = 25,
        ContextWindow = 40_000,
        Model = "deepseek-chat"
    };
    var labels = new Dictionary<string, string>();
    var compact = HudFormatting.GetTaskListMetrics(hierarchySnapshot, "compact", labels, "exact");
    Equal("context,model,cacheHitRate", string.Join(',', compact.Primary.Select(static metric => metric.Key)), "compact tier keeps context, model, and cache efficiency");
    var balanced = HudFormatting.GetTaskListMetrics(hierarchySnapshot, "balanced", labels, "exact");
    Equal("context,model,cacheHitRate,callTotal", string.Join(',', balanced.Primary.Select(static metric => metric.Key)), "balanced tier adds the current call total");
    var detailed = HudFormatting.GetTaskListMetrics(hierarchySnapshot, "detailed", labels, "exact");
    IsTrue(detailed.Diagnostics.Any(static metric => metric.Key == "contextWindow"), "detailed tier exposes provider-specific context capacity");
    IsTrue(detailed.Diagnostics.Any(static metric => metric.Key == "taskTotal"), "detailed tier keeps cumulative task accounting off the primary row");
    var allFields = new Dictionary<string, bool>
    {
        ["input"] = true,
        ["callTotal"] = true,
        ["activeTasks"] = true,
        ["cacheHitRate"] = true,
        ["taskTotal"] = true,
        ["context"] = true,
        ["model"] = true,
        ["updated"] = true
    };
    var summary = HudFormatting.GetSummaryMetrics(hierarchySnapshot, allFields, labels, "exact");
    IsTrue(summary.All(static metric => metric.Key is not ("cacheHitRate" or "taskTotal" or "context" or "model" or "updated")), "summary excludes per-task-only metrics");
    Equal(3, HudFormatting.GetContextAlertLevel(98, new[] { 75d, 90d, 98d }), "context level");
    Equal("75,90,98", string.Join(',', HudFormatting.ParseContextAlertThresholds(new[] { "98", "75", "90" })!), "threshold normalization");
    NotNull(HudFormatting.GetTaskDeepLink("019f69dc-91bf-7c33-b47b-604b9eaa04b6"), "safe deep link");
    Equal<string?>(null, HudFormatting.GetTaskDeepLink("../unsafe"), "unsafe deep link rejected");
}

void TestPlacement()
{
    var topRight = HudPlacement.GetPreset("top-right", 0, 0, 1920, 1040, 700, 80, 18);
    Equal(1238d, topRight.Left, "top-right window offsets transparent chrome");
    Equal(-18d, topRight.Top, "top edge offsets transparent chrome");
    Equal(1920d, topRight.Left + 700 - 18, "visible shell touches right edge");
    Equal(0d, topRight.Top + 18, "visible shell touches top edge");
    var custom = HudPlacement.ClampCustom(-1000, 5000, 0, 0, 1920, 1040, 700, 80, 18);
    Equal(-18d, custom.Left, "custom position clamps to visible left edge");
    Equal(978d, custom.Top, "custom position clamps to visible bottom edge");
    var unsnapped = HudPlacement.ClampCustom(12 - 18, 15 - 18, 0, 0, 1920, 1040, 700, 80, 18);
    Equal(-6d, unsnapped.Left, "near-left custom placement is not snapped");
    Equal(-3d, unsnapped.Top, "near-top custom placement is not snapped");
}

void TestSurfaceEffects()
{
    var dark = SurfaceEffects.Create("#EE111827", "#FFF8FAFC");
    var light = SurfaceEffects.Create("#F4F8FAFC", "#FF172033");
    Equal("dark", dark.Tone, "dark classification");
    Equal("light", light.Tone, "light classification");
    IsTrue(dark.PeakOpacity > light.PeakOpacity, "dark peak compensation");
    IsTrue(dark.Blur > light.Blur, "dark blur compensation");
}

void TestConfiguration()
{
    WithTemporaryDirectory(root =>
    {
        var pluginRoot = Path.Combine(root, "plugin");
        var localRoot = Path.Combine(root, "local");
        var home = Path.Combine(root, "home");
        Directory.CreateDirectory(pluginRoot);
        Directory.CreateDirectory(Path.Combine(pluginRoot, "locales"));
        File.Copy(Path.Combine(repositoryRoot, "config.default.json"), Path.Combine(pluginRoot, "config.default.json"));
        File.Copy(Path.Combine(repositoryRoot, "locales", "en.json"), Path.Combine(pluginRoot, "locales", "en.json"));
        var paths = HudPaths.Create(pluginRoot, localRoot, home);
        Directory.CreateDirectory(paths.StateRoot);
        File.WriteAllText(paths.ConfigPath, """{"multiTask":"corrupt","behavior":{"contextAlerts":"corrupt"},"opacity":-0.01,"alwaysOnTop":"yes","fontSize":"large","fields":{"context":"yes"},"statusColors":{"active":17}}""");
        var config = HudConfigStore.Load(paths);
        Equal("summary", config["multiTask"]!["displayMode"]!.GetValue<string>(), "object/scalar corruption recovery");
        Equal(0d, config["opacity"]!.GetValue<double>(), "opacity clamp");
        var settings = HudSettings.From(config);
        Equal("summary", settings.MultiTask.DisplayMode, "typed settings projection");
        Equal(true, settings.SessionSources.VsCode, "missing VS Code source setting defaults to enabled");
        Equal("always", settings.MultiTask.NameMode, "conversation subtitle is visible by default");
        Equal(0d, settings.Opacity, "typed numeric settings projection");
        Equal(true, settings.AlwaysOnTop, "wrong scalar type retains default boolean");
        Equal(14d, settings.FontSize, "wrong scalar type retains default number");
        Equal(false, settings.Fields["context"], "wrong nested scalar type retains default");
        Equal("#FF34C759", settings.StatusColors["active"], "wrong dictionary scalar type retains default");
        ((JsonObject)config["agentNotifications"]!)["enabled"] = true;
        ((JsonObject)config["agentNotifications"]!)["permission"] = "expressive";
        settings = HudSettings.From(config);
        Equal(true, settings.AgentNotifications.Enabled, "typed agent-notification boolean projection");
        Equal("expressive", settings.AgentNotifications.Permission, "typed agent-notification permission projection");
        HudConfigStore.Save(paths, config);
        NotNull(JsonNode.Parse(File.ReadAllText(paths.ConfigPath)), "saved config JSON");
        var reloaded = HudSettings.From(HudConfigStore.Load(paths));
        Equal(true, reloaded.AgentNotifications.Enabled, "saved agent-notification boolean survives config merge");
        Equal("expressive", reloaded.AgentNotifications.Permission, "saved agent-notification permission survives config merge");
        Equal(0, Directory.EnumerateFiles(paths.StateRoot, "settings.json.*.tmp").Count(), "atomic config save leaves no temporary file");
    });
}

void TestMacPortability()
{
    WithTemporaryDirectory(root =>
    {
        var pluginRoot = Path.Combine(root, "CodexMonitorHUD.app", "Contents", "MacOS");
        var syntheticHome = Path.Combine(root, "Users", "synthetic-user");
        Directory.CreateDirectory(pluginRoot);
        Directory.CreateDirectory(syntheticHome);
        var paths = HudPaths.CreateForPlatform(pluginRoot, HudPlatform.MacOS, syntheticHome);
        Equal(
            Path.Combine(syntheticHome, "Library", "Application Support", "CodexMonitorHUD"),
            paths.StateRoot,
            "macOS state root");
        Equal(Path.Combine(syntheticHome, ".codex", "sessions"), paths.SessionsRoot, "macOS sessions root");

        var unixContext = HudRecordParser.Parse(
            """{"type":"turn_context","payload":{"cwd":"/Users/synthetic-user/项目/portable-workspace","model":"gpt-test"}}""");
        Equal("portable-workspace", unixContext?.Workspace, "Unix workspace leaf");

        var codexRoot = Path.Combine(syntheticHome, ".codex");
        var missingSessionsRoot = Path.Combine(codexRoot, "sessions");
        Directory.CreateDirectory(codexRoot);
        using var tracker = new SessionChangeTracker(
            missingSessionsRoot,
            pathComparer: StringComparer.Ordinal);
        _ = tracker.ConsumeDirty();
        _ = tracker.ConsumeStructural();
        var dateRoot = Path.Combine(missingSessionsRoot, "2026", "07", "19");
        Directory.CreateDirectory(dateRoot);
        var firstPath = Path.Combine(dateRoot, "CaseSensitive.jsonl");
        var secondPath = Path.Combine(dateRoot, "casesensitive.jsonl");
        File.WriteAllText(firstPath, "{}\n", new UTF8Encoding(false));
        File.WriteAllText(secondPath, "{}\n", new UTF8Encoding(false));
        SpinWait.SpinUntil(() => tracker.ConsumeDirty(), TimeSpan.FromSeconds(3));
        var changed = tracker.DrainChangedPaths();
        IsTrue(changed.Count >= 1, "watcher observes nested creation below a missing sessions root");
        Equal(2, new HashSet<string>(new[] { firstPath, secondPath }, StringComparer.Ordinal).Count, "case-sensitive path identity");

        var indexPath = Path.Combine(codexRoot, "session_index.jsonl");
        File.WriteAllText(indexPath, "{\"id\":\"mac-one\",\"thread_name\":\"初始标题\"}\n", new UTF8Encoding(false));
        var index = new SessionTitleIndex();
        IsTrue(index.Refresh(indexPath), "macOS UTF-8 title index loads");
        File.Move(indexPath, indexPath + ".old");
        File.WriteAllText(indexPath, "{\"id\":\"mac-two\",\"thread_name\":\"替换标题\"}\n", new UTF8Encoding(false));
        IsTrue(index.Refresh(indexPath), "atomic title-index replacement is reconciled");
        Equal(string.Empty, index.GetTitle("mac-one"), "replacement drops stale title");
        Equal("替换标题", index.GetTitle("mac-two"), "replacement keeps UTF-8 title");
    });
}

void TestPricing()
{
    var catalog = PricingCatalog.Load(repositoryRoot);
    IsTrue(catalog.Loaded, "built-in pricing loaded");
    var snapshot = NewSnapshot(100, 50, 20, 1_100_000, "gpt-5.6-luna", DateTimeOffset.Now) with
    {
        TaskInput = 1_000_000,
        TaskCached = 500_000,
        TaskOutput = 100_000
    };
    var estimate = catalog.Estimate(snapshot);
    NotNull(estimate, "known model estimate");
    Equal(1.15d, Math.Round(estimate!.CostUsd, 6), "current cached-input pricing");
    var datedEstimate = catalog.Estimate(snapshot with { Model = "gpt-5.6-luna-2026-08-10" });
    NotNull(datedEstimate, "dated model snapshot estimate");
    Equal("gpt-5.6-luna", datedEstimate!.PricedAs, "dated snapshot resolves to catalog model");
    Equal(1.15d, Math.Round(datedEstimate.CostUsd, 6), "dated snapshot inherits matching catalog price");
    Equal<CostEstimate?>(null, catalog.Estimate(snapshot with { Model = "not-priced" }), "unknown model is not guessed");
}

HudSnapshot NewSnapshot(long input, long cached, long output, long taskTotal, string model, DateTimeOffset timestamp) => new()
{
    Timestamp = timestamp,
    Input = input,
    Cached = cached,
    Uncached = input - cached,
    Output = output,
    CallTotal = input + output,
    TaskInput = input,
    TaskCached = cached,
    TaskUncached = input - cached,
    TaskOutput = output,
    TaskTotal = taskTotal,
    ContextWindow = 200_000,
    ContextPercent = input * 100.0 / 200_000,
    Model = model
};

void WithTemporaryDirectory(Action<string> action)
{
    var root = Path.Combine(Path.GetTempPath(), "CodexMonitorHud.Core.Tests", Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(root);
    try
    {
        action(root);
    }
    finally
    {
        Directory.Delete(root, recursive: true);
    }
}

string FindRepositoryRoot()
{
    var current = new DirectoryInfo(Environment.CurrentDirectory);
    while (current is not null)
    {
        if (File.Exists(Path.Combine(current.FullName, "config.default.json")))
        {
            return current.FullName;
        }
        current = current.Parent;
    }
    throw new DirectoryNotFoundException("Repository root was not found.");
}

void IsTrue(bool condition, string message)
{
    if (!condition)
    {
        throw new InvalidOperationException("Assertion failed: " + message);
    }
}

void NotNull<T>(T? value, string message)
{
    if (value is null)
    {
        throw new InvalidOperationException("Assertion failed: " + message);
    }
}

void Equal<T>(T expected, T actual, string message)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException($"Assertion failed: {message}. Expected '{expected}', actual '{actual}'.");
    }
}

sealed class SyntheticSessionActivitySource(IEnumerable<SessionActivity> activities) : ISessionActivitySource
{
    private readonly IReadOnlyList<SessionActivity> _activities = activities.ToArray();

    public IReadOnlyList<SessionActivity> GetRecentUserSessions(
        SessionProfile profile,
        DateTimeOffset cutoff,
        int maximumRows) => _activities
            .Where(activity => activity.UpdatedAt >= cutoff)
            .Take(Math.Max(1, maximumRows))
            .ToArray();
}
