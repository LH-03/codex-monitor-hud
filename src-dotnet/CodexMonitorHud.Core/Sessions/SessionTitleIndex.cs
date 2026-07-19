using System.Text.Json;
using System.Text.RegularExpressions;

namespace CodexMonitorHud.Core.Sessions;

public sealed partial class SessionTitleIndex
{
    private Dictionary<string, string> _titles = new(StringComparer.Ordinal);
    private readonly IncrementalJsonlReader _reader = new(0);
    private DateTime _lastWriteTimeUtc = DateTime.MinValue;
    private DateTime _creationTimeUtc = DateTime.MinValue;
    private ulong _firstRecordSignature;

    public bool HasBacklog => _reader.HasUnreadData;

    public bool Refresh(string path)
    {
        if (!File.Exists(path))
        {
            return false;
        }

        try
        {
            var file = new FileInfo(path);
            file.Refresh();
            var writeTime = file.LastWriteTimeUtc;
            var firstRecordSignature = ReadFirstRecordSignature(path);
            var identityChanged = _reader.Offset > 0 &&
                ((_creationTimeUtc != DateTime.MinValue && file.CreationTimeUtc != _creationTimeUtc) ||
                 (_firstRecordSignature != 0 && firstRecordSignature != _firstRecordSignature));
            if (!identityChanged && writeTime <= _lastWriteTimeUtc && file.Length == _reader.Offset)
            {
                return false;
            }

            var reset = file.Length < _reader.Offset || identityChanged;
            if (reset)
            {
                _reader.Reset();
                _titles = new Dictionary<string, string>(StringComparer.Ordinal);
            }

            var changed = reset;
            foreach (var line in _reader.ReadAppended(path))
            {
                try
                {
                    using var document = JsonDocument.Parse(line);
                    var root = document.RootElement;
                    var id = root.TryGetProperty("id", out var idNode) ? idNode.GetString() ?? string.Empty : string.Empty;
                    var title = root.TryGetProperty("thread_name", out var titleNode) ? titleNode.GetString() ?? string.Empty : string.Empty;
                    title = WhitespaceRegex().Replace(title, " ").Trim();
                    if (string.IsNullOrWhiteSpace(id) || string.IsNullOrWhiteSpace(title))
                    {
                        continue;
                    }

                    if (title.Length > 52)
                    {
                        title = title[..52].TrimEnd() + '\u2026';
                    }

                    if (!_titles.TryGetValue(id, out var previous) || previous != title)
                    {
                        _titles[id] = title;
                        changed = true;
                    }
                }
                catch (JsonException)
                {
                }
                catch (InvalidOperationException)
                {
                }
            }

            _lastWriteTimeUtc = writeTime;
            _creationTimeUtc = file.CreationTimeUtc;
            _firstRecordSignature = firstRecordSignature;
            return changed;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }

    public string GetTitle(string? sessionId) =>
        !string.IsNullOrWhiteSpace(sessionId) && _titles.TryGetValue(sessionId, out var title)
            ? title
            : string.Empty;

    private static ulong ReadFirstRecordSignature(string path)
    {
        Span<byte> buffer = stackalloc byte[4096];
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        var read = stream.Read(buffer);
        var newline = buffer[..read].IndexOf((byte)'\n');
        var count = newline >= 0 ? newline + 1 : read;
        if (count == 0)
        {
            return 0;
        }

        const ulong offset = 14695981039346656037;
        const ulong prime = 1099511628211;
        var hash = offset;
        foreach (var value in buffer[..count])
        {
            hash ^= value;
            hash *= prime;
        }
        return hash;
    }

    [GeneratedRegex("\\s+", RegexOptions.CultureInvariant)]
    private static partial Regex WhitespaceRegex();
}
