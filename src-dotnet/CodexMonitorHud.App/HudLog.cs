using System.Text;

namespace CodexMonitorHud.App;

internal sealed class HudLog
{
    private readonly string _path;
    private readonly object _gate = new();

    public HudLog(string stateRoot, bool enabled)
    {
        _path = Path.Combine(stateRoot, "runtime-v220.log");
        DebugEnabled = enabled;
    }

    public bool DebugEnabled { get; }

    public void Write(string message)
    {
        if (!DebugEnabled)
        {
            return;
        }
        try
        {
            lock (_gate)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
                if (File.Exists(_path) && new FileInfo(_path).Length > 1024 * 1024)
                {
                    File.Move(_path, _path + ".previous", overwrite: true);
                }
                File.AppendAllText(
                    _path,
                    $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}",
                    new UTF8Encoding(false));
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }
}
