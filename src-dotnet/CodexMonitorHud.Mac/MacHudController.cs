using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Threading;
using CodexMonitorHud.Core.Configuration;
using CodexMonitorHud.Core.Models;
using CodexMonitorHud.Core.Presentation;
using CodexMonitorHud.Core.Pricing;
using CodexMonitorHud.Core.Sessions;
using CodexMonitorHud.Core.State;

namespace CodexMonitorHud.Mac;

internal sealed class MacHudController : IDisposable
{
    private const string Version = "3.0.0";
    private readonly Application _application;
    private readonly MainWindow _window;
    private readonly MacLaunchOptions _options;
    private readonly HudPaths _paths;
    private readonly string _sessionIndexPath;
    private readonly string _heartbeatPath;
    private readonly string _notificationsRoot;
    private readonly SessionMonitorEngine _engine;
    private readonly SessionChangeTracker _sessionsTracker;
    private readonly SessionChangeTracker _titleTracker;
    private readonly SessionChangeTracker _notificationTracker;
    private readonly SessionChangeTracker _signalTracker;
    private readonly MacLocaleCatalog _locales;
    private readonly DispatcherTimer _timer;
    private readonly Dictionary<string, TaskBubbleWindow> _bubbles;
    private readonly TrayIcon? _trayIcon;
    private readonly FileStream? _instanceLock;
    private JsonObject _config;
    private HudSettings _settings;
    private IReadOnlyDictionary<string, string> _locale;
    private PricingCatalog _pricing;
    private SettingsWindow? _settingsWindow;
    private DateTimeOffset _lastTick = DateTimeOffset.Now;
    private DateTimeOffset _lastHeartbeat = DateTimeOffset.MinValue;
    private DateTimeOffset _lastReconciliation = DateTimeOffset.MinValue;
    private DateTimeOffset _lastLifecyclePoll = DateTimeOffset.MinValue;
    private DateTimeOffset _lastMaterialAt = DateTimeOffset.Now;
    private DateTimeOffset _quietOverrideUntil = DateTimeOffset.MinValue;
    private DateTimeOffset _managedGraceUntil = DateTimeOffset.MinValue;
    private DateTimeOffset _lastHostCheck = DateTimeOffset.MinValue;
    private bool _hostActive = true;
    private long _renderedRevision = -1;
    private string _renderSignature = string.Empty;
    private string _registrySignature = string.Empty;
    private bool _paused;
    private bool _initialScanComplete;
    private bool _disposed;
    private bool _smokeWritten;
    private bool _allowWindowClose;
    private readonly bool _secondaryInstance;

    public MacHudController(Application application, MainWindow window, MacLaunchOptions options)
    {
        _application = application;
        _window = window;
        _options = options;
        var platformPaths = HudPaths.CreateForPlatform(options.PluginRoot, HudPlatform.MacOS, options.TestHome);
        _paths = string.IsNullOrWhiteSpace(options.TestStateRoot)
            ? platformPaths
            : platformPaths with
            {
                StateRoot = options.TestStateRoot,
                ConfigPath = Path.Combine(options.TestStateRoot, "settings.json")
            };
        Directory.CreateDirectory(_paths.StateRoot);
        try
        {
            _instanceLock = new FileStream(
                Path.Combine(_paths.StateRoot, "hud.instance.lock"),
                FileMode.OpenOrCreate,
                FileAccess.ReadWrite,
                FileShare.None);
        }
        catch (IOException)
        {
            _secondaryInstance = true;
        }
        _config = HudConfigStore.Load(_paths);
        _settings = HudSettings.From(_config);
        _locales = new MacLocaleCatalog(_paths.LocaleRoot);
        _locale = _locales.Get(_settings.Language);
        _pricing = PricingCatalog.Load(_paths.PluginRoot, _settings.PricingPath);
        _sessionIndexPath = Path.Combine(Path.GetDirectoryName(_paths.SessionsRoot)!, "session_index.jsonl");
        _engine = new SessionMonitorEngine(_paths.SessionsRoot, _sessionIndexPath, _settings.ToRuntimeOptions());
        _sessionsTracker = new SessionChangeTracker(_paths.SessionsRoot);
        _titleTracker = new SessionChangeTracker(
            Path.GetDirectoryName(_sessionIndexPath)!,
            Path.GetFileName(_sessionIndexPath),
            includeSubdirectories: false);
        _notificationsRoot = Path.Combine(_paths.StateRoot, "notifications");
        Directory.CreateDirectory(_notificationsRoot);
        _notificationTracker = new SessionChangeTracker(_notificationsRoot, "*.json", includeSubdirectories: false);
        _signalTracker = new SessionChangeTracker(_paths.StateRoot, "*.signal", includeSubdirectories: false);
        _heartbeatPath = Path.Combine(_paths.StateRoot, "hud.heartbeat");
        _bubbles = new Dictionary<string, TaskBubbleWindow>(SessionChangeTracker.GetPlatformPathComparer());
        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
        _timer.Tick += OnTick;
        WireWindow();
        _trayIcon = CreateTrayIcon();
    }

    public void Start()
    {
        if (_secondaryInstance)
        {
            WriteAtomic(Path.Combine(_paths.StateRoot, "show.signal"), DateTimeOffset.UtcNow.ToString("O"));
            DispatcherTimer.RunOnce(Stop, TimeSpan.Zero);
            return;
        }
        var now = DateTimeOffset.Now;
        _engine.RefreshActiveSessions(now);
        _engine.Poll(now);
        _initialScanComplete = true;
        _lastReconciliation = now;
        _lastLifecyclePoll = now;
        ApplyPricing();
        Render(force: true);
        _window.Show();
        _timer.Start();
        if (_options.OpenSettings)
        {
            ShowSettings();
        }
        if (_options.SmokeSettingsUpdate)
        {
            DispatcherTimer.RunOnce(() =>
            {
                var document = (JsonObject)_config.DeepClone();
                document["opacity"] = 0.88;
                SaveAndReload(document);
            }, TimeSpan.FromMilliseconds(500));
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _timer.Stop();
        _sessionsTracker.Dispose();
        _titleTracker.Dispose();
        _notificationTracker.Dispose();
        _signalTracker.Dispose();
        _trayIcon?.Dispose();
        _instanceLock?.Dispose();
        foreach (var bubble in _bubbles.Values) bubble.Close();
        _bubbles.Clear();
        TryDelete(_heartbeatPath);
    }

    private void WireWindow()
    {
        _window.SettingsRequested += ShowSettings;
        _window.ExitRequested += StopByUser;
        _window.ModeRequested += SetMode;
        _window.OpenTaskRequested += OpenTask;
        _window.DismissTaskRequested += path =>
        {
            _engine.Dismiss(path);
            if (_bubbles.Remove(path, out var bubble)) bubble.Close();
            Render(force: true);
        };
        _window.QuietWakeRequested += () =>
        {
            _quietOverrideUntil = DateTimeOffset.Now.AddSeconds(10);
            Render(force: true);
        };
        _window.PositionPersistRequested += (left, top) =>
        {
            _config["position"] = "custom";
            _config["customLeft"] = left;
            _config["customTop"] = top;
            SaveAndReload(_config);
        };
        _window.Closing += (_, args) =>
        {
            if (_allowWindowClose) return;
            args.Cancel = true;
            _window.Hide();
        };
    }

    private TrayIcon? CreateTrayIcon()
    {
        try
        {
            var menu = new NativeMenu();
            menu.Add(Item("Show HUD", () =>
            {
                _window.Show();
                _window.Activate();
                _quietOverrideUntil = DateTimeOffset.Now.AddSeconds(10);
                Render(force: true);
            }));
            menu.Add(Item("Summary", () => SetMode("summary")));
            menu.Add(Item("Task list", () => SetMode("list")));
            menu.Add(Item("Split tasks", () => SetMode("split")));
            menu.Add(new NativeMenuItemSeparator());
            menu.Add(Item("Settings", ShowSettings));
            menu.Add(Item("Disable click-through / 关闭鼠标穿透", () => SetMousePassthrough(false)));
            menu.Add(Item("Pause / Resume", () =>
            {
                _paused = !_paused;
                Render(force: true);
            }));
            menu.Add(new NativeMenuItemSeparator());
            menu.Add(Item("Exit", StopByUser));
            WindowIcon? icon = null;
            var iconPath = Path.Combine(_paths.PluginRoot, "assets", "codex-monitor-hud-256.png");
            if (File.Exists(iconPath)) icon = new WindowIcon(iconPath);
            return new TrayIcon
            {
                ToolTipText = "Codex Monitor HUD",
                Menu = menu,
                Icon = icon,
                IsVisible = true
            };
        }
        catch (Exception exception) when (exception is IOException or InvalidOperationException)
        {
            return null;
        }
    }

    private static NativeMenuItem Item(string header, Action action)
    {
        var item = new NativeMenuItem(header);
        item.Click += (_, _) => action();
        return item;
    }

    private void OnTick(object? sender, EventArgs args)
    {
        var now = DateTimeOffset.Now;
        var tickGap = now - _lastTick;
        _lastTick = now;
        if (tickGap > TimeSpan.FromSeconds(10))
        {
            _sessionsTracker.ForceReconciliation();
            _managedGraceUntil = now.AddSeconds(15);
        }
        if (now - _lastHeartbeat >= TimeSpan.FromSeconds(2))
        {
            _lastHeartbeat = now;
            WriteHeartbeat(now);
        }
        if (_options.Managed && now - _lastHostCheck >= TimeSpan.FromSeconds(2))
        {
            _lastHostCheck = now;
            _hostActive = HasActiveHost(now);
        }
        if (_options.Managed && now >= _managedGraceUntil && !_hostActive)
        {
            Stop();
            return;
        }
        if (ConsumeSignal("exit.signal")) { Stop(); return; }
        if (ConsumeSignal("show.signal")) { _window.Show(); _window.Activate(); }
        if (ConsumeSignal("hide.signal")) _window.Hide();
        if (ConsumeSignal("open-settings.signal")) ShowSettings();
        if (ConsumeSignal("passthrough-off.signal")) SetMousePassthrough(false);
        if (ConsumeSignal("pause.signal")) _paused = !_paused;
        if (ConsumeSignal("reload-settings.signal")) ReloadSettings();

        var changed = false;
        if (_notificationTracker.ConsumeDirty()) changed |= ProcessNotifications(now);
        _ = _notificationTracker.DrainChangedPaths();
        if (_titleTracker.ConsumeDirty() || _engine.HasTitleBacklog) changed |= _engine.RefreshTitles();
        _ = _titleTracker.DrainChangedPaths();

        if (!_paused)
        {
            var reconcileDue = now - _lastReconciliation >= TimeSpan.FromSeconds(30);
            var dirty = _sessionsTracker.ConsumeDirty();
            var structural = _sessionsTracker.ConsumeStructural();
            var overflowed = _sessionsTracker.ConsumeOverflowed();
            var paths = _sessionsTracker.DrainChangedPaths();
            if (reconcileDue || structural || overflowed)
            {
                _lastReconciliation = now;
                _lastLifecyclePoll = now;
                changed |= _engine.RefreshActiveSessions(now);
                changed |= _engine.Poll(now);
            }
            else if (dirty)
            {
                _lastLifecyclePoll = now;
                changed |= _engine.PollPaths(paths, now);
            }
            else if (_engine.HasBacklog)
            {
                _lastLifecyclePoll = now;
                changed |= _engine.PollBacklog(now);
            }
            else if (_engine.HasPendingIdentity && now - _lastLifecyclePoll >= TimeSpan.FromMilliseconds(800))
            {
                _lastLifecyclePoll = now;
                changed |= _engine.PollPendingIdentity(now);
            }
            else if (now - _lastLifecyclePoll >= TimeSpan.FromMilliseconds(800))
            {
                _lastLifecyclePoll = now;
                changed |= _engine.AdvanceLifecycleOnly(now);
            }
        }
        if (changed)
        {
            _lastMaterialAt = now;
            ApplyPricing();
        }
        var status = OverallStatus(now);
        if (changed || _renderedRevision != _engine.MaterialRevision || SignatureStatusChanged(status))
        {
            Render(force: true);
        }
        else if (_settings.Behavior.IdleIndicator.Enabled)
        {
            Render(force: false);
        }
        _timer.Interval = _engine.HasBacklog
            ? TimeSpan.FromMilliseconds(250)
            : status is "active" or "listening"
                ? TimeSpan.FromMilliseconds(800)
                : TimeSpan.FromMilliseconds(1500);
        TryCompleteSmoke(now);
    }

    private bool SignatureStatusChanged(string status) => !_renderSignature.StartsWith(status + "|", StringComparison.Ordinal);

    private void Render(bool force)
    {
        var now = DateTimeOffset.Now;
        var states = _engine.GetVisibleStates(now);
        var summary = BuildSummary(states);
        var overall = OverallStatus(now, states, summary);
        var quiet = _settings.Behavior.IdleIndicator.Enabled &&
                    now >= _quietOverrideUntil &&
                    now - _lastMaterialAt >= TimeSpan.FromMinutes(_settings.Behavior.IdleIndicator.AfterMinutes);
        var tasks = states.Select(state => new MacTaskModel(
                state.Path,
                state.Number,
                string.IsNullOrWhiteSpace(state.Workspace) ? MacVisuals.Text(_locale, "unnamedWorkspace") : state.Workspace,
                state.ConversationLabel,
                _engine.GetStatus(state, _paused, now),
                state.Snapshot,
                state.AgentNoticeUntil > now ? state.AgentNoticeText : string.Empty,
                state.ContextAlertUntil > now ? state.ContextAlertLevel : 0))
            .OrderBy(static task => task.Number)
            .ToArray();
        var signature = $"{overall}|{_settings.MultiTask.DisplayMode}|{quiet}|{_engine.MaterialRevision}|{tasks.Length}|{_settings.Language}|{_settings.Opacity:0.00}";
        if (!force && signature == _renderSignature) return;
        _renderSignature = signature;
        _renderedRevision = _engine.MaterialRevision;
        var model = new MacRenderModel(_settings, _locale, overall, summary, tasks, _paused, quiet, _initialScanComplete);
        _window.Update(model);
        UpdateBubbles(model);
        _engine.HoldTerminalExits = quiet;
        WriteRegistry(states, now);
    }

    private void UpdateBubbles(MacRenderModel model)
    {
        var split = model.Settings.MultiTask.DisplayMode == "split";
        var desired = split
            ? model.Tasks.Take(model.Settings.MultiTask.MaxSplitBubbles).Select(static task => task.Path).ToHashSet(SessionChangeTracker.GetPlatformPathComparer())
            : new HashSet<string>(SessionChangeTracker.GetPlatformPathComparer());
        foreach (var path in _bubbles.Keys.Where(path => !desired.Contains(path)).ToArray())
        {
            _bubbles[path].Close();
            _bubbles.Remove(path);
        }
        if (!split) return;
        var index = 0;
        foreach (var task in model.Tasks.Take(model.Settings.MultiTask.MaxSplitBubbles))
        {
            if (!_bubbles.TryGetValue(task.Path, out var bubble))
            {
                bubble = new TaskBubbleWindow();
                bubble.OpenRequested += OpenTask;
                bubble.DismissRequested += path =>
                {
                    _engine.Dismiss(path);
                    Render(force: true);
                };
                _bubbles[task.Path] = bubble;
                bubble.Show();
            }
            bubble.Update(task, model);
            if (model.Quiet && model.Settings.Behavior.IdleIndicator.IncludeTaskBubbles)
            {
                bubble.Hide();
            }
            else
            {
                bubble.Show();
                if (bubble.Screens.Primary is { } screen)
                {
                    var area = screen.WorkingArea;
                    var column = index % 3;
                    var row = index / 3;
                    bubble.Position = new PixelPoint(area.Right - 380 * (column + 1), area.Y + 30 + 230 * row);
                }
            }
            index++;
        }
    }

    private HudSnapshot? BuildSummary(IReadOnlyList<SessionState> states)
    {
        var snapshots = states.Select(static state => state.Snapshot).OfType<HudSnapshot>().ToArray();
        if (snapshots.Length == 0) return null;
        if (_settings.MonitorScope == "aggregate")
        {
            return SnapshotAggregator.Merge(snapshots, MacVisuals.Text(_locale, "multiTaskSummary"));
        }
        var latest = snapshots.OrderByDescending(static snapshot => snapshot.Timestamp).First() with { ActiveTasks = snapshots.Length };
        var allowance = SnapshotAggregator.GetLatestAllowance(snapshots);
        return allowance is null ? latest : latest with
        {
            AllowanceTimestamp = allowance.AllowanceTimestamp,
            WeeklyRemainingPercent = allowance.WeeklyRemainingPercent,
            FiveHourRemainingPercent = allowance.FiveHourRemainingPercent
        };
    }

    private string OverallStatus(DateTimeOffset now, IReadOnlyList<SessionState>? states = null, HudSnapshot? summary = null)
    {
        if (_paused) return "paused";
        states ??= _engine.GetVisibleStates(now);
        var statuses = states.Select(state => _engine.GetStatus(state, false, now)).ToArray();
        if (statuses.Contains("aborted", StringComparer.Ordinal)) return "aborted";
        if (statuses.Contains("completed", StringComparer.Ordinal)) return "completed";
        if (_engine.LastReadErrorAt != DateTimeOffset.MinValue &&
            (now - _engine.LastReadErrorAt).TotalSeconds <= _settings.StatusTiming.ErrorHoldSeconds) return "error";
        summary ??= states.Select(static state => state.Snapshot).OfType<HudSnapshot>()
            .OrderByDescending(static snapshot => snapshot.Timestamp).FirstOrDefault();
        if (summary is null) return "idle";
        var reference = _engine.LastUsageAt == DateTimeOffset.MinValue ? summary.Timestamp : _engine.LastUsageAt;
        var age = (now - reference).TotalSeconds;
        return age <= _settings.StatusTiming.ActiveSeconds ? "active" :
            age <= _settings.StatusTiming.IdleSeconds ? "listening" : "idle";
    }

    private void ApplyPricing()
    {
        foreach (var state in _engine.States.Values)
        {
            if (state.Snapshot is null || state.Snapshot.EstimatedCostUsd.HasValue) continue;
            var estimate = _pricing.Estimate(state.Snapshot);
            if (estimate is not null) state.Snapshot = state.Snapshot with { EstimatedCostUsd = estimate.CostUsd };
        }
    }

    private void SetMode(string mode)
    {
        if (mode is not ("summary" or "list" or "split")) return;
        if (_config["multiTask"] is not JsonObject multi)
        {
            multi = new JsonObject();
            _config["multiTask"] = multi;
        }
        multi["displayMode"] = mode;
        SaveAndReload(_config);
    }

    private void SetMousePassthrough(bool enabled)
    {
        if (_settings.MousePassthrough == enabled) return;
        _config["mousePassthrough"] = enabled;
        SaveAndReload(_config);
    }

    private void ShowSettings()
    {
        if (_settingsWindow is not null)
        {
            _settingsWindow.Show();
            _settingsWindow.Activate();
            return;
        }
        _settingsWindow = new SettingsWindow(
            _config,
            _settings.Language == "symbols" ? _locales.Get("en") : _locale,
            _paths.LocaleRoot);
        _settingsWindow.ApplyRequested += document => SaveAndReload(document);
        _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        _settingsWindow.Show();
        _settingsWindow.Activate();
    }

    private void SaveAndReload(JsonObject document)
    {
        HudConfigStore.Save(_paths, document);
        _config = HudConfigStore.Load(_paths);
        ReloadSettingsCore();
    }

    private void ReloadSettings()
    {
        _config = HudConfigStore.Load(_paths);
        ReloadSettingsCore();
    }

    private void ReloadSettingsCore()
    {
        _settings = HudSettings.From(_config);
        _locale = _locales.Get(_settings.Language);
        _pricing = PricingCatalog.Load(_paths.PluginRoot, _settings.PricingPath);
        _engine.UpdateOptions(_settings.ToRuntimeOptions());
        foreach (var state in _engine.States.Values)
            if (state.Snapshot is not null) state.Snapshot = state.Snapshot with { EstimatedCostUsd = null };
        ApplyPricing();
        _lastMaterialAt = DateTimeOffset.Now;
        Render(force: true);
    }

    private void OpenTask(string path)
    {
        if (!_settings.Behavior.OpenTaskOnDoubleClick || !_engine.States.TryGetValue(path, out var state)) return;
        var link = HudFormatting.GetTaskDeepLink(state.SessionId);
        if (link is null) return;
        try { _ = Process.Start(new ProcessStartInfo(link) { UseShellExecute = true }); }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception) { }
    }

    private bool ProcessNotifications(DateTimeOffset now)
    {
        var changed = false;
        foreach (var path in Directory.EnumerateFiles(_notificationsRoot, "*.json"))
        {
            try
            {
                var info = new FileInfo(path);
                if (!_settings.AgentNotifications.Enabled || info.Length > 8192)
                {
                    TryDelete(path);
                    continue;
                }
                using var document = JsonDocument.Parse(File.ReadAllText(path));
                var root = document.RootElement;
                if (!root.TryGetProperty("source", out var source) || source.GetString() != "codex-mcp")
                    throw new InvalidDataException("Unsupported notification source.");
                var message = root.TryGetProperty("message", out var messageNode) ? messageNode.GetString() ?? string.Empty : string.Empty;
                message = new string(message.Where(static character => !char.IsControl(character)).Take(160).ToArray()).Trim();
                if (message.Length == 0) throw new InvalidDataException("Empty notification.");
                int? taskNumber = root.TryGetProperty("task_number", out var taskNode) && taskNode.TryGetInt32(out var number)
                    ? number : null;
                if (_engine.AcceptAgentNotice(taskNumber, message, _settings.AgentNotifications.DurationSeconds, null, now))
                {
                    MacNotificationService.Show("Codex Monitor HUD", message);
                    TryDelete(path);
                    changed = true;
                }
                else if (now.UtcDateTime - info.CreationTimeUtc > TimeSpan.FromSeconds(60))
                {
                    TryDelete(path);
                }
            }
            catch (Exception exception) when (exception is JsonException or IOException or InvalidDataException)
            {
                TryDelete(path);
            }
        }
        return changed;
    }

    private void WriteHeartbeat(DateTimeOffset now) => WriteAtomic(_heartbeatPath, JsonSerializer.Serialize(new
    {
        version = Version,
        host = "avalonia-macos",
        platform = OperatingSystem.IsMacOS() ? "macos" : "test-host",
        architecture = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant(),
        pid = Environment.ProcessId,
        timestamp = now.ToUniversalTime()
    }));

    private void WriteRegistry(IReadOnlyList<SessionState> states, DateTimeOffset now)
    {
        var tasks = states.OrderBy(static state => state.Number).Select(state => new
        {
            task_number = state.Number,
            workspace = state.Workspace,
            status = _engine.GetStatus(state, _paused, now),
            updated_at = state.LastUsageAt.ToString("O")
        }).ToArray();
        var signature = JsonSerializer.Serialize(tasks);
        if (signature == _registrySignature) return;
        _registrySignature = signature;
        WriteAtomic(Path.Combine(_paths.StateRoot, "task-registry.json"), JsonSerializer.Serialize(new
        {
            version = 1,
            generated_at = now.ToString("O"),
            tasks
        }));
    }

    private void TryCompleteSmoke(DateTimeOffset now)
    {
        if (_smokeWritten || string.IsNullOrWhiteSpace(_options.SmokeOutput)) return;
        if (now - _lastReconciliation < TimeSpan.FromSeconds(1.5)) return;
        _smokeWritten = true;
        var states = _engine.GetVisibleStates(now);
        WriteAtomic(_options.SmokeOutput, JsonSerializer.Serialize(new
        {
            version = Version,
            host = "avalonia-macos",
            visible_tasks = states.Count,
            display_mode = _settings.MultiTask.DisplayMode,
            quiet = _settings.Behavior.IdleIndicator.Enabled &&
                    now >= _quietOverrideUntil &&
                    now - _lastMaterialAt >= TimeSpan.FromMinutes(_settings.Behavior.IdleIndicator.AfterMinutes),
            heartbeat = File.Exists(_heartbeatPath) ? "present" : "missing",
            registry = File.Exists(Path.Combine(_paths.StateRoot, "task-registry.json")) ? "present" : "missing",
            settings = File.Exists(_paths.ConfigPath) ? "present" : "default",
            settings_opacity = _settings.Opacity,
            active_notices = states.Count(state => state.AgentNoticeUntil > now),
            status = OverallStatus(now)
        }));
        DispatcherTimer.RunOnce(Stop, TimeSpan.FromMilliseconds(100));
    }

    private bool ConsumeSignal(string name)
    {
        var path = Path.Combine(_paths.StateRoot, name);
        if (!File.Exists(path)) return false;
        TryDelete(path);
        return true;
    }

    private bool HasActiveHost(DateTimeOffset now)
    {
        var hostsRoot = Path.Combine(_paths.StateRoot, "hosts");
        try
        {
            if (Directory.Exists(hostsRoot))
            {
                var cutoff = now.UtcDateTime.AddSeconds(-8);
                foreach (var path in Directory.EnumerateFiles(hostsRoot, "*.heartbeat"))
                {
                    if (File.GetLastWriteTimeUtc(path) >= cutoff) return true;
                    TryDelete(path);
                }
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        if (_options.ParentPid <= 0) return false;
        try
        {
            using var parent = Process.GetProcessById(_options.ParentPid);
            return !parent.HasExited;
        }
        catch (ArgumentException)
        {
            return false;
        }
    }

    private static void WriteAtomic(string path, string content)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + $".{Environment.ProcessId}.{Guid.NewGuid():N}.tmp";
        try
        {
            File.WriteAllText(temporary, content, new UTF8Encoding(false));
            File.Move(temporary, path, overwrite: true);
        }
        finally
        {
            TryDelete(temporary);
        }
    }

    private static void TryDelete(string path)
    {
        try { File.Delete(path); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private void StopByUser()
    {
        WriteAtomic(Path.Combine(_paths.StateRoot, "manual-exit.signal"), DateTimeOffset.UtcNow.ToString("O"));
        Stop();
    }

    private void Stop()
    {
        _timer.Stop();
        _allowWindowClose = true;
        Dispose();
        if (_application.ApplicationLifetime is Avalonia.Controls.ApplicationLifetimes.IClassicDesktopStyleApplicationLifetime desktop)
            desktop.Shutdown();
    }
}
