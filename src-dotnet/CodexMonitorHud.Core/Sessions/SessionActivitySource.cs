namespace CodexMonitorHud.Core.Sessions;

public sealed record SessionActivity(
    string SessionId,
    string RolloutPath,
    DateTimeOffset UpdatedAt);

public interface ISessionActivitySource
{
    IReadOnlyList<SessionActivity> GetRecentUserSessions(
        SessionProfile profile,
        DateTimeOffset cutoff,
        int maximumRows);
}

public sealed class EmptySessionActivitySource : ISessionActivitySource
{
    public static EmptySessionActivitySource Instance { get; } = new();

    private EmptySessionActivitySource()
    {
    }

    public IReadOnlyList<SessionActivity> GetRecentUserSessions(
        SessionProfile profile,
        DateTimeOffset cutoff,
        int maximumRows) => Array.Empty<SessionActivity>();
}
