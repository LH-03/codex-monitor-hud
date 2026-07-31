using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Threading;
using CodexMonitorHud.Core.Configuration;
using CodexMonitorHud.Core.Models;
using CodexMonitorHud.Core.Presentation;
using CodexMonitorHud.Core.Pricing;
using CodexMonitorHud.Core.Sessions;
using CodexMonitorHud.Core.State;

namespace CodexMonitorHud.App;

internal sealed partial class HudApplicationController : IDisposable
{
    private readonly Application _application;
    private readonly HudPaths _paths;
    private readonly AppArguments _arguments;
    private readonly HudLog _log;
    private readonly LocaleCatalog _locales;
    private readonly SessionMonitorEngine _engine;
    private readonly SessionChangeTracker _changeTracker;
    private readonly SessionChangeTracker _titleTracker;
    private readonly SessionChangeTracker _notificationTracker;
    private readonly SessionChangeTracker _signalTracker;
    private readonly MainHudView _view;
    private readonly HudCommandSurfaces _commands;
    private readonly DispatcherTimer _timer;
    private readonly string _sessionIndexPath;
    private readonly string _heartbeatPath;
    private readonly string _hostsRoot;
    private readonly string _notificationsRoot;
    private JsonObject _configDocument;
    private HudSettings _settings;
    private PricingCatalog _pricing;
    private IReadOnlyDictionary<string, string> _locale;
    private IReadOnlyDictionary<string, string> _settingsLocale;
    private DateTimeOffset _lastTick = DateTimeOffset.Now;
    private DateTimeOffset _lastHeartbeat = DateTimeOffset.MinValue;
    private DateTimeOffset _lastReconciliation = DateTimeOffset.MinValue;
    private DateTimeOffset _lastLifecyclePoll = DateTimeOffset.MinValue;
    private DateTimeOffset _lastQuietPoll = DateTimeOffset.MinValue;
    private DateTimeOffset _lastNotificationReconciliation = DateTimeOffset.MinValue;
    private DateTimeOffset _managedGraceUntil = DateTimeOffset.MinValue;
    private DateTimeOffset _responsiveUntil = DateTimeOffset.MinValue;
    private DateTimeOffset _lastHostCheck = DateTimeOffset.MinValue;
    private bool _lastHostActive = true;
    private long _lastRenderedRevision = -1;
    private string _lastOverallStatus = string.Empty;
    private string _lastRegistryContent = string.Empty;
    private bool _paused;
    private bool _initialScanComplete;
    private bool _disposed;
    private int _wakePending;

    public HudApplicationController(
        Application application,
        HudPaths paths,
        AppArguments arguments,
        HudLog log)
    {
        _application = application;
        _paths = paths;
        _arguments = arguments;
        _log = log;
        _configDocument = HudConfigStore.Load(paths);
        _settings = HudSettings.From(_configDocument);
        _pricing = PricingCatalog.Load(paths.PluginRoot, _settings.PricingPath);
        _locales = new LocaleCatalog(paths.LocaleRoot);
        _locale = _locales.Get(_settings.Language);
        _settingsLocale = _settings.Language == "symbols" ? _locales.Get("en") : _locale;
        _sessionIndexPath = Path.Combine(
            Path.GetDirectoryName(_paths.SessionsRoot)!,
            "session_index.jsonl");
        _engine = new SessionMonitorEngine(paths.SessionsRoot, _sessionIndexPath, _settings.ToRuntimeOptions());
        _changeTracker = new SessionChangeTracker(paths.SessionsRoot);
        _titleTracker = new SessionChangeTracker(Path.GetDirectoryName(_sessionIndexPath)!, Path.GetFileName(_sessionIndexPath), includeSubdirectories: false);
        _view = new MainHudView(
            Path.Combine(paths.PluginRoot, "src", "HudWindow.xaml"),
            Path.Combine(paths.PluginRoot, "src", "TaskBubbleWindow.xaml"));
        _commands = new HudCommandSurfaces(_view.Window, Path.Combine(paths.PluginRoot, "assets", "codex-monitor-hud.ico"));
        _heartbeatPath = Path.Combine(paths.StateRoot, "hud.heartbeat");
        _hostsRoot = Path.Combine(paths.StateRoot, "hosts");
        _notificationsRoot = Path.Combine(paths.StateRoot, "notifications");
        Directory.CreateDirectory(_notificationsRoot);
        _notificationTracker = new SessionChangeTracker(_notificationsRoot, "*.json", includeSubdirectories: false);
        _signalTracker = new SessionChangeTracker(paths.StateRoot, "*.signal", includeSubdirectories: false);
        _timer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromMilliseconds(200)
        };
        _timer.Tick += OnTick;
        _changeTracker.ChangeAvailable += QueueWake;
        _titleTracker.ChangeAvailable += QueueWake;
        _notificationTracker.ChangeAvailable += QueueWake;
        _signalTracker.ChangeAvailable += QueueWake;
        WireCommands();
    }

    public void Start()
    {
        _log.Write($"Compiled HUD v2.2.0 starting. config={_paths.ConfigPath}; sessions={_paths.SessionsRoot}; agentNotices={_settings.AgentNotifications.Enabled}/{_settings.AgentNotifications.Permission}");
        var now = DateTimeOffset.Now;
        _engine.RefreshActiveSessions(now);
        _engine.Poll(now);
        _lastReconciliation = now;
        _lastLifecyclePoll = now;
        _initialScanComplete = true;
        ApplyPricing();
        Render(force: true);
        _view.Window.Show();
        _timer.Start();
        if (_arguments.OpenSettings)
        {
            OpenSettings();
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        _timer.Stop();
        _changeTracker.Dispose();
        _titleTracker.Dispose();
        _notificationTracker.Dispose();
        _signalTracker.Dispose();
        _commands.Dispose();
        _view.Dispose();
        TryDelete(_heartbeatPath);
    }

    private void QueueWake()
    {
        if (_disposed || Interlocked.Exchange(ref _wakePending, 1) == 1)
        {
            return;
        }
        try
        {
            _application.Dispatcher.BeginInvoke(DispatcherPriority.Background, (Action)(() =>
            {
                Interlocked.Exchange(ref _wakePending, 0);
                if (!_disposed)
                {
                    OnTick(null, EventArgs.Empty);
                }
            }));
        }
        catch (InvalidOperationException)
        {
            Interlocked.Exchange(ref _wakePending, 0);
        }
    }

    private void WireCommands()
    {
        _view.SettingsRequested += OpenSettings;
        _view.ExitRequested += StopByUser;
        _view.ToggleListRequested += ToggleTaskList;
        _view.DismissRequested += path =>
        {
            _engine.Dismiss(path);
            _view.RemoveState(path);
            Render(force: true);
        };
        _view.OpenRequested += OpenTask;
        _view.PositionChanged += (left, top) =>
        {
            _configDocument["position"] = "custom";
            _configDocument["customLeft"] = left;
            _configDocument["customTop"] = top;
            SaveAndReloadSettings();
        };
        _view.DetachedChanged += (_, _) => Render(force: true);
        _view.AttentionPresented += (surface, path, reason) =>
        {
            var workspace = _engine.States.TryGetValue(path, out var state) ? state.Workspace : Path.GetFileName(path);
            _log.Write($"Attention surface: {surface} {workspace} reason={reason}");
        };
        _commands.SettingsRequested += OpenSettings;
        _commands.PassthroughToggleRequested += TogglePassthrough;
        _commands.PauseToggleRequested += () =>
        {
            _paused = !_paused;
            Render(force: true);
        };
        _commands.ResetPositionRequested += () =>
        {
            if (_settings.Position == "custom")
            {
                _configDocument["position"] = "top-right";
                SaveAndReloadSettings();
            }
            Render(force: true);
        };
        _commands.ModeRequested += SetMode;
        _commands.ExitRequested += StopByUser;
    }

    private void OnTick(object? sender, EventArgs args)
    {
        var now = DateTimeOffset.Now;
        var tickGap = now - _lastTick;
        _lastTick = now;
        if (tickGap > TimeSpan.FromSeconds(10))
        {
            _managedGraceUntil = now.AddSeconds(15);
            _changeTracker.ForceReconciliation();
            _log.Write($"Resume/tick gap detected: {tickGap.TotalSeconds:0.0}s; managed grace applied.");
        }

        if (now - _lastHeartbeat >= TimeSpan.FromSeconds(2))
        {
            _lastHeartbeat = now;
            TryWriteText(_heartbeatPath, DateTime.UtcNow.ToString("O"));
        }

        if (_arguments.Managed && now - _lastHostCheck >= TimeSpan.FromSeconds(2))
        {
            _lastHostCheck = now;
            _lastHostActive = HasActiveHost(now);
        }
        if (_arguments.Managed && now >= _managedGraceUntil && !_lastHostActive)
        {
            Stop();
            return;
        }

        if (ConsumeSignal("exit.signal"))
        {
            Stop();
            return;
        }
        if (ConsumeSignal("open-settings.signal")) OpenSettings();
        if (ConsumeSignal("show.signal")) _view.Window.Show();
        if (ConsumeSignal("hide.signal")) _view.Window.Hide();
        if (ConsumeSignal("pause.signal")) _paused = !_paused;
        if (ConsumeSignal("passthrough-off.signal") && _settings.MousePassthrough) SetMousePassthrough(false);
        if (ConsumeSignal("reload-settings.signal")) ReloadSettings();

        var notificationReconciliationDue = now - _lastNotificationReconciliation >= TimeSpan.FromSeconds(30);
        var changed = _notificationTracker.ConsumeDirty() || notificationReconciliationDue
            ? ProcessNotifications(now)
            : false;
        _ = _notificationTracker.DrainChangedPaths();
        if (_titleTracker.ConsumeDirty() || _engine.HasTitleBacklog)
        {
            changed |= _engine.RefreshTitles();
            if (_engine.HasTitleBacklog)
            {
                _responsiveUntil = now.AddSeconds(2);
            }
        }
        _ = _titleTracker.DrainChangedPaths();
        if (notificationReconciliationDue)
        {
            _lastNotificationReconciliation = now;
        }
        if (!_paused)
        {
            var filePollPerformed = false;
            var reconcileDue = now - _lastReconciliation >= TimeSpan.FromSeconds(30);
            var dirty = _changeTracker.ConsumeDirty();
            var overflowed = _changeTracker.ConsumeOverflowed();
            var structural = _changeTracker.ConsumeStructural();
            var changedPaths = _changeTracker.DrainChangedPaths();
            if (dirty || reconcileDue || overflowed)
            {
                filePollPerformed = true;
                _lastLifecyclePoll = now;
                if (reconcileDue)
                {
                    _lastReconciliation = now;
                }
                if (reconcileDue || structural || overflowed)
                {
                    changed |= _engine.RefreshActiveSessions(now);
                    changed |= _engine.Poll(now);
                }
                else
                {
                    changed |= _engine.PollPaths(changedPaths, now);
                }
            }
            else if (_engine.HasBacklog)
            {
                filePollPerformed = true;
                _lastLifecyclePoll = now;
                changed |= _engine.PollBacklog(now);
            }
            else if (_engine.HasPendingIdentity && now - _lastLifecyclePoll >= TimeSpan.FromMilliseconds(800))
            {
                filePollPerformed = true;
                _lastLifecyclePoll = now;
                changed |= _engine.PollPendingIdentity(now);
            }
            else if (now - _lastLifecyclePoll >= TimeSpan.FromMilliseconds(800))
            {
                _lastLifecyclePoll = now;
                changed |= _engine.AdvanceLifecycleOnly(now);
            }
            if (filePollPerformed && _engine.HasBacklog)
            {
                _responsiveUntil = now.AddSeconds(2);
            }
        }

        var overallStatus = GetOverallStatus(now);
        if (now - _lastQuietPoll >= TimeSpan.FromMilliseconds(500))
        {
            _lastQuietPoll = now;
            var quietStates = _engine.GetVisibleStates(now);
            _view.RefreshQuietMode(
                _settings,
                _settingsLocale,
                quietStates,
                state => _engine.GetStatus(state, _paused, now),
                GetOverallStatus(now, quietStates),
                now);
            _engine.HoldTerminalExits = _view.HoldTerminalExits;
        }
        if (changed || _lastRenderedRevision != _engine.MaterialRevision || overallStatus != _lastOverallStatus)
        {
            _responsiveUntil = now.AddSeconds(2);
            ApplyPricing();
            Render(force: true);
        }
        _timer.Interval = now < _responsiveUntil
            ? TimeSpan.FromMilliseconds(250)
            : overallStatus is "active" or "listening"
                ? TimeSpan.FromMilliseconds(800)
                : TimeSpan.FromMilliseconds(1500);
    }

    private void Render(bool force)
    {
        var now = DateTimeOffset.Now;
        var states = _engine.GetVisibleStates(now);
        var snapshot = BuildDisplaySnapshot(states);
        var status = GetOverallStatus(now, states, snapshot);
        if (!force && _lastRenderedRevision == _engine.MaterialRevision && _lastOverallStatus == status)
        {
            return;
        }
        _lastRenderedRevision = _engine.MaterialRevision;
        _lastOverallStatus = status;
        _view.Render(
            _settings,
            _locale,
            _settingsLocale,
            _locales.Get("zh-CN"),
            _locales.Get("en"),
            states,
            snapshot,
            state => _engine.GetStatus(state, _paused, now),
            status,
            _paused,
            _initialScanComplete);
        _engine.HoldTerminalExits = _view.HoldTerminalExits;
        _commands.Update(_locales.Get("zh-CN"), _locales.Get("en"), status, _settings.MultiTask.DisplayMode, _paused, _settings.MousePassthrough);
        WriteTaskRegistry(states, now);
    }

    private HudSnapshot? BuildDisplaySnapshot(IReadOnlyList<SessionState> states)
    {
        var snapshots = states.Select(static state => state.Snapshot).OfType<HudSnapshot>().ToArray();
        if (snapshots.Length == 0)
        {
            return null;
        }
        if (_settings.MonitorScope == "aggregate")
        {
            return SnapshotAggregator.Merge(snapshots, Get(_locale, "multiTaskSummary"));
        }
        var latest = snapshots.OrderByDescending(static snapshot => snapshot.Timestamp).First() with { ActiveTasks = snapshots.Length };
        var allowance = SnapshotAggregator.GetLatestAllowance(snapshots);
        return allowance is null
            ? latest
            : latest with
            {
                AllowanceTimestamp = allowance.AllowanceTimestamp,
                WeeklyRemainingPercent = allowance.WeeklyRemainingPercent,
                FiveHourRemainingPercent = allowance.FiveHourRemainingPercent
            };
    }

    private string GetOverallStatus(DateTimeOffset now, IReadOnlyList<SessionState>? states = null, HudSnapshot? snapshot = null)
    {
        if (_paused)
        {
            return "paused";
        }
        states ??= _engine.GetVisibleStates(now);
        var statuses = states.Select(state => _engine.GetStatus(state, false, now)).ToArray();
        if (statuses.Contains("aborted", StringComparer.Ordinal)) return "aborted";
        if (statuses.Contains("completed", StringComparer.Ordinal)) return "completed";
        if (_engine.LastReadErrorAt != DateTimeOffset.MinValue &&
            (now - _engine.LastReadErrorAt).TotalSeconds <= _settings.StatusTiming.ErrorHoldSeconds) return "error";
        snapshot ??= states.Select(static state => state.Snapshot)
            .OfType<HudSnapshot>()
            .OrderByDescending(static item => item.Timestamp)
            .FirstOrDefault();
        if (snapshot is null) return "idle";
        var reference = _engine.LastUsageAt != DateTimeOffset.MinValue ? _engine.LastUsageAt : snapshot.Timestamp;
        var age = (now - reference).TotalSeconds;
        return age <= _settings.StatusTiming.ActiveSeconds
            ? "active"
            : age <= _settings.StatusTiming.IdleSeconds
                ? "listening"
                : "idle";
    }

    private void ApplyPricing()
    {
        foreach (var state in _engine.States.Values)
        {
            if (state.Snapshot is null)
            {
                continue;
            }
            if (state.Snapshot.EstimatedCostUsd.HasValue)
            {
                continue;
            }
            var estimate = _pricing.Estimate(state.Snapshot);
            if (estimate is not null)
            {
                state.Snapshot = state.Snapshot with { EstimatedCostUsd = estimate.CostUsd };
            }
        }
    }

    private void SetMode(string mode)
    {
        if (mode is not ("summary" or "list" or "split"))
        {
            return;
        }
        if (mode == "summary" || mode == "list" && _settings.MultiTask.DisplayMode == "split")
        {
            _view.MergeAll();
        }
        _view.ResetTaskListVisibility();
        _configDocument["multiTask"]!["displayMode"] = mode;
        SaveAndReloadSettings();
        if (mode == "split")
        {
            _view.SplitAll(_engine.GetVisibleStates(), _settings.MultiTask.MaxSplitBubbles);
        }
        Render(force: true);
    }

    private void ToggleTaskList()
    {
        // The aggregate button is a list visibility control, not a "merge all"
        // command. In split mode and when individual bubbles are detached, it
        // must leave those windows alone.
        if (_settings.MultiTask.DisplayMode == "summary")
        {
            SetMode("list");
            return;
        }
        _view.ToggleTaskListVisibility(_settings);
        Render(force: true);
    }

    private void TogglePassthrough()
    {
        if (!_settings.MousePassthrough)
        {
            var answer = MessageBox.Show(
                Get(_settingsLocale, "mousePassthroughConfirm"),
                Get(_settingsLocale, "mousePassthroughTitle"),
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning);
            if (answer != MessageBoxResult.Yes)
            {
                return;
            }
            SetMousePassthrough(true);
            OpenSettings();
        }
        else
        {
            SetMousePassthrough(false);
        }
    }

    private void SetMousePassthrough(bool enabled)
    {
        _configDocument["mousePassthrough"] = enabled;
        SaveAndReloadSettings();
        _view.SetMousePassthrough(enabled);
        Render(force: true);
    }

    private void SaveAndReloadSettings()
    {
        HudConfigStore.Save(_paths, _configDocument);
        _settings = HudSettings.From(_configDocument);
        _engine.UpdateOptions(_settings.ToRuntimeOptions());
        _locale = _locales.Get(_settings.Language);
        _settingsLocale = _settings.Language == "symbols" ? _locales.Get("en") : _locale;
    }

    private void ReloadSettings()
    {
        var previousMode = _settings.MultiTask.DisplayMode;
        _configDocument = HudConfigStore.Load(_paths);
        _settings = HudSettings.From(_configDocument);
        _pricing = PricingCatalog.Load(_paths.PluginRoot, _settings.PricingPath);
        foreach (var state in _engine.States.Values)
        {
            if (state.Snapshot is not null)
            {
                state.Snapshot = state.Snapshot with { EstimatedCostUsd = null };
            }
        }
        _engine.UpdateOptions(_settings.ToRuntimeOptions());
        _locale = _locales.Get(_settings.Language);
        _settingsLocale = _settings.Language == "symbols" ? _locales.Get("en") : _locale;
        if (_settings.MultiTask.DisplayMode == "split" && previousMode != "split")
        {
            _view.SplitAll(_engine.GetVisibleStates(), _settings.MultiTask.MaxSplitBubbles);
        }
        else if (previousMode == "split" && _settings.MultiTask.DisplayMode != "split")
        {
            _view.MergeAll();
        }
        Render(force: true);
    }

    private void OpenSettings()
    {
        var legacy = Path.Combine(_paths.PluginRoot, "src", "CodexMonitorHUD.ps1");
        if (!File.Exists(legacy))
        {
            return;
        }
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "powershell.exe",
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                ArgumentList =
                {
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    legacy,
                    "-SettingsHost"
                }
            });
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            _log.Write("Settings host launch failed: " + exception.Message);
        }
    }

    private void OpenTask(string path)
    {
        if (!_settings.Behavior.OpenTaskOnDoubleClick || !_engine.States.TryGetValue(path, out var state))
        {
            return;
        }
        var link = HudFormatting.GetTaskDeepLink(state.SessionId);
        if (link is null)
        {
            return;
        }
        try
        {
            _ = Process.Start(new ProcessStartInfo(link) { UseShellExecute = true });
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            _log.Write("Task deep link failed: " + exception.Message);
        }
    }

    private bool ProcessNotifications(DateTimeOffset now)
    {
        if (!Directory.Exists(_notificationsRoot))
        {
            return false;
        }
        var changed = false;
        foreach (var path in Directory.EnumerateFiles(_notificationsRoot, "*.json").OrderBy(static path =>
                 {
                     try { return File.GetCreationTimeUtc(path); }
                     catch (IOException) { return DateTime.MaxValue; }
                     catch (UnauthorizedAccessException) { return DateTime.MaxValue; }
                 }))
        {
            try
            {
                var file = new FileInfo(path);
                if (!_settings.AgentNotifications.Enabled || file.Length > 8192)
                {
                    _log.Write($"Agent notice discarded; enabled={_settings.AgentNotifications.Enabled}; bytes={file.Length}");
                    TryDelete(path);
                    continue;
                }
                using var document = JsonDocument.Parse(File.ReadAllText(path));
                var root = document.RootElement;
                if (!root.TryGetProperty("source", out var source) || source.GetString() != "codex-mcp")
                {
                    throw new InvalidDataException("Unsupported notification source.");
                }
                var message = root.TryGetProperty("message", out var messageNode) ? messageNode.GetString() ?? string.Empty : string.Empty;
                message = ControlRegex().Replace(message, " ");
                message = WhitespaceRegex().Replace(message, " ").Trim();
                if (message.Length > 160) message = message[..160];
                if (message.Length == 0) throw new InvalidDataException("Empty notification.");
                int? taskNumber = root.TryGetProperty("task_number", out var taskNode) && taskNode.TryGetInt32(out var number)
                    ? number
                    : null;
                var recipe = _settings.AgentNotifications.Permission == "expressive" &&
                             root.TryGetProperty("animation", out var animationNode)
                    ? ParseAgentAnimationRecipe(animationNode, _settings.AgentNotifications.Color)
                    : null;
                if (_engine.AcceptAgentNotice(taskNumber, message, _settings.AgentNotifications.DurationSeconds, recipe, now))
                {
                    var targetLabel = taskNumber?.ToString() ?? "auto";
                    _log.Write($"Agent notice accepted for task #{targetLabel}; expressive={recipe is not null}");
                    TryDelete(path);
                    changed = true;
                }
                else if (now.UtcDateTime - file.CreationTimeUtc > TimeSpan.FromSeconds(60))
                {
                    _log.Write($"Agent notice expired before a visible target was available; task=#{taskNumber?.ToString() ?? "auto"}");
                    TryDelete(path);
                }
                else
                {
                    _log.Write($"Agent notice deferred; target task #{taskNumber?.ToString() ?? "auto"} is not visible yet");
                }
            }
            catch (Exception exception) when (exception is JsonException or IOException or InvalidDataException)
            {
                _log.Write("Agent notice rejected: " + exception.Message);
                TryDelete(path);
            }
        }
        return changed;
    }

    private void WriteTaskRegistry(IReadOnlyList<SessionState> states, DateTimeOffset now)
    {
        var tasks = states.OrderBy(static state => state.Number).Select(state => new
        {
            task_number = state.Number,
            workspace = state.Workspace,
            status = _engine.GetStatus(state, _paused, now),
            updated_at = state.LastUsageAt.ToString("O")
        }).ToArray();
        var content = JsonSerializer.Serialize(tasks);
        if (content == _lastRegistryContent)
        {
            return;
        }
        _lastRegistryContent = content;
        var registry = JsonSerializer.Serialize(new
        {
            version = 1,
            generated_at = now.ToString("O"),
            tasks
        });
        TryWriteText(Path.Combine(_paths.StateRoot, "task-registry.json"), registry);
    }

    private bool HasActiveHost(DateTimeOffset now)
    {
        try
        {
            if (Directory.Exists(_hostsRoot))
            {
                var cutoff = now.UtcDateTime.AddSeconds(-8);
                foreach (var path in Directory.EnumerateFiles(_hostsRoot, "*.heartbeat"))
                {
                    if (File.GetLastWriteTimeUtc(path) >= cutoff)
                    {
                        return true;
                    }
                    TryDelete(path);
                }
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
        if (_arguments.ParentPid <= 0)
        {
            return false;
        }
        try
        {
            using var process = Process.GetProcessById(_arguments.ParentPid);
            return !process.HasExited;
        }
        catch (ArgumentException)
        {
            return false;
        }
    }

    private bool ConsumeSignal(string name)
    {
        var path = Path.Combine(_paths.StateRoot, name);
        if (!File.Exists(path))
        {
            return false;
        }
        TryDelete(path);
        return true;
    }

    private void Stop()
    {
        _timer.Stop();
        _application.Shutdown();
    }

    private void StopByUser()
    {
        TryWriteText(Path.Combine(_paths.StateRoot, "manual-exit.signal"), DateTime.UtcNow.ToString("O"));
        Stop();
    }

    private void TryWriteText(string path, string content)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var temporary = path + ".tmp";
            File.WriteAllText(temporary, content, new UTF8Encoding(false));
            File.Move(temporary, path, overwrite: true);
        }
        catch (IOException exception)
        {
            _log.Write("State write failed: " + exception.Message);
        }
        catch (UnauthorizedAccessException exception)
        {
            _log.Write("State write denied: " + exception.Message);
        }
    }

    private static void TryDelete(string path)
    {
        try { File.Delete(path); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private static string Get(IReadOnlyDictionary<string, string> locale, string key) =>
        locale.TryGetValue(key, out var value) ? value : key;

    private static AgentAnimationRecipe? ParseAgentAnimationRecipe(JsonElement node, string fallbackColor)
    {
        if (node.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var allowedLayers = new HashSet<string>(new[] { "glow", "pulse", "breathe", "flow" }, StringComparer.Ordinal);
        var layers = node.TryGetProperty("layers", out var layersNode) && layersNode.ValueKind == JsonValueKind.Array
            ? layersNode.EnumerateArray()
                .Where(static item => item.ValueKind == JsonValueKind.String)
                .Select(static item => item.GetString() ?? string.Empty)
                .Where(allowedLayers.Contains)
                .Distinct(StringComparer.Ordinal)
                .Take(4)
                .ToArray()
            : Array.Empty<string>();
        if (layers.Length == 0)
        {
            return null;
        }

        var color = node.TryGetProperty("color", out var colorNode) && colorNode.ValueKind == JsonValueKind.String
            ? colorNode.GetString() ?? fallbackColor
            : fallbackColor;
        if (!Regex.IsMatch(color, "^#[0-9A-Fa-f]{8}$", RegexOptions.CultureInvariant))
        {
            color = fallbackColor;
        }

        return new AgentAnimationRecipe(
            layers,
            color,
            ReadBoundedDouble(node, "intensity", 0.70, 0.20, 1.00),
            (int)Math.Round(ReadBoundedDouble(node, "tempo_ms", 720, 240, 2500)),
            (int)Math.Round(ReadBoundedDouble(node, "cycles", 3, 1, 8)),
            ReadBoundedDouble(node, "glow_radius", 30, 8, 60),
            ReadBoundedDouble(node, "scale", 1.028, 1, 1.08),
            node.TryGetProperty("direction", out var directionNode) && directionNode.GetString() == "right-to-left"
                ? "right-to-left"
                : "left-to-right");
    }

    private static double ReadBoundedDouble(JsonElement node, string name, double fallback, double minimum, double maximum)
    {
        var value = node.TryGetProperty(name, out var property) && property.TryGetDouble(out var candidate)
            ? candidate
            : fallback;
        return double.IsFinite(value) ? Math.Clamp(value, minimum, maximum) : fallback;
    }

    [GeneratedRegex("[\\x00-\\x1F\\x7F]+", RegexOptions.CultureInvariant)]
    private static partial Regex ControlRegex();

    [GeneratedRegex("\\s+", RegexOptions.CultureInvariant)]
    private static partial Regex WhitespaceRegex();
}
