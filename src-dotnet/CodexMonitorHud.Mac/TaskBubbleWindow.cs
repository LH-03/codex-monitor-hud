using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using CodexMonitorHud.Core.Presentation;

namespace CodexMonitorHud.Mac;

internal sealed class TaskBubbleWindow : Window
{
    private readonly Border _root = new();
    private string _path = string.Empty;

    public event Action<string>? OpenRequested;
    public event Action<string>? DismissRequested;

    public TaskBubbleWindow()
    {
        Width = 360;
        Height = 210;
        MinWidth = 280;
        MinHeight = 150;
        WindowDecorations = Avalonia.Controls.WindowDecorations.None;
        TransparencyLevelHint = new[] { WindowTransparencyLevel.Transparent };
        Background = Brushes.Transparent;
        CanResize = true;
        ShowInTaskbar = false;
        Content = _root;
        _root.PointerPressed += OnPointerPressed;
    }

    public void Update(MacTaskModel task, MacRenderModel model)
    {
        _path = task.Path;
        Topmost = model.Settings.AlwaysOnTop;
        MacWindowInterop.SetMousePassthrough(this, model.Settings.MousePassthrough);
        Opacity = model.Settings.Opacity;
        _root.Background = MacVisuals.Brush(model.Settings.Background, "#EE111827");
        _root.BorderBrush = MacVisuals.Brush(model.Settings.Border, "#33FFFFFF");
        _root.BorderThickness = new Thickness(model.Settings.ThemeStyle.BorderWidth);
        _root.CornerRadius = new CornerRadius(model.Settings.CornerRadius);
        _root.Padding = new Thickness(16);

        var panel = new StackPanel { Spacing = 10 };
        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto") };
        var dot = new Border
        {
            IsVisible = model.Settings.ShowStatusDot,
            Width = model.Settings.ThemeStyle.StatusDotSize,
            Height = model.Settings.ThemeStyle.StatusDotSize,
            CornerRadius = new CornerRadius(99),
            Background = MacVisuals.StatusBrush(model.Settings, task.Status),
            VerticalAlignment = VerticalAlignment.Center
        };
        var title = new TextBlock
        {
            Text = $"#{task.Number}  {task.Workspace}",
            FontSize = model.Settings.FontSize,
            FontWeight = FontWeight.SemiBold,
            Foreground = MacVisuals.Brush(model.Settings.Foreground),
            TextTrimming = TextTrimming.CharacterEllipsis,
            Margin = new Thickness(8, 0, 8, 0)
        };
        var dismiss = new Button
        {
            Content = "×",
            Padding = new Thickness(7, 1),
            Background = Brushes.Transparent,
            Foreground = MacVisuals.Brush(model.Settings.Muted)
        };
        dismiss.Click += (_, _) => DismissRequested?.Invoke(_path);
        Grid.SetColumn(title, 1);
        Grid.SetColumn(dismiss, 2);
        header.Children.Add(dot);
        header.Children.Add(title);
        header.Children.Add(dismiss);
        panel.Children.Add(header);

        if (!string.IsNullOrWhiteSpace(task.Conversation))
        {
            panel.Children.Add(new TextBlock
            {
                Text = task.Conversation,
                Foreground = MacVisuals.Brush(model.Settings.Muted),
                FontSize = Math.Max(11, model.Settings.FontSize - 2),
                TextTrimming = TextTrimming.CharacterEllipsis
            });
        }
        if (task.Snapshot is null)
        {
            panel.Children.Add(new TextBlock
            {
                Text = MacVisuals.Text(model.Locale, "waiting"),
                Foreground = MacVisuals.Brush(model.Settings.Muted)
            });
        }
        else
        {
            var metrics = HudFormatting.GetMetrics(task.Snapshot, BubbleFields(model), model.Locale, model.Settings.NumberFormat);
            var wrap = new WrapPanel { Orientation = Orientation.Horizontal };
            foreach (var metric in metrics)
            {
                wrap.Children.Add(MetricChip(metric.Label, metric.Value, model));
            }
            panel.Children.Add(wrap);
        }
        if (!string.IsNullOrWhiteSpace(task.Notice))
        {
            panel.Children.Add(new Border
            {
                Background = MacVisuals.Brush("#227C3AED"),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(8, 5),
                Child = new TextBlock
                {
                    Text = task.Notice,
                    TextWrapping = TextWrapping.Wrap,
                    Foreground = MacVisuals.Brush(model.Settings.Foreground)
                }
            });
        }
        _root.Child = panel;
    }

    private static IReadOnlyDictionary<string, bool> BubbleFields(MacRenderModel model)
    {
        var settings = model.Settings.MultiTask.BubbleFields;
        return new Dictionary<string, bool>(model.Settings.Fields, StringComparer.Ordinal)
        {
            ["model"] = settings.Model,
            ["callTotal"] = settings.CallTotal,
            ["taskTotal"] = settings.TaskTotal,
            ["estimatedCost"] = settings.EstimatedCost,
            ["updated"] = settings.Updated,
            ["weeklyRemaining"] = false,
            ["activeTasks"] = false
        };
    }

    private static Control MetricChip(string label, string value, MacRenderModel model) => new Border
    {
        Margin = new Thickness(0, 0, 7, 7),
        Padding = new Thickness(8, 5),
        CornerRadius = new CornerRadius(8),
        Background = MacVisuals.Brush("#14FFFFFF"),
        Child = new StackPanel
        {
            Spacing = 1,
            Children =
            {
                new TextBlock { Text = label, FontSize = 10, Foreground = MacVisuals.Brush(model.Settings.Muted) },
                new TextBlock { Text = value, FontWeight = FontWeight.SemiBold, Foreground = MacVisuals.Brush(model.Settings.Foreground) }
            }
        }
    };

    private void OnPointerPressed(object? sender, PointerPressedEventArgs args)
    {
        if (args.ClickCount == 2)
        {
            OpenRequested?.Invoke(_path);
        }
    }
}
