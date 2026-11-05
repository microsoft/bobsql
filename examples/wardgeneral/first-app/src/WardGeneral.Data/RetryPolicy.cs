using Microsoft.Data.SqlClient;

namespace WardGeneral.Data;

/// <summary>
/// On-prem, HA is the platform's job to build (WSFC + Availability Groups) and the
/// app mostly ignores it. On Hyperscale the platform owns failover — but the ONE
/// thing the app still owns is <i>transient-fault handling</i>: during a scale
/// operation or a failover the app briefly sees a dropped connection, and a resilient
/// app simply retries.
///
/// This is the canonical retry policy. It uses the built-in configurable retry
/// logic in Microsoft.Data.SqlClient (no Polly, no custom loop) so the retry happens
/// underneath ADO.NET on both <see cref="SqlConnection"/> open and <see cref="SqlCommand"/>
/// execute.
/// </summary>
public static class RetryPolicy
{
    // Extend the driver-owned baseline with transport resets and Azure SQL failover
    // subcodes that can surface as top-level SqlException numbers.
    private static readonly int[] TransientErrorNumbers =
    [
        .. SqlConfigurableRetryFactory.BaselineTransientErrors,
        64,    // Transport failure after a connection was established.
        10053, // Established connection aborted by the local host.
        10054, // Established connection reset by the remote host.
        40020, // Azure SQL failover subcode that can surface as the top-level error.
        40166  // Azure SQL failover subcode that can surface as the top-level error.
    ];

    /// <summary>Create a fresh exponential-backoff provider for connection opens.</summary>
    public static SqlRetryLogicBaseProvider CreateConnectionProvider() => CreateProvider();

    /// <summary>Create a fresh provider for a command the caller has established is read-only.</summary>
    public static SqlRetryLogicBaseProvider CreateReadOnlyCommandProvider() =>
        CreateProvider(_ => true);

    private static SqlRetryLogicBaseProvider CreateProvider(Predicate<string>? authorizedSqlCondition = null)
    {
        var options = new SqlRetryLogicOption
        {
            NumberOfTries = 5,
            DeltaTime = TimeSpan.FromSeconds(2),
            MaxTimeInterval = TimeSpan.FromSeconds(30),
            TransientErrors = TransientErrorNumbers,
            AuthorizedSqlCondition = authorizedSqlCondition
        };

        return SqlConfigurableRetryFactory.CreateExponentialRetryProvider(options);
    }
}
