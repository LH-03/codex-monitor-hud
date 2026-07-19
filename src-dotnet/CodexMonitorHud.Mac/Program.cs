using Avalonia;

namespace CodexMonitorHud.Mac;

internal static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        if (MacHealthCheck.TryRun(args, out var exitCode))
        {
            return exitCode;
        }

        App.LaunchOptions = MacLaunchOptions.Parse(args);
        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        return 0;
    }

    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>()
            .UsePlatformDetect();
}
