using Microsoft.Data.SqlClient;

namespace WardGeneral.Data;

/// <summary>
/// Talk verb: <b>Make it HA</b> (app-side).
///
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
    // Transient/retryable errors that matter on Azure SQL / Hyperscale, including the
    // ones seen during a scale operation or a failover.
    private static readonly int[] TransientErrorNumbers =
    {
        40613, // Database currently unavailable (opening/failover)
        40197, // Service error processing request (reconfiguration)
        40501, // Service busy
        49918, 49919, 49920, // Cannot process request / too many operations
        4060,  // Cannot open database (transient during failover)
        10928, 10929, // Resource governance limits
        233,   // No process on the other end of the pipe (connection dropped)
        64,    // A connection was successfully established but then failed
        -2,    // Timeout
        20     // Instance not currently able to accept the connection
    };

    /// <summary>Create a fresh exponential-backoff retry provider (5 tries, ~2s→30s).</summary>
    public static SqlRetryLogicBaseProvider CreateProvider()
    {
        var options = new SqlRetryLogicOption
        {
            NumberOfTries = 5,
            DeltaTime = TimeSpan.FromSeconds(2),
            MaxTimeInterval = TimeSpan.FromSeconds(30),
            TransientErrors = TransientErrorNumbers
        };

        return SqlConfigurableRetryFactory.CreateExponentialRetryProvider(options);
    }
}
