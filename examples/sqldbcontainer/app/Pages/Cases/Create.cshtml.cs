using System.ComponentModel.DataAnnotations;
using CustomerServiceDesk.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.Data.SqlClient;

namespace CustomerServiceDesk.Pages.Cases;

public class CreateModel(DeskRepository desk) : PageModel
{
    [BindProperty]
    public CaseInput Input { get; set; } = new();

    [BindProperty, Range(1, int.MaxValue, ErrorMessage = "Choose a synthetic customer.")]
    public int CustomerId { get; set; }

    public List<CustomerOption> Customers { get; private set; } = [];

    public async Task OnGetAsync(CancellationToken token) => Customers = await desk.GetCustomersAsync(token);

    public async Task<IActionResult> OnPostAsync(CancellationToken token)
    {
        if (ModelState.IsValid)
        {
            try
            {
                var id = await desk.CreateAsync(CustomerId, Input, token);
                TempData["Notice"] = "Case created. Run the embedding refresh before semantic search; no model was invoked by this save.";
                return RedirectToPage("/Cases/Details", new { id });
            }
            catch (SqlException exception) when (exception.Number == 51100)
            {
                ModelState.AddModelError("", exception.Message);
            }
        }
        Customers = await desk.GetCustomersAsync(token);
        Response.StatusCode = 400;
        return Page();
    }
}
