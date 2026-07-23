using CodexMonitorHud.Core.Models;
using CodexMonitorHud.Core.Parsing;
using CodexMonitorHud.Core.Presentation;
using CodexMonitorHud.Core.Sessions;

namespace CodexMonitorHud.Core.State;

public sealed class SessionMonitorEngine
{
    private const int PerSessionReadBudgetBytes = 256 * 1024;
    private const int GlobalReadBudgetBytes = 4 * 1024 * 1024;
    private readonly string _sessionsRoot;
    private readonly string _sessionIndexPath;
    private readonly TaskNumberPool _numberPool;
    private readonly SessionTitleIndex _titleIndex = new();
    private readonly StringComparer _pathComparer;
    private readonly Dictionary<string, SessionState> _states;
    private readonly HashSet<string> _backlogPaths;
    private int _attentionSequence;

    public SessionMonitorEngine(
        string sessionsRoot,
        string sessionIndexPath,
        HudRuntimeOptions options,
        StringComparer? pathComparer = null)
    {
        _sessionsRoot = sessionsRoot;
        _sessionIndexPath = sessionIndexPath;
        _pathComparer = pathComparer ?? SessionChangeTracker.GetPlatformPathComparer();
        _states = new Dictionary<string, SessionState>(_pathComparer);
        _backlogPaths = new HashSet<string>(_pathComparer);
        Options = options;
        _numberPool = new TaskNumberPool();
    }

    public HudRuntimeOptions Options { get; private set; }
    public IReadOnlyDictionary<string, SessionState> States => _states;
    public long MaterialRevision { get; private set; }
    public DateTimeOffset LastUsageAt { get; private set; } = DateTimeOffset.MinValue;
    public DateTimeOffset LastReadErrorAt { get; private set; } = DateTimeOffset.MinValue;
    public bool HasBacklog => _backlogPaths.Count > 0;
    public bool HasTitleBacklog => _titleIndex.HasBacklog;
    public bool HasPendingIdentity => _states.Values.Any(static state => !state.IdentityMetadataFound && !state.IsInternalSession);

    public void UpdateOptions(HudRuntimeOptions options)
    {
        Options = options;
        foreach (var state in _states.Values)
        {
            state.ContextAlertLevel = 0;
            state.ContextAlertPercent = 0;
            state.ContextAlertUntil = DateTimeOffset.MinValue;
            if (state.AttentionReason == "context")
            {
                state.AttentionReason = string.Empty;
                state.AttentionUntil = DateTimeOffset.MinValue;
            }
        }
        MaterialRevision++;
    }

    public bool RefreshActiveSessions(DateTimeOffset? now = null)
    {
        var current = now ?? DateTimeOffset.Now;
        var changed = RefreshTitlesCore();

        var files = SessionDiscovery.GetActiveFiles(
            _sessionsRoot,
            Options.ActiveWindowMinutes,
            Options.MaximumFiles,
            current.UtcDateTime);
        var activePaths = new HashSet<string>(_pathComparer);
        foreach (var file in files)
        {
            activePaths.Add(file.FullName);
            try
            {
                if (!_states.TryGetValue(file.FullName, out var state))
                {
                    state = Initialize(file);
                    _states.Add(file.FullName, state);
                    changed = true;
                }
                else if (RefreshIdentity(state))
                {
                    changed = true;
                }
            }
            catch (IOException)
            {
                LastReadErrorAt = current;
            }
            catch (UnauthorizedAccessException)
            {
                LastReadErrorAt = current;
            }
        }

        foreach (var removed in _states.Keys.Where(path => !activePaths.Contains(path)).ToArray())
        {
            var state = _states[removed];
            _numberPool.Release(state.Number, Options.NumberCooldownSeconds, current);
            _states.Remove(removed);
            _backlogPaths.Remove(removed);
            changed = true;
        }

        if (changed)
        {
            MaterialRevision++;
        }
        return changed;
    }

    public bool RefreshTitles()
    {
        var changed = RefreshTitlesCore();
        if (changed)
        {
            MaterialRevision++;
        }
        return changed;
    }

    public bool Poll(DateTimeOffset? now = null)
    {
        return PollStates(_states.Values, now ?? DateTimeOffset.Now);
    }

    public bool PollPaths(IEnumerable<string> paths, DateTimeOffset? now = null)
    {
        var selected = paths
            .Distinct(_pathComparer)
            .Select(path => _states.GetValueOrDefault(path))
            .OfType<SessionState>()
            .ToArray();
        return PollStates(selected, now ?? DateTimeOffset.Now);
    }

    public bool PollBacklog(DateTimeOffset? now = null)
    {
        var selected = _backlogPaths
            .Select(path => _states.GetValueOrDefault(path))
            .OfType<SessionState>()
            .ToArray();
        return PollStates(selected, now ?? DateTimeOffset.Now);
    }

    public bool PollPendingIdentity(DateTimeOffset? now = null)
    {
        var selected = _states.Values.Where(static state => !state.IdentityMetadataFound && !state.IsInternalSession).ToArray();
        return PollStates(selected, now ?? DateTimeOffset.Now);
    }

    public bool AdvanceLifecycleOnly(DateTimeOffset? now = null)
    {
        var changed = AdvanceLifecycle(now ?? DateTimeOffset.Now);
        if (changed)
        {
            MaterialRevision++;
        }
        return changed;
    }

    private bool PollStates(IEnumerable<SessionState> states, DateTimeOffset current)
    {
        var changed = false;
        var remainingReadBudget = GlobalReadBudgetBytes;
        foreach (var state in states)
        {
            if (state.IsInternalSession)
            {
                _backlogPaths.Remove(state.Path);
                continue;
            }
            try
            {
                var file = new FileInfo(state.Path);
                file.Refresh();
                if (!file.Exists)
                {
                    continue;
                }

                if (file.LastWriteTimeUtc > state.LastWriteTimeUtc || file.Length != state.Reader.Offset)
                {
                    if (remainingReadBudget <= 0)
                    {
                        _backlogPaths.Add(state.Path);
                        continue;
                    }
                    changed |= ReadAppended(state, current, Math.Min(PerSessionReadBudgetBytes, remainingReadBudget));
                    remainingReadBudget -= Math.Min(remainingReadBudget, state.Reader.LastReadBytes);
                }
            }
            catch (IOException)
            {
                RecordReadError(state, current);
            }
            catch (UnauthorizedAccessException)
            {
                RecordReadError(state, current);
            }
        }

        changed |= AdvanceLifecycle(current);
        if (changed)
        {
            MaterialRevision++;
        }
        return changed;
    }

    private bool RefreshTitlesCore()
    {
        if (!_titleIndex.Refresh(_sessionIndexPath))
        {
            return false;
        }

        foreach (var state in _states.Values)
        {
            state.ConversationLabel = _titleIndex.GetTitle(state.SessionId);
        }
        return true;
    }

    public IReadOnlyList<SessionState> GetVisibleStates(DateTimeOffset? now = null) =>
        _states.Values
            .Where(state => IsVisible(state, now ?? DateTimeOffset.Now))
            .OrderBy(state => state.Number)
            .ToArray();

    public string GetStatus(SessionState state, bool paused, DateTimeOffset? now = null)
    {
        var current = now ?? DateTimeOffset.Now;
        if (paused)
        {
            return "paused";
        }

        if (!string.IsNullOrWhiteSpace(state.TerminalStatus) &&
            state.TerminalAt != DateTimeOffset.MinValue &&
            !state.TerminalExitCompleted)
        {
            return state.TerminalStatus;
        }

        if (state.LastReadErrorAt != DateTimeOffset.MinValue &&
            (current - state.LastReadErrorAt).TotalSeconds <= Options.ErrorHoldSeconds)
        {
            return "error";
        }

        if (state.Snapshot is null)
        {
            return "idle";
        }

        var reference = state.LastUsageAt != DateTimeOffset.MinValue
            ? state.LastUsageAt
            : state.Snapshot.Timestamp;
        var age = (current - reference).TotalSeconds;
        return age <= Options.ActiveSeconds
            ? "active"
            : age <= Options.IdleSeconds
                ? "listening"
                : "idle";
    }

    public void Dismiss(string path)
    {
        if (_states.TryGetValue(path, out var state) && !state.Dismissed)
        {
            state.Dismissed = true;
            MaterialRevision++;
        }
    }

    public bool HoldTerminalExits { get; set; }

    public bool AcceptAgentNotice(
        int? taskNumber,
        string message,
        int durationSeconds,
        AgentAnimationRecipe? recipe = null,
        DateTimeOffset? now = null)
    {
        var current = now ?? DateTimeOffset.Now;
        var candidates = GetVisibleStates(current);
        var target = taskNumber.HasValue && taskNumber.Value > 0
            ? candidates.FirstOrDefault(state => state.Number == taskNumber.Value)
            : candidates.OrderByDescending(static state => state.LastUsageAt)
                .ThenByDescending(static state => state.LastWriteTimeUtc)
                .FirstOrDefault();
        if (target is null)
        {
            return false;
        }

        target.AgentNoticeText = message;
        target.AgentNoticeUntil = current.AddSeconds(Math.Clamp(durationSeconds, 4, 60));
        target.AgentNoticeRecipe = recipe;
        target.AttentionRevision = ++_attentionSequence;
        target.AttentionReason = "agent";
        target.AttentionUntil = target.AgentNoticeUntil;
        if (!string.IsNullOrWhiteSpace(target.TerminalStatus))
        {
            ResetTerminalExit(target);
        }
        MaterialRevision++;
        return true;
    }

    private SessionState Initialize(SessionFile file)
    {
        var identity = SessionIdentityReader.Read(file.FullName);
        var snapshot = identity.IsInternalSession ? null : BoundedTailReader.ReadLatestSnapshot(file.FullName);
        return new SessionState
        {
            Path = file.FullName,
            Number = _numberPool.Acquire(),
            StartedAt = new DateTimeOffset(File.GetCreationTime(file.FullName)),
            Reader = new IncrementalJsonlReader(file.Length),
            Model = snapshot?.Model ?? string.Empty,
            Workspace = !string.IsNullOrWhiteSpace(snapshot?.Workspace)
                ? snapshot!.Workspace
                : identity.Workspace,
            Snapshot = snapshot,
            AllowanceTimestamp = snapshot?.AllowanceTimestamp,
            WeeklyRemainingPercent = snapshot?.WeeklyRemainingPercent,
            FiveHourRemainingPercent = snapshot?.FiveHourRemainingPercent,
            LastWriteTimeUtc = file.LastWriteTimeUtc,
            LastUsageAt = snapshot?.Timestamp ?? DateTimeOffset.MinValue,
            TerminalStatus = snapshot?.TerminalStatus ?? string.Empty,
            TerminalAt = snapshot?.TerminalTimestamp ?? DateTimeOffset.MinValue,
            TerminalSilent = snapshot?.TerminalSilent ?? false,
            IsInternalSession = identity.IsInternalSession,
            IdentityMetadataFound = identity.MetadataFound,
            SessionId = identity.SessionId,
            ConversationLabel = _titleIndex.GetTitle(identity.SessionId)
        };
    }

    private bool RefreshIdentity(SessionState state)
    {
        if (state.IdentityMetadataFound)
        {
            return false;
        }

        var identity = SessionIdentityReader.Read(state.Path);
        if (!identity.MetadataFound)
        {
            return false;
        }

        ApplyIdentity(state, identity);
        return true;
    }

    private bool ReadAppended(SessionState state, DateTimeOffset now, int maximumBytes)
    {
        try
        {
            var identityChanged = RefreshIdentity(state);
            if (state.IsInternalSession)
            {
                _backlogPaths.Remove(state.Path);
                return identityChanged;
            }
            var file = new FileInfo(state.Path);
            file.Refresh();
            if (!file.Exists)
            {
                return identityChanged;
            }

            state.LastWriteTimeUtc = file.LastWriteTimeUtc;
            var lines = state.Reader.ReadAppended(state.Path, maximumBytes);
            if (state.Reader.HasUnreadData) _backlogPaths.Add(state.Path);
            else _backlogPaths.Remove(state.Path);
            var updated = identityChanged;
            foreach (var line in lines)
            {
                if (!state.IdentityMetadataFound)
                {
                    var identity = SessionIdentityReader.ParseLine(line);
                    if (identity.MetadataFound)
                    {
                        ApplyIdentity(state, identity);
                        updated = true;
                        if (state.IsInternalSession)
                        {
                            _backlogPaths.Remove(state.Path);
                            break;
                        }
                    }
                }

                var item = HudRecordParser.Parse(line);
                if (item is null)
                {
                    continue;
                }

                updated |= ApplyRecord(state, item, now);
            }
            return updated;
        }
        catch (IOException)
        {
            RecordReadError(state, now);
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            RecordReadError(state, now);
            return false;
        }
        catch (InvalidDataException)
        {
            RecordReadError(state, now);
            return false;
        }
    }

    private bool ApplyRecord(SessionState state, HudRecord item, DateTimeOffset now)
    {
        switch (item.Kind)
        {
            case HudRecordKind.Context:
                state.Model = item.Model;
                state.Workspace = item.Workspace;
                return true;
            case HudRecordKind.Started:
                state.ActiveTurnId = item.TurnId;
                ClearPendingCompletion(state);
                state.TerminalStatus = string.Empty;
                state.TerminalAt = DateTimeOffset.MinValue;
                state.TerminalSilent = false;
                ResetTerminalExit(state);
                state.Dismissed = false;
                state.LastUsageAt = now;
                state.HasObservedActivity = true;
                return true;
            case HudRecordKind.Completed:
                if (string.IsNullOrWhiteSpace(state.ActiveTurnId) || item.TurnId == state.ActiveTurnId)
                {
                    state.PendingCompletionTurnId = item.TurnId;
                    state.PendingCompletionDueAt = now.AddSeconds(Options.CompletionGraceSeconds);
                    if (Options.CompletionGraceSeconds == 0)
                    {
                        _ = ConfirmPendingCompletion(state, now);
                    }
                }
                return true;
            case HudRecordKind.CompletedSilent:
                ClearPendingCompletion(state);
                state.TerminalStatus = "completed";
                state.TerminalAt = item.Timestamp;
                state.TerminalSilent = true;
                ResetTerminalExit(state);
                return true;
            case HudRecordKind.Aborted:
                ClearPendingCompletion(state);
                state.TerminalStatus = "aborted";
                state.TerminalAt = item.Timestamp;
                state.TerminalSilent = false;
                ResetTerminalExit(state);
                SetAttention(state, "aborted", now);
                return true;
            case HudRecordKind.Allowance:
                ApplyAllowance(state, item);
                return true;
            case HudRecordKind.Usage:
                ApplyAllowance(state, item);
                var snapshot = HudSnapshot.FromUsage(item) with
                {
                    Model = state.Model,
                    Workspace = state.Workspace,
                    AllowanceTimestamp = state.AllowanceTimestamp,
                    WeeklyRemainingPercent = state.WeeklyRemainingPercent,
                    FiveHourRemainingPercent = state.FiveHourRemainingPercent
                };
                state.Snapshot = snapshot;
                state.LastUsageAt = now;
                state.LastReadErrorAt = DateTimeOffset.MinValue;
                state.HasObservedActivity = true;
                LastUsageAt = now;
                UpdateContextAlert(state, now);
                return true;
            default:
                return false;
        }
    }

    private bool AdvanceLifecycle(DateTimeOffset now)
    {
        var changed = false;
        foreach (var state in _states.Values)
        {
            if (state.AgentNoticeUntil != DateTimeOffset.MinValue && state.AgentNoticeUntil <= now)
            {
                state.AgentNoticeText = string.Empty;
                state.AgentNoticeUntil = DateTimeOffset.MinValue;
                state.AgentNoticeRecipe = null;
                if (state.AttentionReason == "agent")
                {
                    state.AttentionUntil = DateTimeOffset.MinValue;
                    state.AttentionReason = string.Empty;
                }
                changed = true;
            }
            if (state.ContextAlertUntil != DateTimeOffset.MinValue && state.ContextAlertUntil <= now)
            {
                state.ContextAlertUntil = DateTimeOffset.MinValue;
                if (state.AttentionReason == "context")
                {
                    state.AttentionUntil = DateTimeOffset.MinValue;
                    state.AttentionReason = string.Empty;
                }
                changed = true;
            }
            if (state.AttentionUntil != DateTimeOffset.MinValue && state.AttentionUntil <= now)
            {
                state.AttentionUntil = DateTimeOffset.MinValue;
                state.AttentionReason = string.Empty;
                changed = true;
            }
            changed |= ConfirmPendingCompletion(state, now);
            var nextStatus = GetStatus(state, paused: false, now);
            if (!string.IsNullOrWhiteSpace(state.LastRenderedStatus) && state.LastRenderedStatus != nextStatus)
            {
                changed = true;
                if (nextStatus == "error")
                {
                    SetAttention(state, "error", now);
                }
                else if (nextStatus == "idle" && state.LastRenderedStatus is "active" or "listening" &&
                         state.HasObservedActivity && string.IsNullOrWhiteSpace(state.TerminalStatus))
                {
                    SetAttention(state, "settled", now);
                }
            }
            state.LastRenderedStatus = nextStatus;
            changed |= UpdateTerminalExit(state, now);
        }
        return changed;
    }

    private bool ConfirmPendingCompletion(SessionState state, DateTimeOffset now)
    {
        if (state.PendingCompletionDueAt == DateTimeOffset.MinValue || state.PendingCompletionDueAt > now)
        {
            return false;
        }

        if (!string.IsNullOrWhiteSpace(state.PendingCompletionTurnId) &&
            !string.IsNullOrWhiteSpace(state.ActiveTurnId) &&
            state.PendingCompletionTurnId != state.ActiveTurnId)
        {
            ClearPendingCompletion(state);
            return false;
        }

        state.TerminalStatus = "completed";
        state.TerminalAt = now;
        state.TerminalSilent = false;
        ResetTerminalExit(state);
        ClearPendingCompletion(state);
        SetAttention(state, "completed", now);
        return true;
    }

    private bool UpdateTerminalExit(SessionState state, DateTimeOffset now)
    {
        if (string.IsNullOrWhiteSpace(state.TerminalStatus) || state.TerminalAt == DateTimeOffset.MinValue)
        {
            if (state.TerminalExitStarted || state.TerminalExitCompleted)
            {
                ResetTerminalExit(state);
                return true;
            }
            return false;
        }

        if (HoldTerminalExits || state.TerminalExitCompleted || state.AgentNoticeUntil > now || state.AttentionUntil > now ||
            state.TerminalAt.AddSeconds(Options.TerminalHoldSeconds) > now)
        {
            return false;
        }

        if (!state.TerminalExitStarted)
        {
            state.TerminalExitStarted = true;
            state.TerminalExitUntil = now.AddMilliseconds(GetTerminalExitDuration(Options.TerminalExitMode));
            state.TerminalExitRevision++;
            return true;
        }

        if (state.TerminalExitUntil <= now)
        {
            state.TerminalExitCompleted = true;
            return true;
        }
        return false;
    }

    private void UpdateContextAlert(SessionState state, DateTimeOffset now)
    {
        if (!Options.ContextAlertsEnabled || state.Snapshot is null)
        {
            return;
        }

        var next = HudFormatting.GetContextAlertLevel(state.Snapshot.ContextPercent, Options.ContextThresholds);
        var previous = state.ContextAlertLevel;
        state.ContextAlertLevel = next;
        if (next <= previous)
        {
            return;
        }

        state.ContextAlertPercent = Math.Round(state.Snapshot.ContextPercent, 1);
        state.ContextAlertUntil = now.AddSeconds(Options.AttentionDurationSeconds);
        state.AttentionRevision = ++_attentionSequence;
        state.AttentionReason = "context";
        state.AttentionUntil = state.ContextAlertUntil;
    }

    private void SetAttention(SessionState state, string reason, DateTimeOffset now)
    {
        var enabled = reason switch
        {
            "completed" => Options.AttentionOnCompleted,
            "aborted" or "error" => Options.AttentionOnAbortedOrError,
            "settled" => Options.AttentionOnSettled,
            _ => false
        };
        if (!enabled || !Options.AnyAttentionSurfaceEnabled && !Options.AttentionDotEnabled)
        {
            return;
        }

        state.AttentionRevision = ++_attentionSequence;
        state.AttentionReason = reason;
        state.AttentionUntil = now.AddSeconds(Options.AttentionDurationSeconds);
    }

    private void ApplyIdentity(SessionState state, SessionIdentity identity)
    {
        state.IdentityMetadataFound = true;
        state.IsInternalSession = identity.IsInternalSession;
        state.SessionId = identity.SessionId;
        state.ConversationLabel = _titleIndex.GetTitle(identity.SessionId);
        if (string.IsNullOrWhiteSpace(state.Workspace) && !string.IsNullOrWhiteSpace(identity.Workspace))
        {
            state.Workspace = identity.Workspace;
        }
    }

    private void ApplyAllowance(SessionState state, HudRecord item)
    {
        if (!item.WeeklyRemainingPercent.HasValue && !item.FiveHourRemainingPercent.HasValue)
        {
            return;
        }

        state.AllowanceTimestamp = item.AllowanceTimestamp;
        state.WeeklyRemainingPercent = item.WeeklyRemainingPercent;
        state.FiveHourRemainingPercent = item.FiveHourRemainingPercent;
        if (state.Snapshot is not null)
        {
            state.Snapshot = state.Snapshot with
            {
                AllowanceTimestamp = state.AllowanceTimestamp,
                WeeklyRemainingPercent = state.WeeklyRemainingPercent,
                FiveHourRemainingPercent = state.FiveHourRemainingPercent
            };
        }
    }

    private static bool IsVisible(SessionState state, DateTimeOffset now)
    {
        // Identity is the privacy boundary: do not flash unclassified files or
        // internal/subagent sessions.  A newly confirmed user session may not
        // have emitted its first token_count record yet, however.  Keep that
        // task visible as "waiting" so an active conversation is never
        // mistaken for an unmonitored one.
        if (!state.IdentityMetadataFound || state.IsInternalSession || state.Dismissed)
        {
            return false;
        }

        if (!string.IsNullOrWhiteSpace(state.TerminalStatus) && state.TerminalAt != DateTimeOffset.MinValue)
        {
            return state.AgentNoticeUntil > now || !state.TerminalExitCompleted;
        }
        return true;
    }

    private void RecordReadError(SessionState state, DateTimeOffset now)
    {
        state.LastReadErrorAt = now;
        LastReadErrorAt = now;
    }

    private static void ClearPendingCompletion(SessionState state)
    {
        state.PendingCompletionTurnId = string.Empty;
        state.PendingCompletionDueAt = DateTimeOffset.MinValue;
    }

    private static void ResetTerminalExit(SessionState state)
    {
        state.TerminalExitStarted = false;
        state.TerminalExitCompleted = false;
        state.TerminalExitUntil = DateTimeOffset.MinValue;
    }

    private static double GetTerminalExitDuration(string mode) => mode switch
    {
        "fade" => 1200,
        "focus" => 3600,
        "beacon" => 5000,
        _ => 2400
    };
}
