namespace CodexMonitorHud.Mac;

internal sealed record MacLaunchOptions(
    string PluginRoot,
    string? TestHome,
    string? TestStateRoot,
    string? SmokeOutput,
    bool SmokeSettingsUpdate,
    bool Managed,
    int ParentPid,
    bool OpenSettings)
{
    public static MacLaunchOptions Parse(string[] args)
    {
        var pluginRoot = AppContext.BaseDirectory;
        string? testHome = null;
        string? testStateRoot = null;
        string? smokeOutput = null;
        var openSettings = false;
        var smokeSettingsUpdate = false;
        var managed = false;
        var parentPid = 0;
        for (var index = 0; index < args.Length; index++)
        {
            switch (args[index])
            {
                case "--plugin-root" when index + 1 < args.Length:
                    pluginRoot = Path.GetFullPath(args[++index]);
                    break;
                case "--test-home" when index + 1 < args.Length:
                    testHome = Path.GetFullPath(args[++index]);
                    break;
                case "--test-state-root" when index + 1 < args.Length:
                    testStateRoot = Path.GetFullPath(args[++index]);
                    break;
                case "--smoke-output" when index + 1 < args.Length:
                    smokeOutput = Path.GetFullPath(args[++index]);
                    break;
                case "--open-settings":
                    openSettings = true;
                    break;
                case "--smoke-settings-update":
                    smokeSettingsUpdate = true;
                    break;
                case "--managed":
                    managed = true;
                    break;
                case "--parent-pid" when index + 1 < args.Length:
                    _ = int.TryParse(args[++index], out parentPid);
                    break;
            }
        }
        return new MacLaunchOptions(pluginRoot, testHome, testStateRoot, smokeOutput, smokeSettingsUpdate, managed, parentPid, openSettings);
    }
}
