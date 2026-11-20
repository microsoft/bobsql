using System.Text.Json;
using CustomerServiceDesk.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.Data.SqlClient;

namespace CustomerServiceDesk.Pages.Cases;

public class DetailsModel(DeskRepository desk) : PageModel
{
    public CaseDetail Case { get; private set; } = null!;
    public string FormattedDetails { get; private set; } = "";

    public async Task<IActionResult> OnGetAsync(int id, CancellationToken token)
    {
        try
        {
            Case = await desk.GetCaseAsync(id, token);
        }
        catch (SqlException exception) when (exception.Number == 51101)
        {
            return NotFound();
        }
        using var details = JsonDocument.Parse(Case.Details);
        FormattedDetails = JsonSerializer.Serialize(details.RootElement, new JsonSerializerOptions { WriteIndented = true });
        return Page();
    }
}
