using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using CodexMonitorHud.Core.Models;
using CodexMonitorHud.Core.Parsing;

namespace CodexMonitorHud.Mac;

internal static class MacHealthCheck
{
    public static bool TryRun(string[] args, out int exitCode)
    {
        var index = Array.IndexOf(args, "--health-check");
        if (index < 0)
        {
            exitCode = 0;
            return false;
        }

        if (index + 1 >= args.Length || string.IsNullOrWhiteSpace(args[index + 1]))
        {
            Console.Error.WriteLine("--health-check requires an output path.");
            exitCode = 2;
            return true;
        }

        try
        {
            var baseDirectory = AppContext.BaseDirectory;
            var defaultConfig = Path.Combine(baseDirectory, "config.default.json");
            var locale = Path.Combine(baseDirectory, "locales", "en.json");
            _ = JsonNode.Parse(File.ReadAllText(defaultConfig, Encoding.UTF8)) as JsonObject
                ?? throw new JsonException("Default configuration root must be an object.");
            _ = JsonNode.Parse(File.ReadAllText(locale, Encoding.UTF8)) as JsonObject
                ?? throw new JsonException("English locale root must be an object.");
            var synthetic = HudRecordParser.Parse(
                """{"type":"turn_context","payload":{"cwd":"/Users/synthetic/portable-health","model":"gpt-test"}}""");
            if (synthetic?.Workspace != "portable-health")
            {
                throw new InvalidDataException("Portable Core parser health check failed.");
            }

            var outputPath = Path.GetFullPath(args[index + 1]);
            Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
            File.WriteAllText(outputPath, JsonSerializer.Serialize(new
            {
                version = "3.0.0",
                platform = "macos",
                architecture = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant(),
                config = "ok",
                locale = "ok",
                parser = "ok",
                phase = "functional-host-candidate"
            }), new UTF8Encoding(false));
            exitCode = 0;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException or InvalidDataException)
        {
            Console.Error.WriteLine(exception.Message);
            exitCode = 1;
        }

        return true;
    }
}
