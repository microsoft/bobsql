using System.Reflection;
using CustomerServiceDesk.Data;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace CustomerServiceDesk.Pages;

public class EnvironmentModel(DeskRepository desk, IConfiguration configuration) : PageModel
{
    public DeskEnvironment State { get; private set; } = null!;
    public string DeploymentLabel => configuration["Desk:DeploymentLabel"] ?? "Not configured";
    public string BuildId => typeof(EnvironmentModel).Assembly
        .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "Unknown";
    public async Task OnGetAsync(CancellationToken token) => State = await desk.GetEnvironmentAsync(token);
}
