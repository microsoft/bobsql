using System.ComponentModel.DataAnnotations;
using CustomerServiceDesk.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace CustomerServiceDesk.Pages;

public class IndexModel(DeskRepository desk) : PageModel
{
    [BindProperty(SupportsGet = true), AllowedValues(null, "Open", "InProgress", "Resolved")]
    public string? Status { get; set; }

    [BindProperty(SupportsGet = true), AllowedValues(null, "web", "phone", "chat")]
    public string? Channel { get; set; }

    public List<CaseRow> Cases { get; private set; } = [];
    public DeskEnvironment State { get; private set; } = null!;

    public async Task<IActionResult> OnGetAsync(CancellationToken token)
    {
        State = await desk.GetEnvironmentAsync(token);
        if (!ModelState.IsValid)
        {
            Response.StatusCode = 400;
            return Page();
        }
        Cases = await desk.GetCasesAsync(Status, Channel, token);
        return Page();
    }
}
