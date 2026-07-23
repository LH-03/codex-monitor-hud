namespace CodexMonitorHud.Core.State;

public sealed record AgentAnimationRecipe(
    IReadOnlyList<string> Layers,
    string Color,
    double Intensity,
    int TempoMilliseconds,
    int Cycles,
    double GlowRadius,
    double Scale,
    string Direction);
