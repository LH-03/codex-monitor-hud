using CodexMonitorHud.Core.Models;
using CodexMonitorHud.Core.Parsing;
using CodexMonitorHud.Core.Presentation;
using CodexMonitorHud.Core.Sessions;
using System.Text.RegularExpressions;

namespace CodexMonitorHud.Core.State;

public sealed class SessionMonitorEngine
{
    private const int PerSessionReadBudgetBytes = 256 * 1024;
    private const int GlobalReadBudgetBytes = 4 * 1024 * 1024;
    private static readonly TimeSpan LockRecoveryGrace = TimeSpan.FromMinutes(10);
    private static readonly TimeSpan RuntimeHeartbeatFreshness = TimeSpan.FromMinutes(3);
    private static readonly Regex RolloutSessionIdPattern = new(
        "(?<id>[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})(?:\\.jsonl)?$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);
    private readonly IReadOnlyList<SessionProfile> _profiles;
    private readonly IReadOnlyDictionary<string, SessionProfile> _profileById;
    private readonly TaskNumberPool _numberPool;
    private readonly IReadOnlyDictionary<string, SessionTitleIndex> _titleIndexes;
    private readonly ISessionActivitySource _activitySource;
    private readonly StringComparer _pathComparer;
    private readonly Dictionary<string, SessionState> _states;
    private readonly HashSet<string> _backlogPaths;
    private int _attentionSequence;

    public SessionMonitorEngine(
        string sessionsRoot,
        string sessionIndexPath,
        HudRuntimeOptions options,
        StringComparer? pathComparer = null,
        ISessionActivitySource? activitySource = null)
        : this(
            new[]
            {
                new SessionProfile(
                    SessionProfile.DefaultId,
                    "Codex",
                    sessionsRoot,
                    sessionIndexPath,
                    "unknown",
                    string.Empty)
            },
            options,
            pathComparer,
            activitySource)
    {
    }

    public SessionMonitorEngine(
        IEnumerable<SessionProfile> profiles,
        HudRuntimeOptions options,
        StringComparer? pathComparer = null,
        ISessionActivitySource? activitySource = null)
    {
        _pathComparer = pathComparer ?? SessionChangeTracker.GetPlatformPathComparer();
        _profiles = profiles
            .Select(profile => profile with
            {
                SessionsRoot = Path.GetFullPath(profile.SessionsRoot),
                SessionIndexPath = Path.GetFullPath(profile.SessionIndexPath),
                StateDatabasePath = string.IsNullOrWhiteSpace(profile.StateDatabasePath)
                    ? string.Empty
                    : Path.GetFullPath(profile.StateDatabasePath)
            })
            .GroupBy(static profile => profile.SessionsRoot, _pathComparer)
            .Select(static group => group.First())
            .ToArray();
        if (_profiles.Count == 0)
        {
            throw new ArgumentException("At least one Codex session profile is required.", nameof(profiles));
        }
        _profileById = _profiles.ToDictionary(static profile => profile.Id, StringComparer.Ordinal);
        _titleIndexes = _profiles.ToDictionary(static profile => profile.Id, static _ => new SessionTitleIndex(), StringComparer.Ordinal);
        _activitySource = activitySource ?? EmptySessionActivitySource.Instance;
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
    public bool HasTitleBacklog => _titleIndexes.Values.Any(static index => index.HasBacklog);
    public bool HasPendingIdentity => _states.Values.Any(static state =>
        (!state.IdentityMetadataFound || state.IdentityProvisional || state.NeedsSnapshotHydration) &&
        !state.IsInternalSession);

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

        var files = DiscoverActiveFiles(current);
        var activePaths = new HashSet<string>(_pathComparer);
        foreach (var candidate in files)
        {
            var file = candidate.File;
            activePaths.Add(file.FullName);
            try
            {
                if (!_states.TryGetValue(file.FullName, out var state))
                {
                    state = Initialize(candidate.Profile, file, current);
                    _states.Add(file.FullName, state);
                    changed = true;
                }
                else
                {
                    changed |= UpdateReadBlockState(state, file.ReadBlocked, current);
                    if (!state.IsReadBlocked && RefreshIdentity(state, current))
                    {
                        changed = true;
                    }
                }
                changed |= UpdateRuntimeActivity(state, candidate.RuntimeActivityAt, current);
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

        foreach (var path in _states.Keys.Where(path => !activePaths.Contains(path)).ToArray())
        {
            var state = _states[path];
            var readBlocked = SessionDiscovery.IsReadBlocked(path);
            changed |= UpdateReadBlockState(state, readBlocked, current);
            if (readBlocked)
            {
                activePaths.Add(path);
                continue;
            }

            if (state.LastLockObservedAt != DateTimeOffset.MinValue &&
                current - state.LastLockObservedAt <= LockRecoveryGrace)
            {
                activePaths.Add(path);
                if (RefreshIdentity(state, current))
                {
                    changed = true;
                }
                continue;
            }

            _numberPool.Release(state.Number, Options.NumberCooldownSeconds, current);
            _states.Remove(path);
            _backlogPaths.Remove(path);
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

    public bool RefreshRuntimeSessions(DateTimeOffset? now = null)
    {
        var current = now ?? DateTimeOffset.Now;
        var cutoff = current.Subtract(GetRuntimeDiscoveryWindow());
        var maximum = Math.Max(1, Options.MaximumFiles);
        var changed = false;
        foreach (var profile in _profiles.Where(IsProfileDiscoveryEnabled))
        {
            foreach (var activity in _activitySource.GetRecentUserSessions(profile, cutoff, maximum))
            {
                if (!TryCreateActivityCandidate(profile, activity, out var candidate))
                {
                    continue;
                }

                try
                {
                    if (!_states.TryGetValue(candidate.File.FullName, out var state))
                    {
                        state = Initialize(profile, candidate.File, current);
                        _states.Add(candidate.File.FullName, state);
                        changed = true;
                    }
                    else
                    {
                        changed |= UpdateReadBlockState(state, candidate.File.ReadBlocked, current);
                        if (!state.IsReadBlocked)
                        {
                            changed |= RefreshIdentity(state, current);
                        }
                    }
                    changed |= UpdateRuntimeActivity(state, activity.UpdatedAt, current);
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
        }

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
        var selected = _states.Values.Where(static state =>
            (!state.IdentityMetadataFound || state.IdentityProvisional || state.NeedsSnapshotHydration) &&
            !state.IsInternalSession).ToArray();
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
            if (state.IsReadBlocked)
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
                HandleReadFailure(state, current);
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
        var refreshed = new HashSet<string>(StringComparer.Ordinal);
        foreach (var profile in _profiles)
        {
            if (_titleIndexes[profile.Id].Refresh(profile.SessionIndexPath))
            {
                refreshed.Add(profile.Id);
            }
        }
        if (refreshed.Count == 0)
        {
            return false;
        }
        foreach (var state in _states.Values.Where(state => refreshed.Contains(state.ProfileId)))
        {
            var nextTitle = _titleIndexes[state.ProfileId].GetTitle(state.SessionId);
            state.ConversationLabel = nextTitle;
            if (state.IsReadBlocked && !state.IdentityMetadataFound &&
                !string.IsNullOrWhiteSpace(state.SessionId) && !string.IsNullOrWhiteSpace(nextTitle))
            {
                state.IdentityMetadataFound = true;
                state.IdentityProvisional = true;
                state.NeedsSnapshotHydration = true;
            }
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

        if (HasFreshRuntimeActivity(state, current))
        {
            return "active";
        }

        if (state.LastReadErrorAt != DateTimeOffset.MinValue &&
            (current - state.LastReadErrorAt).TotalSeconds <= Options.ErrorHoldSeconds)
        {
            return "error";
        }

        if (state.IsReadBlocked || state.IdentityProvisional || state.NeedsSnapshotHydration)
        {
            return "listening";
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

    private SessionState Initialize(SessionProfile profile, SessionFile file, DateTimeOffset current)
    {
        var identity = SessionIdentityReader.Read(file.FullName);
        var readBlocked = file.ReadBlocked;
        HudSnapshot? snapshot = null;
        var needsSnapshotHydration = false;
        if (!identity.IsInternalSession)
        {
            try
            {
                snapshot = BoundedTailReader.ReadLatestSnapshot(file.FullName);
            }
            catch (IOException) when (readBlocked || SessionDiscovery.IsReadBlocked(file.FullName))
            {
                readBlocked = true;
                needsSnapshotHydration = true;
            }
        }

        var sessionId = identity.SessionId;
        var conversationLabel = _titleIndexes[profile.Id].GetTitle(sessionId);
        var identityProvisional = false;
        var identityMetadataFound = identity.MetadataFound;
        if (!identityMetadataFound && readBlocked)
        {
            sessionId = GetSessionIdFromPath(file.FullName);
            conversationLabel = _titleIndexes[profile.Id].GetTitle(sessionId);
            identityProvisional = !string.IsNullOrWhiteSpace(sessionId) &&
                                  !string.IsNullOrWhiteSpace(conversationLabel);
            identityMetadataFound = identityProvisional;
            needsSnapshotHydration = true;
        }

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
            TerminalStatus = snapshot?.TerminalSilent == true ? string.Empty : snapshot?.TerminalStatus ?? string.Empty,
            TerminalAt = snapshot?.TerminalSilent == true ? DateTimeOffset.MinValue : snapshot?.TerminalTimestamp ?? DateTimeOffset.MinValue,
            TerminalSilent = false,
            IsInternalSession = identity.IsInternalSession,
            IdentityMetadataFound = identityMetadataFound,
            IdentityProvisional = identityProvisional,
            NeedsSnapshotHydration = needsSnapshotHydration,
            IsReadBlocked = readBlocked,
            LastLockObservedAt = readBlocked ? current : DateTimeOffset.MinValue,
            RuntimeActivityAt = DateTimeOffset.MinValue,
            SessionId = sessionId,
            ConversationLabel = conversationLabel,
            ProfileId = profile.Id,
            ProfileLabel = profile.Label,
            ClientSurface = ResolveClientSurface(identity.ClientSurface, profile),
            ModelProvider = ResolveProvider(identity.ModelProvider, profile)
        };
    }

    private bool RefreshIdentity(SessionState state, DateTimeOffset current)
    {
        if (state.IsReadBlocked)
        {
            return false;
        }

        var changed = false;
        if (!state.IdentityMetadataFound || state.IdentityProvisional)
        {
            var identity = SessionIdentityReader.Read(state.Path);
            if (identity.MetadataFound)
            {
                ApplyIdentity(state, identity);
                changed = true;
            }
        }

        if (!state.IsInternalSession && state.NeedsSnapshotHydration)
        {
            try
            {
                ApplyInitialSnapshot(state, BoundedTailReader.ReadLatestSnapshot(state.Path));
                state.NeedsSnapshotHydration = false;
                changed = true;
            }
            catch (IOException)
            {
                HandleReadFailure(state, current);
            }
            catch (UnauthorizedAccessException)
            {
                RecordReadError(state, current);
            }
        }
        return changed;
    }

    private bool ReadAppended(SessionState state, DateTimeOffset now, int maximumBytes)
    {
        try
        {
            var identityChanged = RefreshIdentity(state, now);
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
            HandleReadFailure(state, now);
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
                    state.PendingCompletionAt = item.Timestamp;
                    state.PendingCompletionDueAt = now.AddSeconds(Options.CompletionGraceSeconds);
                    if (Options.CompletionGraceSeconds == 0)
                    {
                        _ = ConfirmPendingCompletion(state, now);
                    }
                }
                return true;
            case HudRecordKind.CompletedSilent:
                // A silent task_complete is merely an internal/empty turn
                // boundary. It must not hide a conversation or trigger a
                // completion animation.
                ClearPendingCompletion(state);
                state.TerminalStatus = string.Empty;
                state.TerminalAt = DateTimeOffset.MinValue;
                state.TerminalSilent = false;
                if (state.TerminalExitStarted || state.TerminalExitCompleted)
                {
                    ResetTerminalExit(state);
                }
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

        var continuationThreshold = state.PendingCompletionAt.AddSeconds(Math.Max(2, Options.CompletionGraceSeconds));
        if (state.PendingCompletionAt != DateTimeOffset.MinValue &&
            state.RuntimeActivityAt > continuationThreshold)
        {
            ClearPendingCompletion(state);
            return true;
        }

        state.TerminalStatus = "completed";
        state.TerminalAt = state.PendingCompletionAt == DateTimeOffset.MinValue ? now : state.PendingCompletionAt;
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
        var profile = _profileById[state.ProfileId];
        state.IdentityMetadataFound = true;
        state.IdentityProvisional = false;
        state.IsInternalSession = identity.IsInternalSession;
        state.SessionId = identity.SessionId;
        state.ConversationLabel = _titleIndexes[state.ProfileId].GetTitle(identity.SessionId);
        state.ClientSurface = ResolveClientSurface(identity.ClientSurface, profile);
        state.ModelProvider = ResolveProvider(identity.ModelProvider, profile);
        if (string.IsNullOrWhiteSpace(state.Workspace) && !string.IsNullOrWhiteSpace(identity.Workspace))
        {
            state.Workspace = identity.Workspace;
        }
    }

    private void ApplyInitialSnapshot(SessionState state, HudSnapshot? snapshot)
    {
        state.Snapshot = snapshot;
        if (snapshot is null)
        {
            return;
        }

        state.Model = snapshot.Model;
        if (!string.IsNullOrWhiteSpace(snapshot.Workspace))
        {
            state.Workspace = snapshot.Workspace;
        }
        state.AllowanceTimestamp = snapshot.AllowanceTimestamp;
        state.WeeklyRemainingPercent = snapshot.WeeklyRemainingPercent;
        state.FiveHourRemainingPercent = snapshot.FiveHourRemainingPercent;
        state.LastUsageAt = snapshot.Timestamp;
        state.TerminalStatus = snapshot.TerminalSilent ? string.Empty : snapshot.TerminalStatus;
        state.TerminalAt = snapshot.TerminalSilent ? DateTimeOffset.MinValue : snapshot.TerminalTimestamp ?? DateTimeOffset.MinValue;
        state.TerminalSilent = false;
        state.HasObservedActivity = true;
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

    private bool IsVisible(SessionState state, DateTimeOffset now)
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

        if (!IsSourceEnabled(state))
        {
            return false;
        }

        if (!string.IsNullOrWhiteSpace(state.TerminalStatus) && state.TerminalAt != DateTimeOffset.MinValue)
        {
            return state.AgentNoticeUntil > now || !state.TerminalExitCompleted;
        }
        return true;
    }

    private IReadOnlyList<ProfileSessionFile> DiscoverActiveFiles(DateTimeOffset current)
    {
        var cutoff = current.UtcDateTime.AddMinutes(-Math.Max(1, Options.ActiveWindowMinutes));
        var runtimeCutoff = current.Subtract(GetRuntimeDiscoveryWindow());
        var maximum = Math.Max(1, Options.MaximumFiles);
        var candidates = new Dictionary<string, ProfileSessionFile>(_pathComparer);
        foreach (var profile in _profiles.Where(IsProfileDiscoveryEnabled))
        {
            foreach (var file in SessionDiscovery.GetActiveFiles(
                    profile.SessionsRoot,
                    Options.ActiveWindowMinutes,
                    maximum,
                    current.UtcDateTime))
            {
                candidates[file.FullName] = new ProfileSessionFile(profile, file, null);
            }

            foreach (var activity in _activitySource.GetRecentUserSessions(
                         profile,
                         runtimeCutoff,
                         maximum))
            {
                if (!TryCreateActivityCandidate(profile, activity, out var activityCandidate))
                {
                    continue;
                }

                if (candidates.TryGetValue(activityCandidate.File.FullName, out var existing))
                {
                    candidates[activityCandidate.File.FullName] = existing with
                    {
                        RuntimeActivityAt = activity.UpdatedAt
                    };
                }
                else
                {
                    candidates[activityCandidate.File.FullName] = activityCandidate;
                }
            }
        }

        var active = candidates.Values
            .Where(candidate => candidate.File.ReadBlocked ||
                                candidate.File.LastWriteTimeUtc >= cutoff ||
                                candidate.RuntimeActivityAt >= runtimeCutoff)
            .OrderByDescending(static candidate => candidate.File.ReadBlocked)
            .ThenByDescending(GetCandidateActivityTime)
            .Take(maximum)
            .ToArray();
        return active;
    }

    private bool IsProfileDiscoveryEnabled(SessionProfile profile) =>
        profile.Id == SessionProfile.DeepSeekId
            ? Options.DeepSeekCliSessionsEnabled
            : Options.DesktopSessionsEnabled || Options.VsCodeSessionsEnabled || Options.DefaultCliSessionsEnabled;

    private bool IsSourceEnabled(SessionState state)
    {
        if (state.ProfileId == SessionProfile.DeepSeekId)
        {
            return Options.DeepSeekCliSessionsEnabled;
        }

        return state.ClientSurface switch
        {
            "desktop" => Options.DesktopSessionsEnabled,
            "vscode" => Options.VsCodeSessionsEnabled,
            "cli" => Options.DefaultCliSessionsEnabled,
            _ => Options.DesktopSessionsEnabled || Options.VsCodeSessionsEnabled || Options.DefaultCliSessionsEnabled
        };
    }

    private static string ResolveClientSurface(string value, SessionProfile profile) =>
        value is "desktop" or "vscode" or "cli" ? value : profile.DefaultClientSurface;

    private static string ResolveProvider(string value, SessionProfile profile) =>
        string.IsNullOrWhiteSpace(value) ? profile.DefaultProvider : value;

    private sealed record ProfileSessionFile(
        SessionProfile Profile,
        SessionFile File,
        DateTimeOffset? RuntimeActivityAt);

    private bool TryCreateActivityCandidate(
        SessionProfile profile,
        SessionActivity activity,
        out ProfileSessionFile candidate)
    {
        candidate = null!;
        try
        {
            var path = Path.GetFullPath(NormalizeWindowsExtendedPath(activity.RolloutPath));
            var root = Path.GetFullPath(profile.SessionsRoot)
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            var comparison = OperatingSystem.IsWindows()
                ? StringComparison.OrdinalIgnoreCase
                : StringComparison.Ordinal;
            if (!path.StartsWith(root, comparison) ||
                !string.Equals(GetSessionIdFromPath(path), activity.SessionId, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            var file = new FileInfo(path);
            if (!file.Exists)
            {
                return false;
            }

            candidate = new ProfileSessionFile(
                profile,
                new SessionFile(file.FullName, file.LastWriteTimeUtc, file.Length, SessionDiscovery.IsReadBlocked(file.FullName)),
                activity.UpdatedAt);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }

    private static DateTimeOffset GetCandidateActivityTime(ProfileSessionFile candidate)
    {
        var fileTime = new DateTimeOffset(candidate.File.LastWriteTimeUtc, TimeSpan.Zero);
        return candidate.RuntimeActivityAt.HasValue && candidate.RuntimeActivityAt.Value > fileTime
            ? candidate.RuntimeActivityAt.Value
            : fileTime;
    }

    private static string NormalizeWindowsExtendedPath(string path)
    {
        if (!OperatingSystem.IsWindows())
        {
            return path;
        }
        if (path.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase))
        {
            return @"\\" + path[8..];
        }
        return path.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase)
            ? path[4..]
            : path;
    }

    private bool UpdateRuntimeActivity(
        SessionState state,
        DateTimeOffset? activityAt,
        DateTimeOffset now)
    {
        if (!activityAt.HasValue || activityAt.Value < now.Subtract(GetRuntimeDiscoveryWindow()))
        {
            return false;
        }

        var changed = false;
        if (activityAt.Value > state.RuntimeActivityAt)
        {
            state.RuntimeActivityAt = activityAt.Value;
            changed = true;
        }

        // A completed token snapshot can be the last thing in the parent JSONL
        // while Codex continues the task through a guardian/background worker.
        // A newer top-level runtime heartbeat is authoritative for liveness,
        // but it never changes token totals or fabricates a completion event.
        if (!string.IsNullOrWhiteSpace(state.TerminalStatus) &&
            state.TerminalAt != DateTimeOffset.MinValue &&
            state.RuntimeActivityAt > state.TerminalAt.AddSeconds(Math.Max(2, Options.CompletionGraceSeconds)))
        {
            state.TerminalStatus = string.Empty;
            state.TerminalAt = DateTimeOffset.MinValue;
            state.TerminalSilent = false;
            ClearPendingCompletion(state);
            ResetTerminalExit(state);
            if (state.AttentionReason is "completed" or "failed")
            {
                state.AttentionReason = string.Empty;
                state.AttentionUntil = DateTimeOffset.MinValue;
            }
            changed = true;
        }
        return changed;
    }

    private TimeSpan GetRuntimeDiscoveryWindow() =>
        TimeSpan.FromMinutes(Math.Max(RuntimeHeartbeatFreshness.TotalMinutes, Options.ActiveWindowMinutes));

    private static bool HasFreshRuntimeActivity(SessionState state, DateTimeOffset now) =>
        state.RuntimeActivityAt != DateTimeOffset.MinValue &&
        now - state.RuntimeActivityAt <= RuntimeHeartbeatFreshness;

    private static string GetSessionIdFromPath(string path)
    {
        var match = RolloutSessionIdPattern.Match(Path.GetFileName(path));
        return match.Success ? match.Groups["id"].Value : string.Empty;
    }

    private static bool UpdateReadBlockState(SessionState state, bool readBlocked, DateTimeOffset now)
    {
        var changed = state.IsReadBlocked != readBlocked;
        state.IsReadBlocked = readBlocked;
        if (readBlocked)
        {
            state.LastLockObservedAt = now;
            state.LastReadErrorAt = DateTimeOffset.MinValue;
        }
        return changed;
    }

    private void HandleReadFailure(SessionState state, DateTimeOffset now)
    {
        if (SessionDiscovery.IsReadBlocked(state.Path))
        {
            _ = UpdateReadBlockState(state, true, now);
            return;
        }
        RecordReadError(state, now);
    }

    private void RecordReadError(SessionState state, DateTimeOffset now)
    {
        state.LastReadErrorAt = now;
        LastReadErrorAt = now;
    }

    private static void ClearPendingCompletion(SessionState state)
    {
        state.PendingCompletionTurnId = string.Empty;
        state.PendingCompletionAt = DateTimeOffset.MinValue;
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
