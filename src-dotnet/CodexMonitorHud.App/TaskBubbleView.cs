using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
using CodexMonitorHud.Core.Configuration;
using CodexMonitorHud.Core.Presentation;
using CodexMonitorHud.Core.Sessions;
using CodexMonitorHud.Core.State;
using Path = System.Windows.Shapes.Path;

namespace CodexMonitorHud.App;

internal sealed class TaskBubbleView : IDisposable
{
    private readonly BrushFactory _brushes;
    private readonly SessionState _state;
    private readonly Border _shell;
    private readonly Ellipse _dot;
    private readonly Button _dismiss;
    private readonly Button _merge;
    private readonly TextBlock _number;
    private readonly Border _sourceBadge;
    private readonly Path _sourceIcon;
    private readonly TextBlock _name;
    private readonly Border _contextMetric;
    private readonly TextBlock _contextText;
    private readonly TextBlock _metrics;
    private readonly StackPanel _content;
    private readonly Thumb _resize;
    private nint _handle;
    private int _baseStyle;
    private bool _mousePassthrough;
    private bool _closing;
    private string _appearanceSignature = string.Empty;
    private string _contentSignature = string.Empty;
    private bool _surfaceVisualActive;
    private bool _contextVisualActive;
    private Brush? _baseBorderBrush;
    private Thickness _baseBorderThickness;

    public TaskBubbleView(string xamlPath, SessionState state, BrushFactory brushes)
    {
        _brushes = brushes;
        _state = state;
        StatePath = state.Path;
        TaskNumber = state.Number;
        Window = XamlLoader.LoadWindow(xamlPath);
        _shell = XamlLoader.Require<Border>(Window, "TaskBubbleShell");
        _dot = XamlLoader.Require<Ellipse>(Window, "TaskBubbleStatusDot");
        _dismiss = XamlLoader.Require<Button>(Window, "TaskBubbleDismissButton");
        _merge = XamlLoader.Require<Button>(Window, "TaskBubbleMergeButton");
        _number = XamlLoader.Require<TextBlock>(Window, "TaskBubbleNumber");
        _sourceBadge = XamlLoader.Require<Border>(Window, "TaskBubbleSourceBadge");
        _sourceIcon = XamlLoader.Require<Path>(Window, "TaskBubbleSourceIcon");
        _name = XamlLoader.Require<TextBlock>(Window, "TaskBubbleName");
        _contextMetric = XamlLoader.Require<Border>(Window, "TaskBubbleContextMetric");
        _contextText = XamlLoader.Require<TextBlock>(Window, "TaskBubbleContextText");
        _metrics = XamlLoader.Require<TextBlock>(Window, "TaskBubbleMetrics");
        _content = XamlLoader.Require<StackPanel>(Window, "TaskBubbleContent");
        _resize = XamlLoader.Require<Thumb>(Window, "TaskBubbleResizeThumb");
        if (state.BubbleWidth > 0 && state.BubbleHeight > 0)
        {
            Window.SizeToContent = SizeToContent.Manual;
            Window.Width = state.BubbleWidth;
            Window.Height = state.BubbleHeight;
        }
        _dismiss.Click += (_, _) => DismissRequested?.Invoke(StatePath);
        _merge.Click += (_, _) => MergeRequested?.Invoke(StatePath);
        _shell.MouseLeftButtonDown += OnShellMouseLeftButtonDown;
        _resize.DragDelta += OnResize;
        Window.SourceInitialized += (_, _) =>
        {
            _handle = new WindowInteropHelper(Window).Handle;
            _baseStyle = _handle == 0 ? 0 : NativeMethods.GetWindowLong(_handle, NativeMethods.GwlExStyle);
            SetMousePassthrough(_mousePassthrough);
        };
        Window.Closing += (_, args) =>
        {
            if (!_closing)
            {
                args.Cancel = true;
                Window.Hide();
                MergeRequested?.Invoke(StatePath);
            }
        };
    }

    public Window Window { get; }
    public string StatePath { get; }
    public int TaskNumber { get; }
    public int LastAttentionRevision { get; set; }
    public int LastExitRevision { get; set; }
    public bool IsIndicatorCollapsed { get; private set; }
    public bool IsMouseOver => Window.IsMouseOver;
    public event Action<string>? DismissRequested;
    public event Action<string>? MergeRequested;
    public event Action<string>? OpenRequested;
    public event Action<string, string>? AttentionPresented;

    public void Render(
        SessionState state,
        HudSettings settings,
        IReadOnlyDictionary<string, string> locale,
        string status,
        string displayName,
        string sourceLabel,
        string sourceColor,
        string metricsText,
        bool hasAttention)
    {
        var contextVisible = settings.Fields.TryGetValue("context", out var showContext) && showContext;
        var contextText = state.Snapshot is null
            ? Get(locale, "waiting")
            : $"{Get(locale, "context")} {(state.Snapshot.ContextWindow > 0 ? HudFormatting.FormatPercent(state.Snapshot.ContextPercent) : "--")}";
        var appearanceSignature = string.Join('|',
            settings.Preset,
            settings.Background,
            settings.Foreground,
            settings.Muted,
            settings.Border,
            settings.Accent,
            settings.CornerRadius,
            settings.Opacity,
            settings.TransparencyMode,
            settings.AlwaysOnTop,
            settings.MousePassthrough,
            settings.ThemeStyle,
            StatusColor(settings, status),
            status,
            hasAttention,
            contextVisible,
            settings.Behavior.OpenTaskOnDoubleClick,
            sourceLabel,
            sourceColor,
            Get(locale, "mergeTask"),
            Get(locale, "closeTaskBubble"),
            Get(locale, "resizeTaskBubble"),
            Get(locale, "openTaskTooltip"));
        if (_appearanceSignature != appearanceSignature)
        {
            _appearanceSignature = appearanceSignature;
            Window.Topmost = settings.AlwaysOnTop;
            Window.Opacity = settings.TransparencyMode == "uniform" ? settings.Opacity : 1;
            _shell.CornerRadius = new CornerRadius(Math.Max(12, settings.CornerRadius - 4));
            _shell.Background = _brushes.CreateSurface(settings, status, hasAttention);
            _shell.BorderBrush = _brushes.Create(settings.Border, "#22FFFFFF", BrushRole.Decoration, settings, status, hasAttention);
            _shell.BorderThickness = new Thickness(settings.ThemeStyle.BorderWidth);
            _baseBorderBrush = _shell.BorderBrush;
            _baseBorderThickness = _shell.BorderThickness;
            _dot.Width = settings.ThemeStyle.StatusDotSize;
            _dot.Height = settings.ThemeStyle.StatusDotSize;
            _dot.Fill = _brushes.Create(StatusColor(settings, status), "#FF8E8E93", BrushRole.Status, settings, status, hasAttention);
            _number.Foreground = _brushes.Create(settings.Accent, "#FF0A84FF", BrushRole.Primary, settings, status, hasAttention);
            _sourceIcon.Data = Geometry.Parse(GetSourceGeometry(state));
            _sourceIcon.Stroke = _brushes.Create(sourceColor, "#FF64748B", BrushRole.Primary, settings, status, hasAttention);
            _sourceIcon.Fill = string.Equals(state.ClientSurface, "vscode", StringComparison.OrdinalIgnoreCase)
                ? _sourceIcon.Stroke
                : null;
            _sourceIcon.StrokeThickness = string.Equals(state.ClientSurface, "vscode", StringComparison.OrdinalIgnoreCase) ? 0.45 : 1.45;
            _sourceBadge.Background = ColorBrush(ParseColor(sourceColor, "#FF64748B"), 24);
            _sourceBadge.BorderBrush = ColorBrush(ParseColor(sourceColor, "#FF64748B"), 72);
            _sourceBadge.ToolTip = sourceLabel;
            _name.Foreground = _brushes.Create(settings.Foreground, "#FF111827", BrushRole.Primary, settings, status, hasAttention);
            _contextMetric.Visibility = contextVisible ? Visibility.Visible : Visibility.Collapsed;
            _contextText.Foreground = _brushes.Create(settings.Foreground, "#FF111827", BrushRole.Primary, settings, status, hasAttention);
            _contextMetric.BorderBrush = _brushes.Create("#330A84FF", "#330A84FF", BrushRole.Decoration, settings, status, hasAttention);
            _contextMetric.Background = _brushes.Create("#0D0A84FF", "#0D0A84FF", BrushRole.Decoration, settings, status, hasAttention);
            _contextMetric.ToolTip = BuildContextTooltip(state, locale);
            _metrics.Foreground = _brushes.Create(settings.Muted, "#FF667085", BrushRole.Secondary, settings, status, hasAttention);
            try
            {
                var font = new FontFamily(settings.ThemeStyle.FontFamily);
                _number.FontFamily = font;
                _name.FontFamily = font;
                _metrics.FontFamily = font;
            }
            catch (ArgumentException)
            {
            }
            _merge.ToolTip = Get(locale, "mergeTask");
            _dismiss.ToolTip = Get(locale, "closeTaskBubble");
            _resize.ToolTip = Get(locale, "resizeTaskBubble");
            _shell.ToolTip = settings.Behavior.OpenTaskOnDoubleClick &&
                             string.Equals(state.ClientSurface, "desktop", StringComparison.OrdinalIgnoreCase)
                ? Get(locale, "openTaskTooltip")
                : null;
            SetMousePassthrough(settings.MousePassthrough);
        }

        var contentSignature = string.Join('|', state.Number, displayName, sourceLabel, contextText, metricsText);
        if (_contentSignature != contentSignature)
        {
            _contentSignature = contentSignature;
            _number.Text = $"#{state.Number}";
            _name.Text = displayName;
            _contextText.Text = contextText;
            _contextMetric.ToolTip = BuildContextTooltip(state, locale);
            _metrics.Text = metricsText;
        }

        var terminalExitActive = state.TerminalExitStarted && !state.TerminalExitCompleted && state.TerminalExitUntil > DateTimeOffset.Now;
        if (!hasAttention && !terminalExitActive && (_surfaceVisualActive || _contextVisualActive))
        {
            ResetAttentionVisual();
        }
        else if (_contextVisualActive && state.ContextAlertUntil <= DateTimeOffset.Now)
        {
            HudAnimations.ResetAttention(_contextMetric);
            _contextVisualActive = false;
        }

        if (state.AttentionRevision > LastAttentionRevision && state.AttentionUntil > DateTimeOffset.Now)
        {
            LastAttentionRevision = state.AttentionRevision;
            if (_surfaceVisualActive || _contextVisualActive)
            {
                ResetAttentionVisual();
            }
            if (state.AttentionReason == "agent")
            {
                HudAnimations.StartAgent(_shell, state.AgentNoticeRecipe, settings);
                _surfaceVisualActive = true;
            }
            else if (state.AttentionReason == "context")
            {
                HudAnimations.StartContext(_contextMetric, state.ContextAlertLevel, settings);
                _contextVisualActive = true;
            }
            else
            {
                HudAnimations.StartAttention(_dot, _shell, settings.Attention.TaskBubbleMode, settings);
                _surfaceVisualActive = true;
            }
            AttentionPresented?.Invoke(StatePath, state.AttentionReason);
        }
        if (state.TerminalExitRevision > LastExitRevision && state.TerminalExitUntil > DateTimeOffset.Now)
        {
            LastExitRevision = state.TerminalExitRevision;
            HudAnimations.StartTerminalExit(
                _shell,
                settings.StatusTiming.TerminalExitMode,
                StatusColor(settings, status),
                settings,
                state.TerminalExitUntil - DateTimeOffset.Now);
            _surfaceVisualActive = true;
        }
    }

    private void ResetAttentionVisual()
    {
        HudAnimations.ResetAttention(_shell, _dot, _contextMetric);
        _shell.BorderBrush = _baseBorderBrush;
        _shell.BorderThickness = _baseBorderThickness;
        _surfaceVisualActive = false;
        _contextVisualActive = false;
    }

    private static string BuildContextTooltip(SessionState state, IReadOnlyDictionary<string, string> locale)
    {
        if (state.Snapshot is null || state.Snapshot.ContextWindow <= 0)
        {
            return Get(locale, "contextUnavailable");
        }

        var model = string.IsNullOrWhiteSpace(state.Snapshot.Model) ? Get(locale, "modelUnknown") : state.Snapshot.Model;
        return $"{model} \u00B7 {Get(locale, "contextWindow")} {HudFormatting.FormatNumber(state.Snapshot.ContextWindow, "auto")}";
    }

    public void SetIndicatorCollapsed(bool collapsed)
    {
        if (IsIndicatorCollapsed == collapsed)
        {
            return;
        }
        IsIndicatorCollapsed = collapsed;
        var visibility = collapsed ? Visibility.Collapsed : Visibility.Visible;
        _content.Visibility = visibility;
        _merge.Visibility = visibility;
        _dismiss.Visibility = visibility;
        _resize.Visibility = visibility;
        if (collapsed)
        {
            if (Window.SizeToContent == SizeToContent.Manual)
            {
                _state.BubbleWidth = Window.Width;
                _state.BubbleHeight = Window.Height;
            }
            _dot.Margin = new Thickness(0);
            _shell.Padding = new Thickness(10);
            Window.Width = double.NaN;
            Window.Height = double.NaN;
            Window.SizeToContent = SizeToContent.WidthAndHeight;
        }
        else
        {
            _dot.Margin = new Thickness(0, 0, 9, 0);
            _shell.Padding = new Thickness(12, 9, 12, 9);
            if (_state.BubbleWidth > 0 && _state.BubbleHeight > 0)
            {
                Window.SizeToContent = SizeToContent.Manual;
                Window.Width = _state.BubbleWidth;
                Window.Height = _state.BubbleHeight;
            }
            else
            {
                Window.Width = double.NaN;
                Window.Height = double.NaN;
                Window.SizeToContent = SizeToContent.WidthAndHeight;
            }
        }
        Window.UpdateLayout();
    }

    public void SetMousePassthrough(bool enabled)
    {
        _mousePassthrough = enabled;
        if (_handle == 0)
        {
            return;
        }
        var current = NativeMethods.GetWindowLong(_handle, NativeMethods.GwlExStyle);
        var next = enabled
            ? current | NativeMethods.WsExTransparent | NativeMethods.WsExNoActivate
            : (current & ~NativeMethods.WsExTransparent & ~NativeMethods.WsExNoActivate) |
              (_baseStyle & (NativeMethods.WsExTransparent | NativeMethods.WsExNoActivate));
        if (next != current)
        {
            _ = NativeMethods.SetWindowLong(_handle, NativeMethods.GwlExStyle, next);
        }
    }

    public void Dispose()
    {
        _closing = true;
        Window.Close();
    }

    private void OnShellMouseLeftButtonDown(object sender, MouseButtonEventArgs args)
    {
        if (args.ClickCount >= 2 && string.Equals(_state.ClientSurface, "desktop", StringComparison.OrdinalIgnoreCase))
        {
            OpenRequested?.Invoke(StatePath);
            args.Handled = true;
            return;
        }
        if (args.ButtonState == MouseButtonState.Pressed)
        {
            try
            {
                Window.DragMove();
            }
            catch (InvalidOperationException)
            {
            }
        }
    }

    private void OnResize(object sender, DragDeltaEventArgs args)
    {
        if (IsIndicatorCollapsed)
        {
            return;
        }
        Window.SizeToContent = SizeToContent.Manual;
        Window.Width = Math.Clamp(Math.Max(Window.ActualWidth, 220) + args.HorizontalChange, 220, 960);
        Window.Height = Math.Clamp(Math.Max(Window.ActualHeight, 54) + args.VerticalChange, 54, 360);
        _state.BubbleWidth = Window.Width;
        _state.BubbleHeight = Window.Height;
    }

    private static string StatusColor(HudSettings settings, string status) =>
        settings.StatusColors.TryGetValue(status, out var color) ? color : "#FF8E8E93";

    private static string Get(IReadOnlyDictionary<string, string> locale, string key) =>
        locale.TryGetValue(key, out var value) ? value : key;

    private static Color ParseColor(string value, string fallback)
    {
        try { return (Color)ColorConverter.ConvertFromString(value); }
        catch (FormatException) { return (Color)ColorConverter.ConvertFromString(fallback); }
    }

    private static Brush ColorBrush(Color color, byte alpha)
    {
        color.A = alpha;
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    private static string GetSourceGeometry(SessionState state)
    {
        if (string.Equals(state.ClientSurface, "vscode", StringComparison.OrdinalIgnoreCase))
        {
            return "M11.52,0.29 A0.98,0.98 0 0 0 10.82,0.33 L4.21,3.33 L1.5,1.29 A1,1 0 0 0 0,2.09 L0,13.91 A1,1 0 0 0 1.5,14.71 L4.21,12.68 L10.82,15.67 A0.98,0.98 0 0 0 11.52,15.71 L15,14.11 A1,1 0 0 0 15.6,13 L15.6,3 A1,1 0 0 0 15,2.09 Z M11,11.26 L5.73,8 L11,4.74 Z";
        }
        if (string.Equals(state.ClientSurface, "desktop", StringComparison.OrdinalIgnoreCase))
        {
            return "M1.4,2.1 L12.6,2.1 Q13,2.1 13,2.5 L13,11.5 Q13,11.9 12.6,11.9 L1.4,11.9 Q1,11.9 1,11.5 L1,2.5 Q1,2.1 1.4,2.1 Z M1.4,4.8 L12.6,4.8 M3,3.45 L3.08,3.45 M4.75,3.45 L4.83,3.45";
        }
        if (string.Equals(state.ModelProvider, "deepseek", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(state.ProfileId, SessionProfile.DeepSeekId, StringComparison.OrdinalIgnoreCase))
        {
            return "M1.4,2.1 L12.6,2.1 Q13,2.1 13,2.5 L13,11.5 Q13,11.9 12.6,11.9 L1.4,11.9 Q1,11.9 1,11.5 L1,2.5 Q1,2.1 1.4,2.1 Z M2.8,8.4 C4.1,5.7 5.55,10.4 7.05,7.65 C8.15,5.65 9.3,7.25 11.2,5.75";
        }
        return "M1.4,2.1 L12.6,2.1 Q13,2.1 13,2.5 L13,11.5 Q13,11.9 12.6,11.9 L1.4,11.9 Q1,11.9 1,11.5 L1,2.5 Q1,2.1 1.4,2.1 Z M3,5.15 L5.85,7.15 L3,9.15 M7.15,9.15 L10.65,9.15";
    }
}
