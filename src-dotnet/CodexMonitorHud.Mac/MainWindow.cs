using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using CodexMonitorHud.Core.Models;
using CodexMonitorHud.Core.Presentation;

namespace CodexMonitorHud.Mac;

public sealed class MainWindow : Window
{
    private readonly Border _root = new();
    private bool _positionApplied;
    private bool _applyingPosition;
    private string _positionSignature = string.Empty;
    private readonly DispatcherTimer _positionSaveTimer;

    internal event Action? SettingsRequested;
    internal event Action? ExitRequested;
    internal event Action<string>? ModeRequested;
    internal event Action<string>? OpenTaskRequested;
    internal event Action<string>? DismissTaskRequested;
    internal event Action? QuietWakeRequested;
    internal event Action<double, double>? PositionPersistRequested;

    public MainWindow()
    {
        Title = "Codex Monitor HUD";
        Width = 440;
        Height = 240;
        MinWidth = 320;
        MinHeight = 110;
        WindowDecorations = Avalonia.Controls.WindowDecorations.None;
        TransparencyLevelHint = new[] { WindowTransparencyLevel.Transparent };
        Background = Brushes.Transparent;
        CanResize = true;
        ShowInTaskbar = true;
        Content = _root;
        _positionSaveTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(300) };
        _positionSaveTimer.Tick += (_, _) =>
        {
            _positionSaveTimer.Stop();
            if (!_applyingPosition) PositionPersistRequested?.Invoke(Position.X, Position.Y);
        };
        _root.PointerEntered += (_, _) => QuietWakeRequested?.Invoke();
        PositionChanged += (_, _) =>
        {
            if (!_positionApplied || _applyingPosition) return;
            _positionSaveTimer.Stop();
            _positionSaveTimer.Start();
        };
    }

    internal void Update(MacRenderModel model)
    {
        Topmost = model.Settings.AlwaysOnTop;
        MacWindowInterop.SetMousePassthrough(this, model.Settings.MousePassthrough);
        Opacity = model.Settings.Opacity;
        Width = Math.Max(320, 440 * model.Settings.Scale);
        _root.Background = MacVisuals.Brush(model.Settings.Background, "#EE111827");
        _root.BorderBrush = MacVisuals.Brush(model.Settings.Border, "#33FFFFFF");
        _root.BorderThickness = new Thickness(model.Settings.ThemeStyle.BorderWidth);
        _root.CornerRadius = new CornerRadius(model.Settings.CornerRadius);
        _root.Padding = new Thickness(model.Quiet ? 10 : 16);
        _root.Child = model.Quiet ? BuildQuiet(model) : BuildExpanded(model);
        ApplyPosition(model.Settings);
    }

    private Control BuildExpanded(MacRenderModel model)
    {
        var panel = new StackPanel { Spacing = 10 };
        panel.Children.Add(BuildHeader(model));
        if (model.Summary is null)
        {
            panel.Children.Add(new TextBlock
            {
                Text = model.InitialScanComplete
                    ? MacVisuals.Text(model.Locale, "noActiveTasks")
                    : MacVisuals.Text(model.Locale, "waiting"),
                FontSize = model.Settings.FontSize,
                Foreground = MacVisuals.Brush(model.Settings.Muted),
                Margin = new Thickness(4, 10)
            });
        }
        else
        {
            var metrics = HudFormatting.GetMetrics(model.Summary, model.Settings.Fields, model.Locale, model.Settings.NumberFormat);
            var wrap = new WrapPanel { Orientation = Orientation.Horizontal };
            foreach (var metric in metrics)
            {
                wrap.Children.Add(MetricChip(metric, model));
            }
            panel.Children.Add(wrap);
        }

        if (model.Settings.MultiTask.DisplayMode == "list")
        {
            var rows = new StackPanel { Spacing = model.Settings.MultiTask.ListDensity == "compact" ? 4 : 8 };
            foreach (var task in model.Tasks)
            {
                rows.Children.Add(TaskRow(task, model));
            }
            panel.Children.Add(new ScrollViewer
            {
                MaxHeight = 540,
                VerticalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Auto,
                Content = rows
            });
        }
        return panel;
    }

    private Control BuildHeader(MacRenderModel model)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto,Auto") };
        var dot = new Border
        {
            IsVisible = model.Settings.ShowStatusDot,
            Width = model.Settings.ThemeStyle.StatusDotSize + 2,
            Height = model.Settings.ThemeStyle.StatusDotSize + 2,
            CornerRadius = new CornerRadius(99),
            Background = MacVisuals.StatusBrush(model.Settings, model.OverallStatus),
            VerticalAlignment = VerticalAlignment.Center
        };
        var title = new TextBlock
        {
            Text = MacVisuals.Text(model.Locale, "appName"),
            FontSize = model.Settings.FontSize + 1,
            FontWeight = FontWeight.SemiBold,
            Foreground = MacVisuals.Brush(model.Settings.Foreground),
            Margin = new Thickness(9, 0, 8, 0),
            VerticalAlignment = VerticalAlignment.Center
        };
        var mode = new Button
        {
            Content = $"{model.Tasks.Count} ▾",
            Padding = new Thickness(8, 3),
            Background = Brushes.Transparent,
            Foreground = MacVisuals.Brush(model.Settings.Muted)
        };
        mode.Click += (_, _) => ModeRequested?.Invoke(model.Settings.MultiTask.DisplayMode == "list" ? "summary" : "list");
        mode.ContextMenu = BuildModeMenu(model);
        var settings = new Button
        {
            Content = "⚙",
            Padding = new Thickness(7, 3),
            Background = Brushes.Transparent,
            Foreground = MacVisuals.Brush(model.Settings.Muted)
        };
        settings.Click += (_, _) => SettingsRequested?.Invoke();
        Grid.SetColumn(title, 1);
        Grid.SetColumn(mode, 2);
        Grid.SetColumn(settings, 3);
        grid.Children.Add(dot);
        grid.Children.Add(title);
        grid.Children.Add(mode);
        grid.Children.Add(settings);
        return grid;
    }

    private ContextMenu BuildModeMenu(MacRenderModel model)
    {
        var menu = new ContextMenu();
        foreach (var (mode, key) in new[]
        {
            ("summary", "showSummary"),
            ("list", "showTaskList"),
            ("split", "splitAll")
        })
        {
            var item = new MenuItem { Header = MacVisuals.Text(model.Locale, key) };
            item.Click += (_, _) => ModeRequested?.Invoke(mode);
            menu.Items.Add(item);
        }
        var exit = new MenuItem { Header = MacVisuals.Text(model.Locale, "exit") };
        exit.Click += (_, _) => ExitRequested?.Invoke();
        menu.Items.Add(new Separator());
        menu.Items.Add(exit);
        return menu;
    }

    private Control TaskRow(MacTaskModel task, MacRenderModel model)
    {
        var border = new Border
        {
            Background = MacVisuals.Brush(task.ContextAlertLevel >= 3 ? "#33FF453A" : "#12FFFFFF"),
            BorderBrush = MacVisuals.Brush(model.Settings.Border),
            BorderThickness = new Thickness(0, 0, 0, 1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(9, 7)
        };
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto") };
        var number = new Border
        {
            Width = 31,
            Height = 24,
            CornerRadius = new CornerRadius(12),
            Background = MacVisuals.StatusBrush(model.Settings, task.Status),
            Child = new TextBlock
            {
                Text = task.Number.ToString(),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                FontWeight = FontWeight.Bold,
                Foreground = Brushes.White
            }
        };
        var identity = new StackPanel { Spacing = 2, Margin = new Thickness(9, 0) };
        identity.Children.Add(new TextBlock
        {
            Text = task.Workspace,
            FontWeight = FontWeight.SemiBold,
            Foreground = MacVisuals.Brush(model.Settings.Foreground),
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        var subtitle = model.Settings.MultiTask.NameMode == "hidden"
            ? task.Status
            : string.IsNullOrWhiteSpace(task.Conversation) ? task.Status : $"{task.Conversation} · {task.Status}";
        identity.Children.Add(new TextBlock
        {
            Text = subtitle,
            FontSize = Math.Max(10, model.Settings.FontSize - 3),
            Foreground = MacVisuals.Brush(model.Settings.Muted),
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        var details = new TextBlock
        {
            Text = TaskDetail(task, model),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = MacVisuals.Brush(model.Settings.Muted),
            FontSize = Math.Max(10, model.Settings.FontSize - 2)
        };
        Grid.SetColumn(identity, 1);
        Grid.SetColumn(details, 2);
        grid.Children.Add(number);
        grid.Children.Add(identity);
        grid.Children.Add(details);
        border.Child = grid;
        border.PointerPressed += (_, args) =>
        {
            if (args.ClickCount == 2) OpenTaskRequested?.Invoke(task.Path);
        };
        var menu = new ContextMenu();
        var open = new MenuItem { Header = MacVisuals.Text(model.Locale, "openTaskTooltip") };
        open.Click += (_, _) => OpenTaskRequested?.Invoke(task.Path);
        var dismiss = new MenuItem { Header = MacVisuals.Text(model.Locale, "dismissTask") };
        dismiss.Click += (_, _) => DismissTaskRequested?.Invoke(task.Path);
        menu.Items.Add(open);
        menu.Items.Add(dismiss);
        border.ContextMenu = menu;
        return border;
    }

    private static string TaskDetail(MacTaskModel task, MacRenderModel model)
    {
        if (task.Snapshot is null) return "…";
        var snapshot = task.Snapshot;
        return model.Settings.MultiTask.ListDetail switch
        {
            "compact" => $"{snapshot.ContextPercent:0.#}%",
            "detailed" => $"{HudFormatting.FormatNumber(snapshot.CallTotal, model.Settings.NumberFormat)} · {snapshot.Model}",
            _ => $"{HudFormatting.FormatNumber(snapshot.Input, model.Settings.NumberFormat)} in · {HudFormatting.FormatNumber(snapshot.Output, model.Settings.NumberFormat)} out"
        };
    }

    private Control BuildQuiet(MacRenderModel model)
    {
        var horizontal = model.Settings.Behavior.IdleIndicator.Layout != "vertical";
        var panel = new StackPanel
        {
            Orientation = horizontal ? Orientation.Horizontal : Orientation.Vertical,
            Spacing = 7
        };
        panel.Children.Add(new Border
        {
            Width = 24,
            Height = 24,
            CornerRadius = new CornerRadius(99),
            BorderBrush = MacVisuals.Brush(model.Settings.Foreground),
            BorderThickness = new Thickness(1),
            Background = MacVisuals.StatusBrush(model.Settings, model.OverallStatus)
        });
        if (model.Settings.Behavior.IdleIndicator.Layout != "overall")
        {
            foreach (var task in model.Tasks.Take(12))
            {
                var isBar = model.Settings.Behavior.IdleIndicator.TaskStyle == "bar";
                panel.Children.Add(new Border
                {
                    Width = isBar ? 18 : 22,
                    Height = isBar ? 30 : 22,
                    CornerRadius = new CornerRadius(isBar ? 6 : 99),
                    Background = MacVisuals.StatusBrush(model.Settings, task.Status),
                    Child = new TextBlock
                    {
                        Text = task.Number.ToString(),
                        HorizontalAlignment = HorizontalAlignment.Center,
                        VerticalAlignment = VerticalAlignment.Center,
                        FontSize = 9,
                        FontWeight = FontWeight.Bold,
                        Foreground = Brushes.White
                    }
                });
            }
            if (model.Tasks.Count > 12)
            {
                panel.Children.Add(new TextBlock
                {
                    Text = $"+{model.Tasks.Count - 12}",
                    Foreground = MacVisuals.Brush(model.Settings.Muted),
                    VerticalAlignment = VerticalAlignment.Center
                });
            }
        }
        return panel;
    }

    private static Control MetricChip(HudMetric metric, MacRenderModel model) => new Border
    {
        Margin = new Thickness(0, 0, 7, 7),
        Padding = new Thickness(9, 6),
        CornerRadius = new CornerRadius(9),
        Background = MacVisuals.Brush("#14FFFFFF"),
        Child = new StackPanel
        {
            Spacing = 1,
            Children =
            {
                new TextBlock { Text = metric.Label, FontSize = 10, Foreground = MacVisuals.Brush(model.Settings.Muted) },
                new TextBlock { Text = metric.Value, FontWeight = FontWeight.SemiBold, Foreground = MacVisuals.Brush(model.Settings.Foreground) }
            }
        }
    };

    private void ApplyPosition(CodexMonitorHud.Core.Configuration.HudSettings settings)
    {
        if (Screens.Primary is null) return;
        var signature = $"{settings.Position}|{settings.CustomLeft}|{settings.CustomTop}";
        if (_positionApplied && signature == _positionSignature) return;
        _positionSignature = signature;
        _positionApplied = true;
        var area = Screens.Primary.WorkingArea;
        var width = (int)Width;
        var height = (int)Height;
        var x = settings.Position switch
        {
            "top-left" or "bottom-left" => area.X + 20,
            "top-center" or "bottom-center" => area.X + (area.Width - width) / 2,
            "custom" when settings.CustomLeft.HasValue => (int)settings.CustomLeft.Value,
            _ => area.Right - width - 20
        };
        var y = settings.Position switch
        {
            "bottom-left" or "bottom-center" or "bottom-right" => area.Bottom - height - 20,
            "custom" when settings.CustomTop.HasValue => (int)settings.CustomTop.Value,
            _ => area.Y + 20
        };
        _applyingPosition = true;
        Position = new PixelPoint(x, y);
        DispatcherTimer.RunOnce(() => _applyingPosition = false, TimeSpan.FromMilliseconds(50));
    }
}
