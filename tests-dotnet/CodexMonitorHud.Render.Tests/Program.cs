using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CodexMonitorHud.Core.Configuration;
using CodexMonitorHud.Core.Models;
using CodexMonitorHud.Core.Sessions;
using CodexMonitorHud.Core.State;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        var root = Path.GetFullPath(args[0]);
        var output = Path.GetFullPath(args[1]);
        Directory.CreateDirectory(output);
        _ = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        var assembly = Assembly.Load("CodexMonitorHud");
        var mainType = assembly.GetType("CodexMonitorHud.App.MainHudView", throwOnError: true)!;
        var bubbleType = assembly.GetType("CodexMonitorHud.App.TaskBubbleView", throwOnError: true)!;
        var brushType = assembly.GetType("CodexMonitorHud.App.BrushFactory", throwOnError: true)!;
        var zh = ReadLocale(root, "zh-CN");
        var en = ReadLocale(root, "en");
        var now = DateTimeOffset.Parse("2026-07-13T08:00:00Z");
        var states = Enumerable.Range(1, 6).Select(i => new SessionState
        {
            Path = Path.Combine(output, $"synthetic-{i}.jsonl"), Number = i, StartedAt = now,
            Reader = new IncrementalJsonlReader(0), IdentityMetadataFound = true,
            Workspace = $"Synthetic {i}", ConversationLabel = $"合成任务 {i}", SessionId = $"synthetic-{i}",
            ProfileId = "default", ClientSurface = i % 3 == 0 ? "cli" : i % 3 == 1 ? "desktop" : "vscode",
            ModelProvider = "openai", Model = "gpt-test", LastUsageAt = now,
            Snapshot = new HudSnapshot
            {
                Timestamp = now, Model = "gpt-test", Input = 1000 + i, Cached = 700,
                Uncached = 300 + i, Output = 100, CallTotal = 1100 + i, TaskTotal = 10000 + i,
                ContextWindow = 200000, ContextPercent = 25, EstimatedCostUsd = 0.03,
                WeeklyRemainingPercent = 80, FiveHourRemainingPercent = 75
            }
        }).ToArray();

        foreach (var mode in new[] { "summary", "list", "bubble" })
        foreach (var theme in new[] { "default", "dark" })
        {
            var document = JsonNode.Parse(File.ReadAllText(Path.Combine(root, "config.default.json")))!.AsObject();
            document["multiTask"]!["displayMode"] = mode == "bubble" ? "summary" : mode;
            document["behavior"]!["idleIndicator"]!["enabled"] = false;
            document["animateUpdates"] = false;
            if (theme == "dark")
            {
                document["background"] = "#EE111827";
                document["foreground"] = "#FFF8FAFC";
                document["muted"] = "#FF94A3B8";
            }
            var settings = HudSettings.From(document);
            using var view = (IDisposable)(mode == "bubble"
                ? Activator.CreateInstance(bubbleType, Path.Combine(root, "src", "TaskBubbleWindow.xaml"), states[0], Activator.CreateInstance(brushType))!
                : Activator.CreateInstance(mainType, Path.Combine(root, "src", "HudWindow.xaml"), Path.Combine(root, "src", "TaskBubbleWindow.xaml"))!);
            var type = view.GetType();
            var method = type.GetMethod("Render")!;
            var window = (Window)type.GetProperty("Window")!.GetValue(view)!;
            var content = (FrameworkElement)window.Content;
            var snapshot = SnapshotAggregator.Merge(states.Select(s => s.Snapshot), "{tasks} tasks / {models} models");
            object?[] parameters = mode == "bubble"
                ? [states[0], settings, zh, "active", "合成任务 1", "Desktop", "#FF0A84FF", "调用 1,101 · 合计 10,001", false]
                : [settings, zh, zh, zh, en, states, snapshot, (Func<SessionState, string>)(_ => "active"), "active", false, true];
            void Render()
            {
                method.Invoke(view, parameters);
                content.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
                content.Arrange(new Rect(content.DesiredSize));
                content.UpdateLayout();
            }
            Render();
            var width = Math.Max(1, (int)Math.Ceiling(content.ActualWidth + 48));
            var height = Math.Max(1, (int)Math.Ceiling(content.ActualHeight + 48));
            var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
            bitmap.Render(content);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using (var file = File.Create(Path.Combine(output, $"{mode}-{theme}.png"))) encoder.Save(file);
            for (var i = 0; i < 30; i++) Render();
            var bytes = GC.GetAllocatedBytesForCurrentThread();
            var timer = Stopwatch.StartNew();
            for (var i = 0; i < 500; i++) Render();
            timer.Stop();
            Console.WriteLine(JsonSerializer.Serialize(new
            {
                name = mode + "-" + theme, iterations = 500, elapsed_ms = timer.Elapsed.TotalMilliseconds,
                bytes_per_render = (GC.GetAllocatedBytesForCurrentThread() - bytes) / 500, width, height
            }));
        }
    }

    private static Dictionary<string, string> ReadLocale(string root, string language) =>
        JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(Path.Combine(root, "locales", language + ".json")))!;
}
