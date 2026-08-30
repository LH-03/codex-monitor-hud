using System.Diagnostics;
using System.Text.Json;

namespace CodexMonitorHud.Core.Sessions;

public sealed record OfficialCodexAllowance(
    DateTimeOffset ObservedAt,
    double? FiveHourRemainingPercent,
    double? WeeklyRemainingPercent);

/// <summary>Reads only the authenticated Codex app-server allowance response.</summary>
public static class OfficialCodexAllowanceReader
{
    // A cold Codex app-server may take longer than a HUD UI frame to start.
    // This reader runs off the UI thread, so do not race into a false fallback.
    private static readonly TimeSpan ReadTimeout = TimeSpan.FromSeconds(20);

    public static async Task<OfficialCodexAllowance?> TryReadAsync()
    {
        return await TryReadAsync(OperatingSystem.IsWindows() ? "codex.cmd" : "codex").ConfigureAwait(false);
    }

    private static async Task<OfficialCodexAllowance?> TryReadAsync(string executable)
    {
        using var process = new Process { StartInfo = new ProcessStartInfo
        {
            FileName = executable, Arguments = "app-server --stdio", UseShellExecute = false,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true
        }};
        process.StartInfo.Environment["CODEX_HOME"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex");
        try
        {
            if (!process.Start()) return null;
            _ = process.StandardError.ReadToEndAsync();
            await process.StandardInput.WriteLineAsync("{\"method\":\"initialize\",\"id\":1,\"params\":{\"clientInfo\":{\"name\":\"codex-monitor-hud\",\"version\":\"3.2.1\"},\"capabilities\":{\"optOutNotificationMethods\":[\"account/updated\",\"account/rateLimits/updated\"]}}}").ConfigureAwait(false);
            await process.StandardInput.WriteLineAsync("{\"method\":\"initialized\",\"params\":{}}").ConfigureAwait(false);
            await process.StandardInput.WriteLineAsync("{\"method\":\"account/rateLimits/read\",\"id\":2,\"params\":{}}").ConfigureAwait(false);
            await process.StandardInput.FlushAsync().ConfigureAwait(false);
            var deadline = DateTime.UtcNow + ReadTimeout;
            while (DateTime.UtcNow < deadline)
            {
                var read = process.StandardOutput.ReadLineAsync();
                var remaining = deadline - DateTime.UtcNow;
                if (remaining <= TimeSpan.Zero || await Task.WhenAny(read, Task.Delay(remaining)).ConfigureAwait(false) != read) break;
                var line = await read.ConfigureAwait(false);
                if (line is null) break;
                if (TryParse(line, out var allowance)) return allowance;
            }
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception or IOException or JsonException) { }
        finally
        {
            try { if (!process.HasExited) { process.Kill(entireProcessTree: true); await process.WaitForExitAsync().ConfigureAwait(false); } }
            catch (InvalidOperationException) { }
            catch (System.ComponentModel.Win32Exception) { }
        }
        return null;
    }

    public static bool TryParse(string line, out OfficialCodexAllowance? allowance)
    {
        allowance = null;
        using var document = JsonDocument.Parse(line);
        var root = document.RootElement;
        if (!root.TryGetProperty("id", out var id) || id.ValueKind != JsonValueKind.Number || id.GetInt32() != 2 ||
            !root.TryGetProperty("result", out var result) || !result.TryGetProperty("rateLimits", out var limits)) return false;
        double? fiveHour = null, weekly = null;
        foreach (var property in new[] { "primary", "secondary" })
        {
            if (!limits.TryGetProperty(property, out var window) || window.ValueKind != JsonValueKind.Object ||
                !window.TryGetProperty("usedPercent", out var used) || !used.TryGetDouble(out var usedPercent) ||
                !window.TryGetProperty("windowDurationMins", out var minutes) || !minutes.TryGetInt32(out var duration)) continue;
            var remaining = Math.Clamp(100d - usedPercent, 0d, 100d);
            if (duration is >= 240 and <= 360) fiveHour = remaining;
            else if (duration >= 10080) weekly = remaining;
        }
        if (!fiveHour.HasValue && !weekly.HasValue) return false;
        allowance = new OfficialCodexAllowance(DateTimeOffset.Now, fiveHour, weekly);
        return true;
    }
}
