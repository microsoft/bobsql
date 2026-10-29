using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using WardGeneral.Data;

namespace WardGeneral.Agent;

internal sealed class ActingProviderHandler(AccessContext access) : DelegatingHandler(new HttpClientHandler())
{
    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var claims = new[]
        {
            new { typ = "ProviderId", val = access.ProviderId?.ToString() ?? string.Empty },
            new { typ = "Role", val = access.Role }
        };
        var principal = new
        {
            auth_typ = "Area8Simulator",
            name_typ = "ProviderId",
            role_typ = "Role",
            claims
        };
        var json = JsonSerializer.Serialize(principal);
        var header = Convert.ToBase64String(Encoding.UTF8.GetBytes(json));

        request.Headers.Remove("X-MS-CLIENT-PRINCIPAL");
        request.Headers.TryAddWithoutValidation("X-MS-CLIENT-PRINCIPAL", header);
        return base.SendAsync(request, cancellationToken);
    }
}