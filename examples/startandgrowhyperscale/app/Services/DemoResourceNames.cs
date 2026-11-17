using System.Text.RegularExpressions;
using Microsoft.Extensions.Configuration.Json;

namespace CaldovaNetworkScheduling.Services;

// Tracked configuration uses public placeholders; real names come from the git-ignored
// appsettings.Local.json, .NET user-secrets, or the environment.
public static partial class DemoResourceNames
{
    public const string LocalSettingsFile = "appsettings.Local.json";
    public const string NetworkServerPlaceholder = "{network-server}";
    public const string StartServerPlaceholder = "{start-server}";
    public const string AppNameVariable = "$(AppName)";

    private static readonly string[] ResolvedKeys = ["ConnectionStrings:Scheduling", "ServerlessMonitor:ResourceId"];

    public static void AddLocalSettings(IConfigurationBuilder configuration, IHostEnvironment environment)
    {
        var source = new JsonConfigurationSource
        {
            Path = LocalSettingsFile,
            Optional = true,
            ReloadOnChange = false,
            FileProvider = environment.ContentRootFileProvider
        };
        // Sit directly after appsettings.{Environment}.json so user-secrets, environment, and command line still override it.
        var index = -1;
        for (var i = 0; i < configuration.Sources.Count; i++)
            if (configuration.Sources[i] is JsonConfigurationSource json
                && json.Path?.StartsWith("appsettings", StringComparison.OrdinalIgnoreCase) == true)
                index = i;
        configuration.Sources.Insert(index + 1, source);
    }

    public static void Apply(IConfiguration configuration, bool offline)
    {
        foreach (var key in ResolvedKeys)
            if (configuration[key] is { } value)
                configuration[key] = Resolve(value, configuration, offline);
    }

    public static string Resolve(string value, IConfiguration configuration, bool offline = false)
    {
        value = Replace(value, NetworkServerPlaceholder, configuration, offline,
            "Azure:NetworkSqlServer", "CALDOVA_NETWORK_SQL_SERVER", "sql-caldova-network-offline");
        return Replace(value, StartServerPlaceholder, configuration, offline,
            "Azure:StartSqlServer", "CALDOVA_PART1_SQL_SERVER", "sql-caldova-start-offline");
    }

    public static string ResolveAppName(IConfiguration configuration)
    {
        var configured = configuration["Azure:AppName"] ?? configuration["CALDOVA_NETWORK_APP_NAME"]
            ?? configuration["WEBSITE_SITE_NAME"];
        if (string.IsNullOrWhiteSpace(configured) || !AppName().IsMatch(configured))
            throw new InvalidOperationException(
                $"The app identity name is unresolved. Configure Azure:AppName in git-ignored {LocalSettingsFile}, .NET user-secrets, "
                + "or CALDOVA_NETWORK_APP_NAME in the environment. Do not commit the real app name.");
        return configured;
    }

    private static string Replace(string value, string placeholder, IConfiguration configuration, bool offline,
        string key, string environmentKey, string offlineName)
    {
        if (!value.Contains(placeholder, StringComparison.Ordinal)) return value;
        if (offline) return value.Replace(placeholder, offlineName, StringComparison.Ordinal);
        var configured = configuration[key] ?? configuration[environmentKey];
        if (string.IsNullOrWhiteSpace(configured) || !ServerName().IsMatch(configured))
            throw new InvalidOperationException(
                $"The server placeholder '{placeholder}' is unresolved. Configure {key} in git-ignored {LocalSettingsFile}, "
                + $".NET user-secrets, or {environmentKey} in the environment. Do not commit the real server name.");
        return value.Replace(placeholder, configured, StringComparison.Ordinal);
    }

    [GeneratedRegex("^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$")]
    private static partial Regex ServerName();

    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9-]{0,58}[A-Za-z0-9]$")]
    private static partial Regex AppName();
}
