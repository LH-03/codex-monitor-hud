using System.Runtime.InteropServices;
using System.Text;
using CodexMonitorHud.Core.Sessions;

namespace CodexMonitorHud.App;

/// <summary>
/// Reads only non-content liveness fields from Codex state_5.sqlite. It opens
/// the database read-only through the Windows system SQLite library. Any
/// missing database, older schema, lock, or platform mismatch degrades to the
/// normal JSONL discovery path.
/// </summary>
internal sealed class WindowsSessionActivitySource : ISessionActivitySource
{
    private const int SqliteOk = 0;
    private const int SqliteRow = 100;
    private const int SqliteDone = 101;
    private const int SqliteOpenReadOnly = 0x00000001;

    public IReadOnlyList<SessionActivity> GetRecentUserSessions(
        SessionProfile profile,
        DateTimeOffset cutoff,
        int maximumRows)
    {
        var databasePath = profile.StateDatabasePath;
        if (!OperatingSystem.IsWindows() ||
            string.IsNullOrWhiteSpace(databasePath) ||
            !File.Exists(databasePath))
        {
            return Array.Empty<SessionActivity>();
        }

        var database = IntPtr.Zero;
        var statement = IntPtr.Zero;
        try
        {
            if (Native.sqlite3_open_v2(Utf8(databasePath), out database, SqliteOpenReadOnly, IntPtr.Zero) != SqliteOk ||
                database == IntPtr.Zero)
            {
                return Array.Empty<SessionActivity>();
            }

            _ = Native.sqlite3_busy_timeout(database, 75);
            var cutoffMilliseconds = cutoff.ToUnixTimeMilliseconds();
            var rowLimit = Math.Clamp(maximumRows, 1, 256);
            var sql = $"""
                SELECT id, rollout_path, updated_at_ms
                FROM threads
                WHERE archived = 0
                  AND thread_source = 'user'
                  AND updated_at_ms >= {cutoffMilliseconds}
                ORDER BY updated_at_ms DESC
                LIMIT {rowLimit}
                """;
            if (Native.sqlite3_prepare_v2(database, Utf8(sql), -1, out statement, IntPtr.Zero) != SqliteOk ||
                statement == IntPtr.Zero)
            {
                return Array.Empty<SessionActivity>();
            }

            var results = new List<SessionActivity>(rowLimit);
            while (true)
            {
                var step = Native.sqlite3_step(statement);
                if (step == SqliteDone)
                {
                    break;
                }
                if (step != SqliteRow)
                {
                    return Array.Empty<SessionActivity>();
                }

                var sessionId = ReadText(statement, 0);
                var rolloutPath = ReadText(statement, 1);
                var updatedAtMilliseconds = Native.sqlite3_column_int64(statement, 2);
                if (string.IsNullOrWhiteSpace(sessionId) ||
                    string.IsNullOrWhiteSpace(rolloutPath) ||
                    updatedAtMilliseconds <= 0)
                {
                    continue;
                }

                DateTimeOffset updatedAt;
                try
                {
                    updatedAt = DateTimeOffset.FromUnixTimeMilliseconds(updatedAtMilliseconds);
                }
                catch (ArgumentOutOfRangeException)
                {
                    continue;
                }
                results.Add(new SessionActivity(sessionId, rolloutPath, updatedAt));
            }
            return results;
        }
        catch (DllNotFoundException)
        {
            return Array.Empty<SessionActivity>();
        }
        catch (EntryPointNotFoundException)
        {
            return Array.Empty<SessionActivity>();
        }
        catch (BadImageFormatException)
        {
            return Array.Empty<SessionActivity>();
        }
        catch (IOException)
        {
            return Array.Empty<SessionActivity>();
        }
        catch (UnauthorizedAccessException)
        {
            return Array.Empty<SessionActivity>();
        }
        finally
        {
            if (statement != IntPtr.Zero)
            {
                _ = Native.sqlite3_finalize(statement);
            }
            if (database != IntPtr.Zero)
            {
                _ = Native.sqlite3_close_v2(database);
            }
        }
    }

    private static byte[] Utf8(string value) => Encoding.UTF8.GetBytes(value + '\0');

    private static string ReadText(IntPtr statement, int column)
    {
        var pointer = Native.sqlite3_column_text(statement, column);
        return pointer == IntPtr.Zero ? string.Empty : Marshal.PtrToStringUTF8(pointer) ?? string.Empty;
    }

    private static class Native
    {
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        internal static extern int sqlite3_open_v2(byte[] filename, out IntPtr database, int flags, IntPtr vfs);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        internal static extern int sqlite3_busy_timeout(IntPtr database, int milliseconds);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        internal static extern int sqlite3_prepare_v2(
            IntPtr database,
            byte[] sql,
            int bytes,
            out IntPtr statement,
            IntPtr tail);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        internal static extern int sqlite3_step(IntPtr statement);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        internal static extern IntPtr sqlite3_column_text(IntPtr statement, int column);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        internal static extern long sqlite3_column_int64(IntPtr statement, int column);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        internal static extern int sqlite3_finalize(IntPtr statement);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        internal static extern int sqlite3_close_v2(IntPtr database);
    }
}
