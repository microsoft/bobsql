using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace WardGeneral.Data;

/// <summary>
/// Talk verb: <b>Secure it</b>.
///
/// The single connection class the app reuses.
/// The whole point of this file for the talk: <b>there is no secret here</b>. On-prem you
/// ship a SQL login + password in a connection string and guard it forever. Here the app
/// authenticates to <c>wardgeneral</c> with <b>Microsoft Entra</b> — a managed identity in
/// Azure, or the developer's <c>az login</c> / Visual Studio / VS Code identity locally —
/// via <see cref="SqlAuthenticationMethod.ActiveDirectoryDefault"/>. No password, no key,
/// no connection-string secret to leak.
///
/// It also carries the app-side HA policy (<see cref="RetryPolicy"/>) and can hand back a
/// read-only connection for read scale-out (see <paramref name="readOnly"/>) — talk verb
/// <b>Make it HA</b>.
/// </summary>
public sealed class WardGeneralConnectionFactory
{
    private readonly string _server;
    private readonly string _database;
    private readonly string? _researchDatabase;

    public WardGeneralConnectionFactory(IConfiguration config)
    {
        _server = config["WardGeneral:Server"]
                  ?? throw new InvalidOperationException("WardGeneral:Server is not configured.");
        _database = config["WardGeneral:Database"]
                    ?? throw new InvalidOperationException("WardGeneral:Database is not configured.");
        // Optional: the read-only named replica (same logical server) for research reads.
        _researchDatabase = config["Research:Database"];
    }

    /// <summary>Human-readable target, for the UI banner.</summary>
    public string Target => $"{_database} @ {_server}";

    /// <summary>Human-readable research target (the named replica), for the UI banner.</summary>
    public string ResearchTarget => $"{_researchDatabase} @ {_server}";

    /// <summary>
    /// Build a connection. When <paramref name="readOnly"/> is true the connection asks the
    /// gateway to route it to a read-scale-out replica (<c>ApplicationIntent=ReadOnly</c>) —
    /// an app connection-string change, not an app rewrite.
    /// </summary>
    public SqlConnection Create(bool readOnly = false)
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
            ApplicationIntent = readOnly ? ApplicationIntent.ReadOnly : ApplicationIntent.ReadWrite
        };

        var connection = new SqlConnection(builder.ConnectionString)
        {
            // Retry transparently on transient faults (scale ops, failover).
            RetryLogicProvider = RetryPolicy.CreateProvider()
        };

        return connection;
    }

    /// <summary>
    /// Build a connection to the read-only <b>named replica</b> (<c>Research:Database</c> on
    /// the same logical server) for the research page. All research reads — embedding the
    /// query and the DiskANN vector search over the note corpus — run on the replica's own
    /// (serverless) compute, so the OLTP primary is never touched. A named replica is
    /// inherently read-only, so no <c>ApplicationIntent</c> is needed. Talk verb: <b>Scale it</b>.
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
            RetryLogicProvider = RetryPolicy.CreateProvider()
        };
    }
}
