using System.Text.Json;
using System.Threading;
using System.Windows;
using System.Xml.Linq;
using CodexMonitorHud.Core.Configuration;
using CodexMonitorHud.Core.Models;
using CodexMonitorHud.Core.Parsing;
using CodexMonitorHud.Core.Pricing;
using CodexMonitorHud.Core.Sessions;
using CodexMonitorHud.Core.State;

namespace CodexMonitorHud.App;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            _ = NativeMethods.SetProcessDpiAwarenessContext(new nint(-4));
            _ = NativeMethods.SetCurrentProcessExplicitAppUserModelID("CodexMonitorHUD.Desktop");
        }
        catch (EntryPointNotFoundException)
        {
        }
        catch (DllNotFoundException)
        {
        }
        var arguments = AppArguments.Parse(args);
        var pluginRoot = ResolvePluginRoot(arguments.PluginRoot);
        var testHome = Environment.GetEnvironmentVariable("CODEX_MONITOR_HUD_TEST_HOME");
        var testLocalAppData = Environment.GetEnvironmentVariable("CODEX_MONITOR_HUD_TEST_LOCALAPPDATA");
        var paths = HudPaths.Create(
            pluginRoot,
            localAppData: string.IsNullOrWhiteSpace(testLocalAppData) ? null : testLocalAppData,
            home: string.IsNullOrWhiteSpace(testHome) ? null : testHome);
        var log = new HudLog(paths.StateRoot, arguments.DebugLog);

        if (!string.IsNullOrWhiteSpace(arguments.HealthCheckPath))
        {
            return RunHealthCheck(paths, arguments.HealthCheckPath);
        }

        if (arguments.SelfTest)
        {
            return RunSelfTest(paths);
        }

        Directory.CreateDirectory(paths.StateRoot);
        var mutexSuffix = string.IsNullOrWhiteSpace(arguments.InstanceId)
            ? string.Empty
            : "-" + string.Concat(arguments.InstanceId.Select(static character =>
                char.IsLetterOrDigit(character) || character is '_' or '.' or '-' ? character : '_'));
        using var mutex = new Mutex(true, "Local\\CodexMonitorHUD" + mutexSuffix, out var createdNew);
        if (!createdNew)
        {
            if (arguments.OpenSettings)
            {
                File.WriteAllText(Path.Combine(paths.StateRoot, "open-settings.signal"), DateTime.UtcNow.ToString("O"));
            }
            return 0;
        }

        var application = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        application.DispatcherUnhandledException += (_, eventArgs) =>
        {
            log.Write("Unhandled dispatcher exception: " + eventArgs.Exception);
            // The HUD is a read-only projection. Keeping its recovery controls
            // alive is safer than terminating the whole monitor because one
            // event handler or animation encountered a transient UI failure.
            eventArgs.Handled = true;
        };
        AppDomain.CurrentDomain.UnhandledException += (_, eventArgs) => log.Write("Unhandled domain exception: " + eventArgs.ExceptionObject);

        try
        {
            using var controller = new HudApplicationController(application, paths, arguments, log);
            controller.Start();
            return application.Run();
        }
        catch (Exception exception)
        {
            log.Write("Fatal startup error: " + exception);
            return 1;
        }
        finally
        {
            try
            {
                mutex.ReleaseMutex();
            }
            catch (ApplicationException)
            {
            }
        }
    }

    private static int RunSelfTest(HudPaths paths)
    {
        var settings = HudSettings.From(HudConfigStore.Load(paths));
        var engine = new SessionMonitorEngine(
            SessionProfile.CreateDefaultSet(paths),
            settings.ToRuntimeOptions(),
            activitySource: new WindowsSessionActivitySource());
        _ = engine.RefreshActiveSessions();
        _ = engine.Poll();
        var visible = engine.GetVisibleStates();
        var state = visible
            .OrderByDescending(static item => item.RuntimeActivityAt)
            .ThenByDescending(static item => item.LastUsageAt)
            .FirstOrDefault();
        var snapshot = state?.Snapshot;

        Console.WriteLine(JsonSerializer.Serialize(new
        {
            session = state is null ? string.Empty : Path.GetFileName(state.Path),
            identity_found = state?.IdentityMetadataFound ?? false,
            internal_session = state?.IsInternalSession ?? false,
            snapshot_found = snapshot is not null,
            discovered_tasks = engine.States.Count,
            visible_tasks = visible.Count,
            runtime_active_tasks = visible.Count(item => item.RuntimeActivityAt != DateTimeOffset.MinValue),
            tasks = visible.Select(item => new
            {
                id = item.SessionId,
                profile = item.ProfileId,
                surface = item.ClientSurface,
                status = engine.GetStatus(item, paused: false),
                runtime_activity = item.RuntimeActivityAt == DateTimeOffset.MinValue
                    ? string.Empty
                    : item.RuntimeActivityAt.ToString("O")
            }),
            input = snapshot?.Input ?? 0,
            cached = snapshot?.Cached ?? 0,
            uncached = snapshot?.Uncached ?? 0,
            output = snapshot?.Output ?? 0,
            reasoning = snapshot?.Reasoning ?? 0,
            call_total = snapshot?.CallTotal ?? 0,
            task_total = snapshot?.TaskTotal ?? 0,
            context_percent = snapshot?.ContextPercent ?? 0,
            model = snapshot?.Model ?? string.Empty,
            accounting_ok = snapshot?.AccountingIsValid ?? false
        }, new JsonSerializerOptions { WriteIndented = true }));
        return state is null ? 1 : 0;
    }

    private static int RunHealthCheck(HudPaths paths, string outputPath)
    {
        try
        {
            var config = HudConfigStore.Load(paths);
            var settings = HudSettings.From(config);
            var pricing = PricingCatalog.Load(paths.PluginRoot, settings.PricingPath);
            _ = XDocument.Load(Path.Combine(paths.PluginRoot, "src", "HudWindow.xaml"));
            _ = XDocument.Load(Path.Combine(paths.PluginRoot, "src", "TaskBubbleWindow.xaml"));
            var sample = HudRecordParser.Parse("{\"timestamp\":\"2026-07-17T00:00:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":12,\"cached_input_tokens\":4,\"output_tokens\":3,\"reasoning_output_tokens\":1,\"total_tokens\":15},\"total_token_usage\":{\"input_tokens\":12,\"cached_input_tokens\":4,\"output_tokens\":3,\"reasoning_output_tokens\":1,\"total_tokens\":15},\"model_context_window\":100}}}");
            if (sample is null || sample.CallTotal != 15 || sample.Input != 12 || sample.Cached != 4)
            {
                throw new InvalidDataException("Core parser health check failed.");
            }
            var result = JsonSerializer.Serialize(new
            {
                product = "Codex Monitor HUD",
                version = "3.2.0",
                framework = Environment.Version.ToString(),
                config = "ok",
                xaml = "ok",
                parser = "ok",
                pricing = pricing.Loaded ? "loaded" : "fallback"
            });
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outputPath))!);
            File.WriteAllText(outputPath, result);
            return 0;
        }
        catch (Exception exception)
        {
            try { File.WriteAllText(outputPath, JsonSerializer.Serialize(new { error = exception.Message })); } catch { }
            return 1;
        }
    }

    private static string ResolvePluginRoot(string? explicitRoot)
    {
        if (!string.IsNullOrWhiteSpace(explicitRoot))
        {
            return Path.GetFullPath(explicitRoot);
        }

        var current = new DirectoryInfo(AppContext.BaseDirectory);
        while (current is not null)
        {
            if (File.Exists(Path.Combine(current.FullName, "config.default.json")))
            {
                return current.FullName;
            }
            current = current.Parent;
        }
        throw new DirectoryNotFoundException("Codex Monitor HUD plugin root could not be resolved.");
    }
}
