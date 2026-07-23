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
    ("JSON line splitting", TestLineSplitting),
    ("incremental title index", TestTitleIndex),
    ("bounded tail snapshot", TestBoundedTail),
    ("multi-date discovery and cap", TestDiscovery),
    ("snapshot aggregation", TestAggregation),
    ("task number cooldown", TestTaskNumbers),
    ("session state engine", TestSessionEngine),
    ("formatting and deep links", TestFormatting),
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

void TestFormatting()
{
    Equal("999,999", HudFormatting.FormatNumber(999_999, "auto"), "auto exact threshold");
    Equal("1M", HudFormatting.FormatNumber(1_000_000, "auto"), "compact million");
    Equal("~$1.15", HudFormatting.FormatCost(1.15), "cost format");
    Equal(3, HudFormatting.GetContextAlertLevel(98, new[] { 75d, 90d, 98d }), "context level");
    Equal("75,90,98", string.Join(',', HudFormatting.ParseContextAlertThresholds(new[] { "98", "75", "90" })!), "threshold normalization");
    NotNull(HudFormatting.GetTaskDeepLink("019f69dc-91bf-7c33-b47b-604b9eaa04b6"), "safe deep link");
    Equal<string?>(null, HudFormatting.GetTaskDeepLink("../unsafe"), "unsafe deep link rejected");
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
        File.WriteAllText(paths.ConfigPath, """{"multiTask":"corrupt","behavior":{"contextAlerts":"corrupt"},"opacity":0.01,"alwaysOnTop":"yes","fontSize":"large","fields":{"context":"yes"},"statusColors":{"active":17}}""");
        var config = HudConfigStore.Load(paths);
        Equal("summary", config["multiTask"]!["displayMode"]!.GetValue<string>(), "object/scalar corruption recovery");
        Equal(0.15d, config["opacity"]!.GetValue<double>(), "opacity clamp");
        var settings = HudSettings.From(config);
        Equal("summary", settings.MultiTask.DisplayMode, "typed settings projection");
        Equal(0.15d, settings.Opacity, "typed numeric settings projection");
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
    Equal(1.15d, Math.Round(estimate!.CostUsd, 6), "cached-input pricing");
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
