using System.Drawing;
using System.Windows;
using System.Windows.Controls;
using Forms = System.Windows.Forms;

namespace CodexMonitorHud.App;

internal sealed class HudCommandSurfaces : IDisposable
{
    private readonly MenuItem _status = new() { IsEnabled = false };
    private readonly MenuItem _settings = new();
    private readonly MenuItem _passthrough = new();
    private readonly MenuItem _pause = new();
    private readonly MenuItem _position = new();
    private readonly MenuItem _viewMode = new();
    private readonly MenuItem _summary = new() { IsCheckable = true };
    private readonly MenuItem _list = new() { IsCheckable = true };
    private readonly MenuItem _split = new() { IsCheckable = true };
    private readonly MenuItem _mergeAll = new();
    private readonly MenuItem _exit = new();
    private readonly Forms.NotifyIcon _tray = new();
    private readonly Forms.ToolStripMenuItem _trayStatus = new() { Enabled = false };
    private readonly Forms.ToolStripMenuItem _traySettings = new();
    private readonly Forms.ToolStripMenuItem _trayViewMode = new();
    private readonly Forms.ToolStripMenuItem _traySummary = new();
    private readonly Forms.ToolStripMenuItem _trayList = new();
    private readonly Forms.ToolStripMenuItem _traySplit = new();
    private readonly Forms.ToolStripMenuItem _trayMergeAll = new();
    private readonly Forms.ToolStripMenuItem _trayPassthrough = new();
    private readonly Forms.ToolStripMenuItem _trayExit = new();

    public HudCommandSurfaces(Window window, string iconPath)
    {
        _viewMode.Items.Add(_summary);
        _viewMode.Items.Add(_list);
        _viewMode.Items.Add(_split);
        _viewMode.Items.Add(new Separator());
        _viewMode.Items.Add(_mergeAll);
        var menu = new ContextMenu();
        menu.Items.Add(_status);
        menu.Items.Add(new Separator());
        menu.Items.Add(_settings);
        menu.Items.Add(_passthrough);
        menu.Items.Add(_pause);
        menu.Items.Add(_position);
        menu.Items.Add(_viewMode);
        menu.Items.Add(new Separator());
        menu.Items.Add(_exit);
        window.ContextMenu = menu;

        var trayMenu = new Forms.ContextMenuStrip();
        _trayViewMode.DropDownItems.Add(_traySummary);
        _trayViewMode.DropDownItems.Add(_trayList);
        _trayViewMode.DropDownItems.Add(_traySplit);
        _trayViewMode.DropDownItems.Add(new Forms.ToolStripSeparator());
        _trayViewMode.DropDownItems.Add(_trayMergeAll);
        trayMenu.Items.Add(_trayStatus);
        trayMenu.Items.Add(new Forms.ToolStripSeparator());
        trayMenu.Items.Add(_traySettings);
        trayMenu.Items.Add(_trayViewMode);
        trayMenu.Items.Add(_trayPassthrough);
        trayMenu.Items.Add(new Forms.ToolStripSeparator());
        trayMenu.Items.Add(_trayExit);
        _tray.ContextMenuStrip = trayMenu;
        if (File.Exists(iconPath))
        {
            using var source = new Icon(iconPath);
            _tray.Icon = (Icon)source.Clone();
        }
        else
        {
            _tray.Icon = SystemIcons.Application;
        }
        _tray.Visible = true;

        _settings.Click += (_, _) => SettingsRequested?.Invoke();
        _passthrough.Click += (_, _) => PassthroughToggleRequested?.Invoke();
        _pause.Click += (_, _) => PauseToggleRequested?.Invoke();
        _position.Click += (_, _) => ResetPositionRequested?.Invoke();
        _summary.Click += (_, _) => ModeRequested?.Invoke("summary");
        _list.Click += (_, _) => ModeRequested?.Invoke("list");
        _split.Click += (_, _) => ModeRequested?.Invoke("split");
        _mergeAll.Click += (_, _) => ModeRequested?.Invoke("summary");
        _exit.Click += (_, _) => ExitRequested?.Invoke();
        _traySettings.Click += (_, _) => Dispatch(window, () => SettingsRequested?.Invoke());
        _traySummary.Click += (_, _) => Dispatch(window, () => ModeRequested?.Invoke("summary"));
        _trayList.Click += (_, _) => Dispatch(window, () => ModeRequested?.Invoke("list"));
        _traySplit.Click += (_, _) => Dispatch(window, () => ModeRequested?.Invoke("split"));
        _trayMergeAll.Click += (_, _) => Dispatch(window, () => ModeRequested?.Invoke("summary"));
        _trayPassthrough.Click += (_, _) => Dispatch(window, () => PassthroughToggleRequested?.Invoke());
        _trayExit.Click += (_, _) => Dispatch(window, () => ExitRequested?.Invoke());
        _tray.DoubleClick += (_, _) => Dispatch(window, () => SettingsRequested?.Invoke());
    }

    public event Action? SettingsRequested;
    public event Action? PassthroughToggleRequested;
    public event Action? PauseToggleRequested;
    public event Action? ResetPositionRequested;
    public event Action<string>? ModeRequested;
    public event Action? ExitRequested;

    public void Update(
        IReadOnlyDictionary<string, string> zh,
        IReadOnlyDictionary<string, string> en,
        string status,
        string displayMode,
        bool paused,
        bool mousePassthrough)
    {
        var bilingualStatus = $"{Get(zh, StatusKey(status))} ({Get(en, StatusKey(status))})";
        _status.Header = $"{Get(zh, "statusLabel")} / {Get(en, "statusLabel")}: {bilingualStatus}";
        _settings.Header = Bi(zh, en, "openSettings");
        _passthrough.Header = Bi(zh, en, mousePassthrough ? "disableMousePassthrough" : "enableMousePassthrough");
        _pause.Header = Bi(zh, en, paused ? "resume" : "pause");
        _position.Header = Bi(zh, en, "resetPosition");
        _viewMode.Header = Bi(zh, en, "displayMode");
        _summary.Header = Bi(zh, en, "showSummary");
        _list.Header = Bi(zh, en, "showTaskList");
        _split.Header = Bi(zh, en, "splitAll");
        _mergeAll.Header = Bi(zh, en, "mergeAll");
        _exit.Header = $"{Get(zh, "exit")} HUD / {Get(en, "exit")} HUD";
        _summary.IsChecked = displayMode == "summary";
        _list.IsChecked = displayMode == "list";
        _split.IsChecked = displayMode == "split";

        _trayStatus.Text = $"{Get(zh, "statusLabel")} / {Get(en, "statusLabel")}: {bilingualStatus}";
        _traySettings.Text = Bi(zh, en, "openSettings");
        _trayViewMode.Text = Bi(zh, en, "displayMode");
        _traySummary.Text = Bi(zh, en, "showSummary");
        _trayList.Text = Bi(zh, en, "showTaskList");
        _traySplit.Text = Bi(zh, en, "splitAll");
        _trayMergeAll.Text = Bi(zh, en, "mergeAll");
        _trayPassthrough.Text = Bi(zh, en, "disableMousePassthrough");
        _trayPassthrough.Enabled = mousePassthrough;
        _trayExit.Text = $"{Get(zh, "exit")} HUD / {Get(en, "exit")} HUD";
        _traySummary.Checked = displayMode == "summary";
        _trayList.Checked = displayMode == "list";
        _traySplit.Checked = displayMode == "split";
        _tray.Text = mousePassthrough ? "Codex Monitor HUD - click-through ON" : "Codex Monitor HUD - monitoring";
    }

    public void Dispose()
    {
        _tray.Visible = false;
        _tray.Dispose();
    }

    private static void Dispatch(Window window, Action action) => _ = window.Dispatcher.BeginInvoke(action);
    private static string Bi(IReadOnlyDictionary<string, string> zh, IReadOnlyDictionary<string, string> en, string key) => $"{Get(zh, key)} / {Get(en, key)}";
    private static string Get(IReadOnlyDictionary<string, string> locale, string key) => locale.TryGetValue(key, out var value) ? value : key;
    private static string StatusKey(string status) => status switch
    {
        "active" => "statusActive",
        "listening" => "statusListening",
        "paused" => "statusPaused",
        "error" => "statusError",
        "completed" => "statusCompleted",
        "aborted" => "statusAborted",
        _ => "statusIdle"
    };
}
