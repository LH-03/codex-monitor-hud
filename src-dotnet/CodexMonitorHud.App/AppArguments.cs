namespace CodexMonitorHud.App;

internal sealed record AppArguments(
    bool Managed,
    int ParentPid,
    bool OpenSettings,
    bool SelfTest,
    bool DebugLog,
    string InstanceId,
    string? PluginRoot,
    string? HealthCheckPath)
{
    public static AppArguments Parse(string[] args)
    {
        var managed = false;
        var parentPid = 0;
        var openSettings = false;
        var selfTest = false;
        var debugLog = false;
        var instanceId = string.Empty;
        string? pluginRoot = null;
        string? healthCheckPath = null;
        for (var index = 0; index < args.Length; index++)
        {
            switch (args[index].ToLowerInvariant())
            {
                case "--managed":
                case "-managed":
                    managed = true;
                    break;
                case "--open-settings":
                case "-opensettings":
                    openSettings = true;
                    break;
                case "--self-test":
                case "-selftest":
                    selfTest = true;
                    break;
                case "--debug-log":
                case "-debuglog":
                    debugLog = true;
                    break;
                case "--parent-pid" when index + 1 < args.Length:
                case "-parentpid" when index + 1 < args.Length:
                    _ = int.TryParse(args[++index], out parentPid);
                    break;
                case "--instance-id" when index + 1 < args.Length:
                case "-instanceid" when index + 1 < args.Length:
                    instanceId = args[++index];
                    break;
                case "--plugin-root" when index + 1 < args.Length:
                    pluginRoot = args[++index];
                    break;
                case "--health-check" when index + 1 < args.Length:
                    healthCheckPath = args[++index];
                    break;
            }
        }

        return new AppArguments(managed, parentPid, openSettings, selfTest, debugLog, instanceId, pluginRoot, healthCheckPath);
    }
}
