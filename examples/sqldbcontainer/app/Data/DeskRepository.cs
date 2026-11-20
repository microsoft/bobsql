using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;

namespace CustomerServiceDesk.Data;

public sealed class DeskRepository
{
    private readonly string connectionString;
    private Task<DeskEnvironment>? environment;

    public DeskRepository(IConfiguration configuration)
    {
        connectionString = configuration.GetConnectionString("CustomerServiceDesk")
            ?? throw new InvalidOperationException("Run setup-app.ps1 to configure the CustomerServiceDesk connection.");
    }

    private async Task<List<T>> QueryAsync<T>(string procedure, Func<SqlDataReader, T> map,
        CancellationToken cancellationToken, params SqlParameter[] parameters)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new SqlCommand(procedure, connection) { CommandType = CommandType.StoredProcedure };
        command.Parameters.AddRange(parameters);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var rows = new List<T>();
        while (await reader.ReadAsync(cancellationToken))
            rows.Add(map(reader));
        return rows;
    }

    private static string Text(SqlDataReader reader, string name) => reader.GetString(reader.GetOrdinal(name));
    private static string? OptionalText(SqlDataReader reader, string name) =>
        reader.IsDBNull(reader.GetOrdinal(name)) ? null : Text(reader, name);
    private static int Number(SqlDataReader reader, string name) => reader.GetInt32(reader.GetOrdinal(name));
    private static SqlParameter Parameter(string name, SqlDbType type, object? value, int size = 0) =>
        new(name, type, size) { Value = value ?? DBNull.Value };

    public Task<List<CaseRow>> GetCasesAsync(string? status, string? channel, CancellationToken token) =>
        QueryAsync("dbo.GetCases", r => new CaseRow(Number(r, "CaseId"), Text(r, "Title"),
            Text(r, "Topic"), Text(r, "Status"), Text(r, "Priority"), Text(r, "DisplayName"),
            OptionalText(r, "Channel") ?? "", r.GetDateTime(r.GetOrdinal("UpdatedAt"))), token,
            Parameter("@Status", SqlDbType.VarChar, status, 20),
            Parameter("@Channel", SqlDbType.NVarChar, channel, 20),
            Parameter("@Take", SqlDbType.Int, 100));

    public async Task<CaseDetail> GetCaseAsync(int id, CancellationToken token)
    {
        var rows = await QueryAsync("dbo.GetCase", r => new CaseDetail(Number(r, "CaseId"),
            Number(r, "CustomerId"), Text(r, "Title"), Text(r, "Description"), OptionalText(r, "Resolution"),
            Text(r, "Topic"), Text(r, "Status"), Text(r, "Priority"), Text(r, "Details"),
            r.GetDateTime(r.GetOrdinal("CreatedAt")), r.GetDateTime(r.GetOrdinal("UpdatedAt")),
            r.GetFieldValue<byte[]>(r.GetOrdinal("Version")), Text(r, "DisplayName"),
            Text(r, "Email"), Text(r, "Phone")), token, Parameter("@CaseId", SqlDbType.Int, id));
        return rows.Single();
    }

    public Task<List<CustomerOption>> GetCustomersAsync(CancellationToken token) =>
        QueryAsync("dbo.GetCustomers", r => new CustomerOption(Number(r, "CustomerId"), Text(r, "DisplayName")), token);

    public Task<List<PreparedSearch>> GetPreparedSearchesAsync(CancellationToken token) =>
        QueryAsync("dbo.GetPreparedSearches", r => new PreparedSearch(Number(r, "PreparedSearchId"), Text(r, "SearchText")), token);

    private static SearchHit ReadHit(SqlDataReader reader) => new(Number(reader, "CaseId"),
        Text(reader, "Title"), OptionalText(reader, "Resolution") ?? "", Text(reader, "Topic"),
        reader.GetDouble(reader.GetOrdinal("CosineDistance")));

    public Task<List<SearchHit>> SearchAsync(int id, CancellationToken token) =>
        QueryAsync("dbo.SearchPreparedCases", ReadHit, token,
            Parameter("@PreparedSearchId", SqlDbType.Int, id));

    public async Task<SearchProfile?> GetSearchProfileAsync(CancellationToken token)
    {
        var profiles = await QueryAsync("dbo.GetSearchProfile", r => new SearchProfile(
            Number(r, "ProfileId"), Text(r, "Provider"), Text(r, "ModelName"),
            Text(r, "ModelVersion"), Number(r, "Dimensions"), Text(r, "QueryPrefix")), token);
        return profiles.SingleOrDefault();
    }

    public Task<List<SearchHit>> SearchLiveAsync(SearchProfile profile, float[] vector, CancellationToken token) =>
        QueryAsync("dbo.SearchLiveCases", ReadHit, token,
            Parameter("@ProfileId", SqlDbType.Int, profile.ProfileId),
            Parameter("@QueryJson", SqlDbType.NVarChar, JsonSerializer.Serialize(vector), -1));

    public Task<DeskEnvironment> GetEnvironmentAsync(CancellationToken token) =>
        environment ??= LoadEnvironmentAsync(token);

    private async Task<DeskEnvironment> LoadEnvironmentAsync(CancellationToken token)
    {
        var rows = await QueryAsync("dbo.GetDeskEnvironment", r => new DeskEnvironment(
            Text(r, "DatabaseName"), Text(r, "DatabaseUser"), Text(r, "Edition"), Number(r, "EngineEdition"),
            Text(r, "EngineVersion"), Number(r, "TotalCases"), Number(r, "OpenCases"), Number(r, "InProgressCases"),
            Number(r, "ResolvedCases"), Number(r, "PendingEmbeddings"), OptionalText(r, "ProfileName"),
            OptionalText(r, "ModelName"), OptionalText(r, "ModelVersion"),
            r.IsDBNull(r.GetOrdinal("Dimensions")) ? null : Number(r, "Dimensions"),
            Number(r, "ReadyQueries"), Number(r, "TotalQueries"), r.GetBoolean(r.GetOrdinal("JsonIndexPresent")),
            OptionalText(r, "VectorIndexVersion"), Number(r, "PreviewFeatures"), Number(r, "CanUnmask"),
            Number(r, "CanReadCustomers")), token);
        return rows.Single();
    }

    private static SqlParameter[] CaseParameters(CaseInput input) =>
    [
        Parameter("@Title", SqlDbType.NVarChar, input.Title, 200),
        Parameter("@Description", SqlDbType.NVarChar, input.Description, 2000),
        Parameter("@Resolution", SqlDbType.NVarChar, input.Resolution, 2000),
        Parameter("@Topic", SqlDbType.VarChar, input.Topic, 40),
        Parameter("@Status", SqlDbType.VarChar, input.Status, 20),
        Parameter("@Priority", SqlDbType.VarChar, input.Priority, 10),
        Parameter("@Details", SqlDbType.NVarChar, input.Details, -1)
    ];

    public async Task<int> CreateAsync(int customerId, CaseInput input, CancellationToken token)
    {
        var rows = await QueryAsync("dbo.CreateCase", r => Number(r, "CaseId"), token,
            [Parameter("@CustomerId", SqlDbType.Int, customerId), .. CaseParameters(input)]);
        return rows.Single();
    }

    public async Task UpdateAsync(int id, byte[] version, CaseInput input, CancellationToken token)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(token);
        await using var command = new SqlCommand("dbo.UpdateCase", connection) { CommandType = CommandType.StoredProcedure };
        command.Parameters.AddRange([
            Parameter("@CaseId", SqlDbType.Int, id),
            Parameter("@Version", SqlDbType.Binary, version, 8),
            .. CaseParameters(input)]);
        await command.ExecuteNonQueryAsync(token);
    }
}
