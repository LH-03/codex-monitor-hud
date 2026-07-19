using CodexMonitorHud.Core.Configuration;
using CodexMonitorHud.Core.Models;

namespace CodexMonitorHud.Mac;

internal sealed record MacTaskModel(
    string Path,
    int Number,
    string Workspace,
    string Conversation,
    string Status,
    HudSnapshot? Snapshot,
    string Notice,
    int ContextAlertLevel);

internal sealed record MacRenderModel(
    HudSettings Settings,
    IReadOnlyDictionary<string, string> Locale,
    string OverallStatus,
    HudSnapshot? Summary,
    IReadOnlyList<MacTaskModel> Tasks,
    bool Paused,
    bool Quiet,
    bool InitialScanComplete);
