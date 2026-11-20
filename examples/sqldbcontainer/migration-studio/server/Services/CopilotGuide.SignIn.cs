using GitHub.Copilot;
using GitHub.Copilot.Rpc;

namespace MigrationStudio.Services;

#pragma warning disable GHCP001
public sealed partial class CopilotGuide
{
    private SignInAttempt? signInAttempt;
    private Task? signInTask;

    private sealed class SignInAttempt(
        string owner, string flowId, CopilotSession runtime, CopilotSignInState state,
        CancellationTokenSource cancellation)
    {
        public string Owner { get; } = owner;
        public string FlowId { get; } = flowId;
        public CopilotSession Runtime { get; } = runtime;
        public CopilotSignInState State { get; set; } = state;
        public CancellationTokenSource Cancellation { get; } = cancellation;
    }

    public async Task<CopilotSignInState> BeginSignInAsync(string owner, CancellationToken token)
    {
        var status = await StatusAsync(token);
        await connectionGate.WaitAsync(token);
        try
        {
            if (signInTask is { IsCompleted: false })
            {
                if (signInAttempt!.Owner != owner)
                    throw new StudioException(409, "Another local browser session is connecting Copilot. Finish or cancel it there first.");
                return signInAttempt.State;
            }
            if (status.Authenticated)
                return new(null, "connected", status.Status);
            if (client is null)
                throw new StudioException(503, status.Status);
            if (Volatile.Read(ref busy) != 0)
                throw new StudioException(409, "Wait for the current Copilot response before signing in.");
            signInAttempt?.Cancellation.Dispose();
            signInAttempt = null;

            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
            timeout.CancelAfter(TimeSpan.FromSeconds(45));
            var runtime = await client.CreateSessionAsync(
                CopilotRuntime.RestrictedSession(paths.AgentWorkspace, []), timeout.Token);
            try
            {
                var begun = await runtime.Rpc.Accounts.Login.BeginAsync(new AuthLoginBeginRequest
                {
                    Kind = LoginProviderKind.GitHubDotCom,
                    Method = AuthLoginMethod.DeviceCode
                }, timeout.Token);
                if (begun.Step is not AuthLoginStepDeviceCode device)
                {
                    await runtime.Rpc.Accounts.Login.CancelAsync(begun.FlowId, timeout.Token);
                    throw new StudioException(502, "The Copilot runtime did not offer GitHub device sign-in. No credentials were collected. Try connecting again.");
                }
                var state = DeviceChallenge(device);
                var cancellation = new CancellationTokenSource(state.ExpiresAt!.Value - DateTimeOffset.UtcNow);
                signInAttempt = new(owner, begun.FlowId, runtime, state, cancellation);
                signInTask = FinishSignInAsync(signInAttempt);
                return state;
            }
            catch
            {
                await runtime.DisposeAsync();
                throw;
            }
        }
        catch (Exception exception) when (exception is not StudioException && !token.IsCancellationRequested)
        {
            logger.LogWarning("Copilot sign-in start failed with {ExceptionType}; authorization details withheld.", exception.GetType().Name);
            throw new StudioException(502, "Copilot sign-in could not start. Check the local runtime and network, then try Connect Copilot again.");
        }
        finally { connectionGate.Release(); }
    }

    public async Task<CopilotSignInState> SignInStateAsync(string owner, CancellationToken token)
    {
        await connectionGate.WaitAsync(token);
        try
        {
            return signInAttempt is { } attempt && attempt.Owner == owner
                ? attempt.State : new(null, "idle", "Connect Copilot to sign in to GitHub. Azure sign-in is separate.");
        }
        finally { connectionGate.Release(); }
    }

    public async Task<CopilotSignInState> CancelSignInAsync(string owner, string id, CancellationToken token)
    {
        Task? completion;
        await connectionGate.WaitAsync(token);
        try
        {
            if (signInAttempt is not { } attempt || attempt.Owner != owner || attempt.State.Id != id)
                throw new StudioException(404, "Copilot sign-in attempt not found in this browser session.");
            if (attempt.State.State != "waiting") return attempt.State;
            attempt.State = new(id, "cancelled", "Copilot sign-in cancelled. No inference or Azure operation was requested.");
            attempt.Cancellation.Cancel();
            completion = signInTask;
        }
        finally { connectionGate.Release(); }
        if (completion is not null) await completion.WaitAsync(token);
        return await SignInStateAsync(owner, token);
    }

    public static CopilotSignInState DeviceChallenge(AuthLoginStepDeviceCode device)
    {
        if (!Uri.TryCreate(device.VerificationUri, UriKind.Absolute, out var uri)
            || uri.Scheme != "https" || uri.Host != "github.com" || !uri.IsDefaultPort
            || uri.AbsolutePath.TrimEnd('/') != "/login/device" || uri.UserInfo.Length != 0
            || uri.Query.Length != 0 || uri.Fragment.Length != 0
            || string.IsNullOrWhiteSpace(device.UserCode) || device.UserCode.Length > 64
            || device.ExpiresIn <= 0 || device.ExpiresIn > 1800)
            throw new StudioException(502, "The Copilot runtime returned an unsupported sign-in challenge. No verification link was opened.");
        return new(Guid.NewGuid().ToString("N"), "waiting",
            "Enter this one-time code on GitHub and authorize Copilot. Waiting for GitHub confirmation.",
            device.UserCode, uri.AbsoluteUri, DateTimeOffset.UtcNow.AddSeconds(device.ExpiresIn));
    }

    private async Task FinishSignInAsync(SignInAttempt attempt)
    {
        var completed = false;
        try
        {
            await AwaitAuthorizationAsync(
                token => attempt.Runtime.Rpc.Accounts.Login.AdvanceAsync(attempt.FlowId, cancellationToken: token),
                TimeSpan.FromSeconds(1), attempt.Cancellation.Token);
            completed = true;
            await connectionGate.WaitAsync(attempt.Cancellation.Token);
            try { lastStatus = null; }
            finally { connectionGate.Release(); }
            var status = await StatusAsync(attempt.Cancellation.Token);
            await SetSignInStateAsync(attempt, status.Authenticated ? "connected" : "failed",
                status.Authenticated
                    ? "Copilot connected. Authentication and model discovery succeeded; no inference was requested. You can now start the guide."
                    : status.Status);
        }
        catch (OperationCanceledException) when (attempt.Cancellation.IsCancellationRequested)
        {
            await SetSignInStateAsync(attempt, "expired", "Copilot sign-in expired or the host stopped. Connect again to get a new code.");
        }
        catch (Exception exception)
        {
            logger.LogWarning("Copilot sign-in failed with {ExceptionType}. {SafeReason}",
                exception.GetType().Name, exception is StudioException safeReason
                    ? safeReason.Message : "Authorization details withheld.");
            await SetSignInStateAsync(attempt, "failed", exception is StudioException safe
                ? safe.Message : "Copilot sign-in failed. Check your GitHub Copilot access and network, then connect again.");
        }
        finally
        {
            try
            {
                if (!completed)
                {
                    using var cleanup = new CancellationTokenSource(TimeSpan.FromSeconds(10));
                    await attempt.Runtime.Rpc.Accounts.Login.CancelAsync(attempt.FlowId, cleanup.Token);
                }
                await attempt.Runtime.DisposeAsync();
            }
            catch (Exception exception)
            {
                logger.LogWarning("Copilot sign-in cleanup failed with {ExceptionType}; authorization details withheld.", exception.GetType().Name);
                await SetSignInStateAsync(attempt, "failed", "The local runtime could not confirm sign-in cleanup. The GitHub code will expire; check connection before trying again.", replaceCancelled: true);
            }
        }
    }

    public static async Task AwaitAuthorizationAsync(
        Func<CancellationToken, Task<AuthLoginStep>> advance, TimeSpan interval, CancellationToken token)
    {
        while (true)
        {
            token.ThrowIfCancellationRequested();
            var step = await advance(token);
            if (step is AuthLoginStepAwaiting)
            {
                await Task.Delay(interval, token);
                continue;
            }
            if (step is AuthLoginStepCompleted completed)
            {
                var status = completed.Result.Status;
                if (status == AuthLoginResultStatus.Completed) return;
                if (status == AuthLoginResultStatus.NeedsPlaintextConsent)
                    throw new StudioException(502,
                        "GitHub authorization reached the SDK, but it requires consent to plaintext local token storage (needs-plaintext-consent). The app has not approved that storage. Repeating GitHub sign-in alone will not resolve this.");
                if (status == AuthLoginResultStatus.NeedsAccountSelection)
                    throw new StudioException(502,
                        "GitHub authorization reached the SDK, but it requires account selection (needs-account-selection). The app has not selected an account automatically. Repeating GitHub sign-in alone will not resolve this.");
                if (status == AuthLoginResultStatus.Declined)
                    throw new StudioException(502, "The SDK reported that sign-in was declined (declined). No connection was assumed.");
                throw new StudioException(502, "The SDK returned an unsupported authorization result. No connection was assumed.");
            }
            if (step is AuthLoginStepError)
                throw new StudioException(502, "The SDK returned an authorization error (error). Authentication was not confirmed; raw authorization details are withheld.");
            if (step is AuthLoginStepNeedsInteraction)
                throw new StudioException(502, "The SDK requested additional native interaction (needs-interaction). Authentication was not confirmed.");
            if (step is AuthLoginStepInputRequired)
                throw new StudioException(502, "The SDK requested additional input (input-required). The app did not supply a default.");
            throw new StudioException(502, "The SDK returned an unsupported sign-in step. No connection was assumed.");
        }
    }

    private async Task SetSignInStateAsync(SignInAttempt attempt, string state, string message, bool replaceCancelled = false)
    {
        await connectionGate.WaitAsync();
        try
        {
            if (attempt.State.State != "cancelled" || replaceCancelled)
                attempt.State = new(attempt.State.Id, state, message);
        }
        finally { connectionGate.Release(); }
    }
}
#pragma warning restore GHCP001
