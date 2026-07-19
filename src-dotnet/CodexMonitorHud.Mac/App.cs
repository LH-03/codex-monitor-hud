using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Themes.Fluent;

namespace CodexMonitorHud.Mac;

public sealed class App : Application
{
    internal static MacLaunchOptions LaunchOptions { get; set; } = MacLaunchOptions.Parse(Array.Empty<string>());
    private MacHudController? _controller;

    public override void Initialize()
    {
        Styles.Add(new FluentTheme());
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            var window = new MainWindow();
            desktop.MainWindow = window;
            desktop.ShutdownMode = Avalonia.Controls.ShutdownMode.OnExplicitShutdown;
            _controller = new MacHudController(this, window, LaunchOptions);
            desktop.Exit += (_, _) => _controller?.Dispose();
            _controller.Start();
        }

        base.OnFrameworkInitializationCompleted();
    }
}
