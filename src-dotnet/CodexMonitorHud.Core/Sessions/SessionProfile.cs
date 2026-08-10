using CodexMonitorHud.Core.Models;

namespace CodexMonitorHud.Core.Sessions;

public sealed record SessionProfile(
    string Id,
    string Label,
    string SessionsRoot,
    string SessionIndexPath,
    string DefaultClientSurface,
    string DefaultProvider,
    string StateDatabasePath = "")
{
    public const string DefaultId = "codex";
    public const string DeepSeekId = "deepseek";

    public static IReadOnlyList<SessionProfile> CreateDefaultSet(HudPaths paths)
    {
        var defaultProfileRoot = Path.GetDirectoryName(paths.SessionsRoot)
            ?? throw new InvalidOperationException("The default Codex profile root could not be resolved.");
        var home = Path.GetDirectoryName(defaultProfileRoot)
            ?? throw new InvalidOperationException("The user profile root could not be resolved.");
        var deepSeekProfileRoot = Path.Combine(home, ".codex-deepseek");
        return new[]
        {
            new SessionProfile(
                DefaultId,
                "Codex",
                paths.SessionsRoot,
                Path.Combine(defaultProfileRoot, "session_index.jsonl"),
                "unknown",
                string.Empty,
                Path.Combine(defaultProfileRoot, "state_5.sqlite")),
            new SessionProfile(
                DeepSeekId,
                "DeepSeek",
                Path.Combine(deepSeekProfileRoot, "sessions"),
                Path.Combine(deepSeekProfileRoot, "session_index.jsonl"),
                "cli",
                "deepseek",
                Path.Combine(deepSeekProfileRoot, "state_5.sqlite"))
        };
    }
}
