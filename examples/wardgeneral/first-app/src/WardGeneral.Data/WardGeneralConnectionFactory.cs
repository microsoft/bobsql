using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace WardGeneral.Data;

/// <summary>
/// The single connection class the app reuses.
///
/// The whole point of this file: <b>there is no secret here</b>. On-prem you
/// ship a SQL login + password in a connection string and guard it forever. Here the app
/// authenticates to <c>wardgeneral</c> with <b>Microsoft Entra</b> — a managed identity in
/// Azure, or the developer's <c>az login</c> / Visual Studio / VS Code identity locally —
/// via <see cref="SqlAuthenticationMethod.ActiveDirectoryDefault"/>. No password, no key,
/// no connection-string secret to leak.
///
/// It also carries the app-side transient-fault policy (<see cref="RetryPolicy"/>).
///
/// Note what is <i>not</i> here: the chart app reads and writes the <b>primary</b> replica and
/// nothing else. The HA secondary exists because the database is zone redundant and it is the
/// automatic failover target — not as a place for this app to send reads. The one workload that
/// does move off the primary is research, and it goes to a read-only <b>named replica</b> through
/// <see cref="CreateResearch"/>.
/// </summary>
public sealed class WardGeneralConnectionFactory
{
    private readonly string _server;
    private readonly string _database;
    private readonly string? _researchDatabase;

    public WardGeneralConnectionFactory(IConfiguration config)
    {
        // Fail at startup, with instructions, rather than at the first data load with
        // a network error. appsettings.json ships these EMPTY on purpose — no live
        // server name is ever the committed default.
        _server = Require(config, "WardGeneral:Server", "your-server.database.windows.net");
        _database = Require(config, "WardGeneral:Database", "wardgeneral");
        // Optional: the read-only named replica (same logical server) for research reads.
        _researchDatabase = config["Research:Database"];
    }

    private static string Require(IConfiguration config, string key, string example)
    {
        var value = config[key];
        if (!string.IsNullOrWhiteSpace(value)) return value;

        var envVar = key.Replace(":", "__");
        throw new InvalidOperationException(
            $"{key} is not configured. Set it in src/WardGeneral.Web/appsettings.Development.json, " +
            $"or set the {envVar} environment variable, or start the app with " +
            $"./run.ps1 -Server {example}");
    }

    /// <summary>Human-readable target, for the UI banner.</summary>
    public string Target => $"{_database} @ {_server}";

    /// <summary>Human-readable research target (the named replica), for the UI banner.</summary>
    public string ResearchTarget => $"{_researchDatabase} @ {_server}";

    /// <summary>
    /// Build a connection to <c>wardgeneral</c> on the <b>primary</b> replica. Every read and
    /// every write the application performs goes through this one connection.
    /// </summary>
    public SqlConnection Create()
    {
        var builder = new SqlConnectionStringBuilder
        {
            DataSource = _server,
            InitialCatalog = _database,
            Encrypt = SqlConnectionEncryptOption.Mandatory,
            TrustServerCertificate = false,
            // Entra-only auth. No UID/PWD, no secret. Managed identity in Azure;
            // az CLI / VS / VS Code / interactive locally.
            Authentication = SqlAuthenticationMethod.ActiveDirectoryDefault,
            ConnectTimeout = 30,
            ApplicationName = "wardgeneral-app",
            ApplicationIntent = ApplicationIntent.ReadWrite
        };

        var connection = new SqlConnection(builder.ConnectionString)
        {
            // Retry transparently on transient faults (scale ops, failover).
            RetryLogicProvider = RetryPolicy.CreateConnectionProvider()
        };

        return connection;
    }

    /// <summary>
    /// Build a connection to the read-only <b>named replica</b> (<c>Research:Database</c> on
    /// the same logical server) for the research page. All research reads — embedding the
    /// query and the DiskANN vector search over the note corpus — run on the replica's own
    /// (serverless) compute, so the OLTP primary is never touched. A named replica is
    /// inherently read-only, so no <c>ApplicationIntent</c> is needed.
    /// </summary>
    public SqlConnection CreateResearch()
    {
        if (string.IsNullOrWhiteSpace(_researchDatabase))
            throw new InvalidOperationException("Research:Database is not configured.");

        var builder = new SqlConnectionStringBuilder
        {
            DataSource = _server,
            InitialCatalog = _researchDatabase,
            Encrypt = SqlConnectionEncryptOption.Mandatory,
            TrustServerCertificate = false,
            Authentication = SqlAuthenticationMethod.ActiveDirectoryDefault,
            ConnectTimeout = 30,
            ApplicationName = "wardgeneral-research"
        };

        return new SqlConnection(builder.ConnectionString)
        {
            RetryLogicProvider = RetryPolicy.CreateConnectionProvider()
        };
    }
}
