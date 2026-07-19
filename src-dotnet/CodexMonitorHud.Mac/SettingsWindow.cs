using System.Text.Json.Nodes;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using CodexMonitorHud.Core.Configuration;
using CodexMonitorHud.Core.Presentation;

namespace CodexMonitorHud.Mac;

internal sealed class SettingsWindow : Window
{
    private readonly JsonObject _source;
    private readonly IReadOnlyDictionary<string, string> _locale;
    private readonly string _localeRoot;
    private readonly ComboBox _language = new();
    private readonly ComboBox _mode = new();
    private readonly ComboBox _scope = new();
    private readonly ComboBox _listDetail = new();
    private readonly ComboBox _quietLayout = new();
    private readonly TextBox _activeWindow = new();
    private readonly TextBox _maxSplit = new();
    private readonly TextBox _quietMinutes = new();
    private readonly TextBox _thresholds = new();
    private readonly CheckBox _deepLinks = new();
    private readonly CheckBox _quietEnabled = new();
    private readonly CheckBox _contextAlerts = new();
    private readonly CheckBox _alwaysOnTop = new();
    private readonly CheckBox _showStatusDot = new();
    private readonly CheckBox _mousePassthrough = new();
    private readonly CheckBox _animate = new();
    private readonly Slider _opacity = new() { Minimum = 0.15, Maximum = 1, TickFrequency = 0.01 };
    private readonly Slider _fontSize = new() { Minimum = 10, Maximum = 28, TickFrequency = 1 };
    private readonly Slider _cornerRadius = new() { Minimum = 0, Maximum = 40, TickFrequency = 1 };
    private readonly Slider _scale = new() { Minimum = 0.75, Maximum = 1.75, TickFrequency = 0.05 };
    private readonly TextBox _background = new();
    private readonly TextBox _foreground = new();
    private readonly TextBox _accent = new();
    private readonly Dictionary<string, CheckBox> _fields = new(StringComparer.Ordinal);
    private readonly DispatcherTimer _previewTimer;
    private bool _ready;

    public event Action<JsonObject>? ApplyRequested;

    public SettingsWindow(JsonObject document, IReadOnlyDictionary<string, string> locale, string localeRoot)
    {
        _source = (JsonObject)document.DeepClone();
        _locale = locale;
        _localeRoot = localeRoot;
        Title = Text("settings");
        Width = 650;
        Height = 690;
        MinWidth = 520;
        MinHeight = 480;
        CanResize = true;
        _previewTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(60) };
        _previewTimer.Tick += (_, _) =>
        {
            _previewTimer.Stop();
            if (_ready) ApplyRequested?.Invoke(BuildDocument());
        };

        InitializeValues(HudSettings.From(_source));
        var tabs = new TabControl
        {
            ItemsSource = new object[]
            {
                Tab(Text("generalTab"), GeneralPanel()),
                Tab(Text("multiTaskTab"), MultiTaskPanel()),
                Tab(Text("behaviorTab"), BehaviorPanel()),
                Tab(Text("metricsTab"), MetricsPanel()),
                Tab(Text("appearanceTab"), AppearancePanel())
            }
        };
        var save = new Button
        {
            Content = Text("saveAndClose"),
            HorizontalAlignment = HorizontalAlignment.Right,
            Padding = new Thickness(18, 8)
        };
        save.Click += (_, _) =>
        {
            ApplyRequested?.Invoke(BuildDocument());
            Close();
        };
        var footer = new Border { Padding = new Thickness(0, 12, 0, 0), Child = save };
        DockPanel.SetDock(footer, Dock.Bottom);
        var dock = new DockPanel { Margin = new Thickness(16) };
        dock.Children.Add(footer);
        dock.Children.Add(tabs);
        Content = dock;
        WirePreviewEvents();
        _ready = true;
    }

    private void InitializeValues(HudSettings settings)
    {
        _deepLinks.Content = Text("openTaskOnDoubleClick");
        _quietEnabled.Content = Text("idleIndicatorEnabled");
        _contextAlerts.Content = Text("contextAlertsEnabled");
        _alwaysOnTop.Content = Text("alwaysOnTop");
        _showStatusDot.Content = Text("statusDot");
        _mousePassthrough.Content = Text("mousePassthrough");
        _animate.Content = Text("animateUpdates");
        SetItems(_language, new[] { "en", "zh-CN", "symbols" }, settings.Language);
        SetItems(_mode, new[] { "summary", "list", "split" }, settings.MultiTask.DisplayMode);
        SetItems(_scope, new[] { "aggregate", "latest" }, settings.MonitorScope);
        SetItems(_listDetail, new[] { "compact", "balanced", "detailed" }, settings.MultiTask.ListDetail);
        SetItems(_quietLayout, new[] { "overall", "horizontal", "vertical" }, settings.Behavior.IdleIndicator.Layout);
        _activeWindow.Text = settings.ActiveWindowMinutes.ToString();
        _maxSplit.Text = settings.MultiTask.MaxSplitBubbles.ToString();
        _quietMinutes.Text = settings.Behavior.IdleIndicator.AfterMinutes.ToString("0.##");
        _thresholds.Text = string.Join(",", settings.Behavior.ContextThresholds);
        _deepLinks.IsChecked = settings.Behavior.OpenTaskOnDoubleClick;
        _quietEnabled.IsChecked = settings.Behavior.IdleIndicator.Enabled;
        _contextAlerts.IsChecked = settings.Behavior.ContextAlertsEnabled;
        _alwaysOnTop.IsChecked = settings.AlwaysOnTop;
        _showStatusDot.IsChecked = settings.ShowStatusDot;
        _mousePassthrough.IsChecked = settings.MousePassthrough;
        _animate.IsChecked = settings.AnimateUpdates;
        _opacity.Value = settings.Opacity;
        _fontSize.Value = settings.FontSize;
        _cornerRadius.Value = settings.CornerRadius;
        _scale.Value = settings.Scale;
        _background.Text = settings.Background;
        _foreground.Text = settings.Foreground;
        _accent.Text = settings.Accent;
        foreach (var field in settings.Fields)
        {
            _fields[field.Key] = new CheckBox { Content = Text(field.Key), IsChecked = field.Value };
        }
    }

    private Control GeneralPanel() => Form(new[]
    {
        Row(Text("displayLanguage"), _language),
        Row(Text("displayMode"), _mode),
        Row(Text("monitorScope"), _scope),
        Row(Text("activeWindow"), _activeWindow)
    });

    private Control MultiTaskPanel() => Form(new[]
    {
        Row(Text("listDetailHint"), _listDetail),
        Row(Text("maxSplitBubbles"), _maxSplit)
    });

    private Control BehaviorPanel() => Form(new[]
    {
        _deepLinks,
        _quietEnabled,
        Row(Text("idleIndicatorDelay"), _quietMinutes),
        Row(Text("idleIndicatorLayout"), _quietLayout),
        _contextAlerts,
        Row(Text("contextThresholds"), _thresholds)
    });

    private Control MetricsPanel()
    {
        var wrap = new WrapPanel { Orientation = Orientation.Horizontal };
        foreach (var field in _fields.OrderBy(static pair => pair.Key, StringComparer.Ordinal))
        {
            field.Value.Width = 190;
            field.Value.Margin = new Thickness(0, 0, 8, 8);
            wrap.Children.Add(field.Value);
        }
        return Form(new Control[] { new TextBlock { Text = Text("metricsHint"), TextWrapping = TextWrapping.Wrap }, wrap });
    }

    private Control AppearancePanel() => Form(new[]
    {
        Row(Text("opacity"), _opacity),
        Row(Text("fontSize"), _fontSize),
        Row(Text("cornerRadius"), _cornerRadius),
        Row("Scale", _scale),
        _alwaysOnTop,
        _showStatusDot,
        _mousePassthrough,
        _animate,
        Row(Text("backgroundColor"), _background),
        Row(Text("foregroundColor"), _foreground),
        Row(Text("accentColor"), _accent)
    });

    private static TabItem Tab(string header, Control content) => new()
    {
        Header = header,
        Content = new ScrollViewer
        {
            Padding = new Thickness(8, 14),
            VerticalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Auto,
            Content = content
        }
    };

    private static Control Form(IEnumerable<Control> children)
    {
        var panel = new StackPanel { Spacing = 12 };
        foreach (var child in children) panel.Children.Add(child);
        return panel;
    }

    private static Control Row(string label, Control control)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("210,*") };
        grid.Children.Add(new TextBlock
        {
            Text = label,
            VerticalAlignment = VerticalAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 12, 0)
        });
        Grid.SetColumn(control, 1);
        grid.Children.Add(control);
        return grid;
    }

    private void WirePreviewEvents()
    {
        foreach (var combo in new[] { _language, _mode, _scope, _listDetail, _quietLayout })
            combo.SelectionChanged += (_, _) => QueuePreview();
        foreach (var check in new[] { _deepLinks, _quietEnabled, _contextAlerts, _alwaysOnTop, _showStatusDot, _mousePassthrough, _animate })
        {
            check.IsCheckedChanged += (_, _) => QueuePreview();
        }
        foreach (var check in _fields.Values) check.IsCheckedChanged += (_, _) => QueuePreview();
        foreach (var slider in new[] { _opacity, _fontSize, _cornerRadius, _scale })
            slider.ValueChanged += (_, _) => QueuePreview();
        foreach (var text in new[] { _activeWindow, _maxSplit, _quietMinutes, _thresholds, _background, _foreground, _accent })
            text.LostFocus += (_, _) => QueuePreview();
    }

    private void QueuePreview()
    {
        if (!_ready) return;
        _previewTimer.Stop();
        _previewTimer.Start();
    }

    private JsonObject BuildDocument()
    {
        var document = (JsonObject)_source.DeepClone();
        document["language"] = Selected(_language, "en");
        document["monitorScope"] = Selected(_scope, "aggregate");
        document["activeWindowMinutes"] = ParseInt(_activeWindow.Text, 30, 1, 1440);
        Set(document, Selected(_mode, "summary"), "multiTask", "displayMode");
        Set(document, Selected(_listDetail, "balanced"), "multiTask", "listDetail");
        Set(document, ParseInt(_maxSplit.Text, 6, 1, 12), "multiTask", "maxSplitBubbles");
        Set(document, _deepLinks.IsChecked == true, "behavior", "openTaskOnDoubleClick");
        Set(document, _quietEnabled.IsChecked == true, "behavior", "idleIndicator", "enabled");
        Set(document, ParseDouble(_quietMinutes.Text, 15, 0.01, 1440), "behavior", "idleIndicator", "afterMinutes");
        Set(document, Selected(_quietLayout, "overall"), "behavior", "idleIndicator", "layout");
        var thresholds = HudFormatting.ParseContextAlertThresholds((_thresholds.Text ?? string.Empty).Split(','));
        var contextEnabled = _contextAlerts.IsChecked == true && thresholds is not null;
        Set(document, contextEnabled, "behavior", "contextAlerts", "enabled");
        if (thresholds is not null)
        {
            Set(document, new JsonArray(thresholds.Select(static value => JsonValue.Create(value)).ToArray()), "behavior", "contextAlerts", "thresholds");
        }
        document["alwaysOnTop"] = _alwaysOnTop.IsChecked == true;
        document["showStatusDot"] = _showStatusDot.IsChecked == true;
        document["mousePassthrough"] = _mousePassthrough.IsChecked == true;
        document["animateUpdates"] = _animate.IsChecked == true;
        document["opacity"] = Math.Round(_opacity.Value, 2);
        document["fontSize"] = Math.Round(_fontSize.Value, 1);
        document["cornerRadius"] = Math.Round(_cornerRadius.Value, 1);
        document["scale"] = Math.Round(_scale.Value, 2);
        document["background"] = ValidColor(_background.Text, "#EAF7F8FA");
        document["foreground"] = ValidColor(_foreground.Text, "#FF111827");
        document["accent"] = ValidColor(_accent.Text, "#FF0A84FF");
        var fields = document["fields"] as JsonObject ?? new JsonObject();
        document["fields"] = fields;
        foreach (var field in _fields) fields[field.Key] = field.Value.IsChecked == true;
        if (contextEnabled) fields["context"] = true;
        HudConfigStore.Normalize(document, _localeRoot);
        return document;
    }

    private static void Set(JsonObject root, JsonNode? value, params string[] path)
    {
        var current = root;
        foreach (var part in path[..^1])
        {
            if (current[part] is not JsonObject next)
            {
                next = new JsonObject();
                current[part] = next;
            }
            current = next;
        }
        current[path[^1]] = value;
    }

    private static void SetItems(ComboBox combo, IReadOnlyList<string> values, string selected)
    {
        combo.ItemsSource = values;
        combo.SelectedIndex = Math.Max(0, values.ToList().IndexOf(selected));
    }

    private static string Selected(ComboBox combo, string fallback) => combo.SelectedItem as string ?? fallback;
    private static int ParseInt(string? value, int fallback, int minimum, int maximum) =>
        int.TryParse(value, out var parsed) ? Math.Clamp(parsed, minimum, maximum) : fallback;
    private static double ParseDouble(string? value, double fallback, double minimum, double maximum) =>
        double.TryParse(value, out var parsed) && double.IsFinite(parsed) ? Math.Clamp(parsed, minimum, maximum) : fallback;
    private static string ValidColor(string? value, string fallback)
    {
        var text = (value ?? string.Empty).Trim();
        if (text.Length != 9 || text[0] != '#' || !text[1..].All(Uri.IsHexDigit)) return fallback;
        return text.ToUpperInvariant();
    }
    private string Text(string key) => MacVisuals.Text(_locale, key);
}
