using System.ComponentModel.DataAnnotations;
using CustomerServiceDesk.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.Data.SqlClient;

namespace CustomerServiceDesk.Pages.Cases;

public class EditModel(DeskRepository desk) : PageModel
{
    [BindProperty]
    public CaseInput Input { get; set; } = new();

    [BindProperty, Required]
    public string Version { get; set; } = "";

    public async Task<IActionResult> OnGetAsync(int id, CancellationToken token)
    {
        CaseDetail item;
        try
        {
            item = await desk.GetCaseAsync(id, token);
        }
        catch (SqlException exception) when (exception.Number == 51101)
        {
            return NotFound();
        }
        Input = new CaseInput { Title = item.Title, Description = item.Description,
            Resolution = item.Resolution, Topic = item.Topic, Status = item.Status,
            Priority = item.Priority, Details = item.Details };
        Version = Convert.ToBase64String(item.Version);
        return Page();
    }

    public async Task<IActionResult> OnPostAsync(int id, CancellationToken token)
    {
        byte[] version = [];
        if (ModelState.IsValid)
        {
            try
            {
                version = Convert.FromBase64String(Version);
                if (version.Length != 8)
                    ModelState.AddModelError(nameof(Version), "Invalid case version. Reload the case before saving.");
            }
            catch (FormatException)
            {
                ModelState.AddModelError(nameof(Version), "Invalid case version. Reload the case before saving.");
            }
        }
        if (ModelState.IsValid)
        {
            try
            {
                await desk.UpdateAsync(id, version, Input, token);
                TempData["Notice"] = "Case saved. Searchable text changes require an embedding refresh; status and JSON-only changes do not.";
                return RedirectToPage("/Cases/Details", new { id });
            }
            catch (SqlException exception) when (exception.Number is 51100 or 51103)
            {
                ModelState.AddModelError("", exception.Message);
                Response.StatusCode = exception.Number == 51103 ? 409 : 400;
                return Page();
            }
        }
        Response.StatusCode = 400;
        return Page();
    }
}
