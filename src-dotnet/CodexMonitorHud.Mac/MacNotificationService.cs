using System.Diagnostics;

namespace CodexMonitorHud.Mac;

internal static class MacNotificationService
{
    public static void Show(string title, string message)
    {
        if (!OperatingSystem.IsMacOS())
        {
            return;
        }
        var safeTitle = Escape(title);
        var safeMessage = Escape(message);
        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = "/usr/bin/osascript",
                UseShellExecute = false,
                CreateNoWindow = true,
                ArgumentList =
                {
                    "-e",
                    $"display notification \"{safeMessage}\" with title \"{safeTitle}\""
                }
            });
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
        }
    }

    private static string Escape(string value) => value
        .Replace("\\", "\\\\", StringComparison.Ordinal)
        .Replace("\"", "\\\"", StringComparison.Ordinal)
        .Replace("\r", " ", StringComparison.Ordinal)
        .Replace("\n", " ", StringComparison.Ordinal);
}
