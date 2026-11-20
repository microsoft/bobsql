using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using GitHub.Copilot.Rpc;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using MigrationStudio;
using MigrationStudio.Services;
using Xunit;

namespace MigrationStudioTests;

public sealed class ApprovalTests
{
    [Fact]
    public async Task CopilotSignInRequiresProtectedBrowserSessionAndNeverQueuesInference()
    {
        await using var factory = new StudioFactory();
        using var client = factory.CreateClient(new() { BaseAddress = new Uri("http://localhost:5188") });
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/copilot/signin")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsJsonAsync("/api/copilot/signin", new { })).StatusCode);
        var session = await client.GetFromJsonAsync<JsonElement>("/api/session");
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PostAsJsonAsync("/api/copilot/signin", new { })).StatusCode);
        client.DefaultRequestHeaders.Add("Origin", "https://untrusted.example");
        client.DefaultRequestHeaders.Add("X-CSRF-TOKEN", session.GetProperty("csrfToken").GetString());
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PostAsJsonAsync("/api/copilot/signin", new { })).StatusCode);
        client.DefaultRequestHeaders.Remove("Origin");
        client.DefaultRequestHeaders.Add("Origin", "http://localhost:5188");
        var begun = await client.PostAsJsonAsync("/api/copilot/signin", new { });
        Assert.Equal(HttpStatusCode.OK, begun.StatusCode);
        var challenge = await begun.Content.ReadFromJsonAsync<CopilotSignInState>();
        Assert.Equal("waiting", challenge!.State);
        var stored = await client.GetFromJsonAsync<CopilotSignInState>("/api/copilot/signin");
        Assert.Equal(challenge, stored);
        using var other = factory.CreateClient(new() { BaseAddress = new Uri("http://localhost:5188") });
        var otherSession = await other.GetFromJsonAsync<JsonElement>("/api/session");
        other.DefaultRequestHeaders.Add("Origin", "http://localhost:5188");
        other.DefaultRequestHeaders.Add("X-CSRF-TOKEN", otherSession.GetProperty("csrfToken").GetString());
        var hidden = await other.GetFromJsonAsync<CopilotSignInState>("/api/copilot/signin");
        Assert.Null(hidden!.UserCode);
        Assert.Equal(HttpStatusCode.NotFound, (await other.PostAsJsonAsync($"/api/copilot/signin/{challenge.Id}/cancel", new { })).StatusCode);
        Assert.False((await client.GetFromJsonAsync<CopilotStatus>("/api/copilot/status"))!.Authenticated);
        var cancelled = await client.PostAsJsonAsync($"/api/copilot/signin/{challenge.Id}/cancel", new { });
        Assert.Equal("cancelled", (await cancelled.Content.ReadFromJsonAsync<CopilotSignInState>())!.State);
        Assert.Null(factory.Runner.LastOperation);
        Assert.Equal(0, factory.Runner.MigrationCalls);
    }

#pragma warning disable GHCP001
    [Fact]
    public async Task CopilotAuthorizationAdvancesAwaitingUntilActualCompletion()
    {
        var responses = new Queue<AuthLoginStep>(
        [
            new AuthLoginStepAwaiting(),
            new AuthLoginStepAwaiting(),
            new AuthLoginStepCompleted { Result = new AuthLoginResultDto { Status = AuthLoginResultStatus.Completed } }
        ]);
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await CopilotGuide.AwaitAuthorizationAsync(
            _ => Task.FromResult(responses.Dequeue()), TimeSpan.Zero, timeout.Token);
        Assert.Empty(responses);
    }

    [Theory]
    [InlineData("needs-plaintext-consent")]
    [InlineData("needs-account-selection")]
    [InlineData("declined")]
    public async Task CopilotAuthorizationReportsExactFollowUpWithoutApprovingIt(string status)
    {
        var calls = 0;
        var error = await Assert.ThrowsAsync<StudioException>(() => CopilotGuide.AwaitAuthorizationAsync(_ =>
        {
            calls++;
            return Task.FromResult<AuthLoginStep>(new AuthLoginStepCompleted
            {
                Result = new AuthLoginResultDto { Status = new AuthLoginResultStatus(status) }
            });
        }, TimeSpan.Zero, CancellationToken.None));
        Assert.Contains(status, error.Message);
        Assert.Equal(1, calls);
    }

    [Fact]
    public async Task CopilotAuthorizationCannotWaitPastCancellationOrExposeRawErrors()
    {
        using var cancellation = new CancellationTokenSource();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => CopilotGuide.AwaitAuthorizationAsync(_ =>
        {
            cancellation.Cancel();
            return Task.FromResult<AuthLoginStep>(new AuthLoginStepAwaiting());
        }, TimeSpan.Zero, cancellation.Token));
        var error = await Assert.ThrowsAsync<StudioException>(() => CopilotGuide.AwaitAuthorizationAsync(
            _ => Task.FromResult<AuthLoginStep>(new AuthLoginStepError { Message = "private authorization diagnostic" }),
            TimeSpan.Zero, CancellationToken.None));
        Assert.Contains("(error)", error.Message);
        Assert.DoesNotContain("private authorization diagnostic", error.Message);
    }

    [Theory]
    [InlineData("https://github.com.evil.example/login/device")]
    [InlineData("http://github.com/login/device")]
    [InlineData("https://github.com:444/login/device")]
    [InlineData("https://github.com/login/device?next=https://evil.example")]
    [InlineData("https://user:password@github.com/login/device")]
    [InlineData("javascript:alert(1)")]
    public void CopilotChallengeRejectsUnexpectedVerificationLinks(string url)
    {
        Assert.Throws<StudioException>(() => CopilotGuide.DeviceChallenge(new AuthLoginStepDeviceCode
        {
            VerificationUri = url, UserCode = "ABCD-EFGH", ExpiresIn = 900, Interval = 5
        }));
    }

    [Fact]
    public void CopilotChallengeHasFiniteExpiryAndNoRuntimeFlowIdentifier()
    {
        var before = DateTimeOffset.UtcNow;
        var device = new AuthLoginStepDeviceCode
        {
            VerificationUri = "https://github.com/login/device", UserCode = "ABCD-EFGH", ExpiresIn = 900, Interval = 5
        };
        var challenge = CopilotGuide.DeviceChallenge(device);
        Assert.Equal("waiting", challenge.State);
        Assert.Equal(device.UserCode, challenge.UserCode);
        Assert.InRange(challenge.ExpiresAt!.Value, before.AddSeconds(900), DateTimeOffset.UtcNow.AddSeconds(900));
        Assert.DoesNotContain("flowId", JsonSerializer.Serialize(challenge, StudioPaths.Json));
        device.ExpiresIn = 0;
        Assert.Throws<StudioException>(() => CopilotGuide.DeviceChallenge(device));
    }
#pragma warning restore GHCP001

    [Fact]
    public async Task ApiRequiresSessionAndMutationRequiresSameOriginAndToken()
    {
        await using var factory = new StudioFactory();
        using var client = factory.CreateClient(new() { BaseAddress = new Uri("http://localhost:5188") });
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/status")).StatusCode);
        var session = await client.GetFromJsonAsync<JsonElement>("/api/session");
        var token = session.GetProperty("csrfToken").GetString();
        var configuration = Configuration();
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PostAsJsonAsync("/api/plans", configuration)).StatusCode);
        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/plans") { Content = JsonContent.Create(configuration) };
        request.Headers.Add("Origin", "https://untrusted.example");
        request.Headers.Add("X-CSRF-TOKEN", token);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.SendAsync(request)).StatusCode);
        Assert.Equal(0, factory.Runner.MigrationCalls);
    }

    [Fact]
    public async Task ReviewIsImmutableAndInvalidApprovalCannotStartOperations()
    {
        await using var factory = new StudioFactory();
        using var client = factory.CreateClient(new() { BaseAddress = new Uri("http://localhost:5188") });
        var session = await client.GetFromJsonAsync<JsonElement>("/api/session");
        client.DefaultRequestHeaders.Add("Origin", "http://localhost:5188");
        client.DefaultRequestHeaders.Add("X-CSRF-TOKEN", session.GetProperty("csrfToken").GetString());
        var response = await client.PostAsJsonAsync("/api/plans", Configuration());
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var plan = await response.Content.ReadFromJsonAsync<MigrationPlan>();
        Assert.NotNull(plan);
        Assert.Equal("review", plan.State);
        Assert.Equal(0, factory.Runner.MigrationCalls);
        var denied = await client.PostAsJsonAsync($"/api/plans/{plan.Id}/run", new { confirmation = "yes", writersStopped = true });
        Assert.Equal(HttpStatusCode.BadRequest, denied.StatusCode);
        denied = await client.PostAsJsonAsync($"/api/plans/{plan.Id}/run",
            new { confirmation = MigrationWorkflow.Confirmation, writersStopped = false });
        Assert.Equal(HttpStatusCode.BadRequest, denied.StatusCode);
        Assert.Equal(0, factory.Runner.MigrationCalls);
        var stored = await client.GetFromJsonAsync<MigrationPlan>($"/api/plans/{plan.Id}");
        Assert.Equal(plan.Fingerprint, stored!.Fingerprint);
    }

    [Fact]
    public void DestinationChangeChangesFingerprintAndSystemSourceIsRejected()
    {
        var configuration = Configuration();
        Assert.NotEqual(MigrationWorkflow.Fingerprint(configuration),
            MigrationWorkflow.Fingerprint(configuration with { TargetDatabase = "different-target" }));
        Assert.Throws<StudioException>(() => MigrationWorkflow.Validate(configuration with { SourceDatabase = "master" }));
    }

    [Fact]
    public async Task SkillTraceReplaysStructuredSubjectsAndStreamsFailures()
    {
        var stream = new EventStream();
        var available = stream.Publish("skill", "available", "Supplied, not invoked.", subject: "migration");
        var started = stream.Publish("skill", "started", "Reading.", subject: "migration");
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await using var entries = stream.Subscribe(available.Id, timeout.Token).GetAsyncEnumerator();
        Assert.True(await entries.MoveNextAsync());
        var replay = JsonSerializer.Deserialize<StudioEvent>(entries.Current.Json, StudioPaths.Json)!;
        Assert.Equal(started.Id, replay.Id);
        Assert.Equal("migration", replay.Subject);
        Assert.Equal("started", replay.State);
        Assert.Equal(JsonValueKind.Number, JsonDocument.Parse(entries.Current.Json).RootElement.GetProperty("id").ValueKind);
        stream.Publish("skill", "failed", "Diagnostics withheld.", subject: "migration");
        Assert.True(await entries.MoveNextAsync());
        var failure = JsonSerializer.Deserialize<StudioEvent>(entries.Current.Json, StudioPaths.Json)!;
        Assert.Equal("failed", failure.State);
        Assert.Equal("migration", failure.Subject);
    }

    [Fact]
    public async Task UnknownRunAndUnapprovedOriginDoNotLeakDetails()
    {
        await using var factory = new StudioFactory();
        using var client = factory.CreateClient(new() { BaseAddress = new Uri("http://localhost:5188") });
        await client.GetAsync("/api/session");
        var response = await client.GetAsync("/api/runs/does-not-exist");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        var problem = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("Migration run not found.", problem.GetProperty("detail").GetString());
        Assert.DoesNotContain("stackTrace", problem.GetRawText());
        Assert.Equal(0, factory.Runner.MigrationCalls);
    }

    [Theory]
    [InlineData(false, "needs-review")]
    [InlineData(true, "succeeded")]
    public async Task ApprovalIsSingleUseAndSuccessRequiresMeasuredVerdict(bool verified, string expectedState)
    {
        await using var factory = new StudioFactory();
        factory.Runner.Verified = verified;
        using var client = factory.CreateClient(new() { BaseAddress = new Uri("http://localhost:5188") });
        var session = await client.GetFromJsonAsync<JsonElement>("/api/session");
        client.DefaultRequestHeaders.Add("Origin", "http://localhost:5188");
        client.DefaultRequestHeaders.Add("X-CSRF-TOKEN", session.GetProperty("csrfToken").GetString());
        var created = await client.PostAsJsonAsync("/api/plans", Configuration());
        var plan = await created.Content.ReadFromJsonAsync<MigrationPlan>();
        var approval = new { confirmation = MigrationWorkflow.Confirmation, writersStopped = true };
        Assert.Equal(HttpStatusCode.Accepted, (await client.PostAsJsonAsync($"/api/plans/{plan!.Id}/run", approval)).StatusCode);
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        await foreach (var entry in factory.Services.GetRequiredService<IEventStream>().Subscribe(0, timeout.Token))
        {
            if (entry.Name != "message") continue;
            var progress = JsonSerializer.Deserialize<StudioEvent>(entry.Json, StudioPaths.Json)!;
            if (progress.RunId == plan.Id && progress.Stage == "migration" && progress.State == expectedState) break;
        }
        var run = await client.GetFromJsonAsync<MigrationRun>($"/api/runs/{plan.Id}");
        Assert.Equal(expectedState, run!.State);
        Assert.Equal(HttpStatusCode.Conflict, (await client.PostAsJsonAsync($"/api/plans/{plan.Id}/run", approval)).StatusCode);
        Assert.Equal(1, factory.Runner.MigrationCalls);
    }

    [Theory]
    [InlineData("locations", "Locations")]
    [InlineData("groups", "Groups")]
    [InlineData("servers", "Servers")]
    [InlineData("identity", "Identity")]
    public async Task AzureDiscoveryForwardsBothTenantAndSubscription(string path, string operation)
    {
        await using var factory = new StudioFactory();
        using var client = factory.CreateClient(new() { BaseAddress = new Uri("http://localhost:5188") });
        await client.GetAsync("/api/session");
        var configuration = Configuration();
        var response = await client.GetAsync($"/api/azure/{path}?tenantId={configuration.TenantId}&subscriptionId={configuration.SubscriptionId}&resourceGroup=studio-test");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(operation, factory.Runner.LastOperation);
        Assert.Equal(configuration.TenantId, factory.Runner.LastInput.GetProperty("tenantId").GetString());
        Assert.Equal(configuration.SubscriptionId, factory.Runner.LastInput.GetProperty("subscriptionId").GetString());
        Assert.Equal(HttpStatusCode.BadRequest, (await client.GetAsync($"/api/azure/{path}?subscriptionId={configuration.SubscriptionId}&resourceGroup=studio-test")).StatusCode);
        Assert.Equal(0, factory.Runner.MigrationCalls);
    }

    [Theory]
    [InlineData(false, "completed", HttpStatusCode.OK)]
    [InlineData(true, "failed", HttpStatusCode.UnprocessableEntity)]
    public async Task DiscoveryPublishesRealWizardLifecycleWithoutSensitiveInputs(bool fail, string terminal, HttpStatusCode expected)
    {
        await using var factory = new StudioFactory();
        factory.Runner.FailDiscovery = fail;
        using var client = factory.CreateClient(new() { BaseAddress = new Uri("http://localhost:5188") });
        await client.GetAsync("/api/session");
        var configuration = Configuration();
        var response = await client.GetAsync($"/api/azure/subscriptions?tenantId={configuration.TenantId}");
        Assert.Equal(expected, response.StatusCode);
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await using var entries = factory.Services.GetRequiredService<IEventStream>().Subscribe(0, timeout.Token).GetAsyncEnumerator();
        foreach (var state in new[] { "started", terminal })
        {
            Assert.True(await entries.MoveNextAsync());
            var entry = JsonSerializer.Deserialize<StudioEvent>(entries.Current.Json, StudioPaths.Json)!;
            Assert.Equal("wizard", entry.Stage);
            Assert.Equal(state, entry.State);
            Assert.Equal("Azure destination / List subscriptions", entry.Subject);
            Assert.DoesNotContain(configuration.TenantId, entries.Current.Json);
            Assert.DoesNotContain("private diagnostic", entries.Current.Json);
        }
        Assert.Equal(0, factory.Runner.MigrationCalls);
    }

    private static MigrationConfiguration Configuration() => new()
    {
        ContainerName = "sqldbcontainer", SourceDatabase = "CustomerServiceDesk",
        TenantId = "11111111-1111-1111-1111-111111111111",
        SubscriptionId = "22222222-2222-2222-2222-222222222222",
        Region = "eastus2", ResourceGroup = "studio-test", CreateResourceGroup = true,
        ServerName = "studio-test-server", CreateServer = true,
        TargetDatabase = "CustomerServiceDesk", Authentication = "Entra"
    };

    private sealed class StudioFactory : WebApplicationFactory<Program>
    {
        private readonly string state = Path.Combine(Path.GetTempPath(), "migration-studio-test-" + Guid.NewGuid().ToString("N"));
        public FakeRunner Runner { get; } = new();
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseContentRoot(Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "server")));
            builder.ConfigureAppConfiguration((_, configuration) => configuration.AddInMemoryCollection(
                new Dictionary<string, string?> { ["Studio:StateRoot"] = state }));
            builder.ConfigureServices(services =>
            {
                services.AddSingleton<IStartupFilter, LoopbackTestFilter>();
                services.RemoveAll<IOperationRunner>();
                services.AddSingleton<IOperationRunner>(Runner);
                services.RemoveAll<ICopilotGuide>();
                services.AddSingleton<ICopilotGuide, FakeCopilot>();
            });
        }
        public override async ValueTask DisposeAsync()
        {
            await base.DisposeAsync();
            if (Directory.Exists(state)) Directory.Delete(state, recursive: true);
        }

        private sealed class LoopbackTestFilter : IStartupFilter
        {
            public Action<IApplicationBuilder> Configure(Action<IApplicationBuilder> next) => app =>
            {
                app.Use((context, continuation) =>
                {
                    context.Connection.RemoteIpAddress = IPAddress.Loopback;
                    return continuation(context);
                });
                next(app);
            };
        }
    }

    private sealed class FakeRunner : IOperationRunner
    {
        public int MigrationCalls { get; private set; }
        public bool Verified { get; set; }
        public bool FailDiscovery { get; set; }
        public string? LastOperation { get; private set; }
        public JsonElement LastInput { get; private set; }
        public Task<JsonElement> RunAsync(string operation, object input, Action<JsonElement>? progress, CancellationToken token)
        {
            LastOperation = operation;
            LastInput = JsonSerializer.SerializeToElement(input, StudioPaths.Json);
            if (operation == "Migrate") MigrationCalls++;
            else if (FailDiscovery) throw new StudioException(422, "Test failure: private diagnostic");
            return Task.FromResult(JsonSerializer.SerializeToElement(new { capabilities = Array.Empty<object>(), verified = Verified }));
        }
    }

    private sealed class FakeCopilot : ICopilotGuide
    {
        private string? owner;
        private CopilotSignInState state = new(null, "idle", "Test: inference disabled.");
        public Task<CopilotStatus> StatusAsync(CancellationToken token) =>
            Task.FromResult(new CopilotStatus(false, "Test: inference disabled.", []));
        public Task<CopilotSignInState> BeginSignInAsync(string operatorId, CancellationToken token)
        {
            owner = operatorId;
            state = new("test-sign-in", "waiting", "Test authorization challenge.", "ABCD-EFGH",
                "https://github.com/login/device", DateTimeOffset.UtcNow.AddMinutes(15));
            return Task.FromResult(state);
        }
        public Task<CopilotSignInState> SignInStateAsync(string operatorId, CancellationToken token) =>
            Task.FromResult(operatorId == owner ? state : new(null, "idle", "Test: no challenge."));
        public Task<CopilotSignInState> CancelSignInAsync(string operatorId, string id, CancellationToken token)
        {
            if (owner != operatorId || state.Id != id) throw new StudioException(404, "Sign-in not found.");
            state = new(id, "cancelled", "Test cancellation.");
            return Task.FromResult(state);
        }
        public Task QueueAsync(CopilotMessageRequest request, CancellationToken token) =>
            throw new InvalidOperationException("Inference is not allowed in these tests.");
    }
}
