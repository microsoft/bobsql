using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using CustomerServiceDesk.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.Data.SqlClient;

namespace CustomerServiceDesk.Pages;

public class SearchModel(DeskRepository desk, OllamaEmbeddings embeddings, ILogger<SearchModel> logger) : PageModel
{
    [BindProperty(SupportsGet = true)]
    public int? QueryId { get; set; }
    [BindProperty, Required, StringLength(1000)]
    public string? QueryText { get; set; }
    public List<PreparedSearch> Searches { get; private set; } = [];
    public List<SearchHit> Hits { get; private set; } = [];
    public DeskEnvironment State { get; private set; } = null!;
    public string? SearchError { get; private set; }
    public string? SearchedText { get; private set; }
    public bool IsLiveSearch { get; private set; }

    public async Task<IActionResult> OnGetAsync(CancellationToken token)
    {
        State = await desk.GetEnvironmentAsync(token);
        Searches = await desk.GetPreparedSearchesAsync(token);
        if (!ModelState.IsValid || QueryId is not null && !Searches.Any(s => s.PreparedSearchId == QueryId))
            return BadRequest("Choose a valid prepared search.");
        if (QueryId is null)
            return Page();
        SearchedText = Searches.Single(s => s.PreparedSearchId == QueryId).SearchText;
        QueryText = SearchedText;
        try
        {
            Hits = await desk.SearchAsync(QueryId.Value, token);
        }
        catch (SqlException exception) when (exception.Number == 51102)
        {
            logger.LogWarning("Prepared search {SearchId} rejected because embeddings are missing or stale.", QueryId);
            SearchError = "Search is unavailable because embeddings are missing or stale. Refresh them using build-database.ps1, then retry. No substitute results were returned.";
            Response.StatusCode = 409;
        }
        return Page();
    }

    public async Task<IActionResult> OnPostAsync(CancellationToken token)
    {
        State = await desk.GetEnvironmentAsync(token);
        Searches = await desk.GetPreparedSearchesAsync(token);
        if (!ModelState.IsValid)
        {
            Response.StatusCode = 400;
            return Page();
        }
        SearchedText = QueryText!.Trim();
        var prepared = Searches.SingleOrDefault(search => search.SearchText == SearchedText);
        IsLiveSearch = prepared is null;
        if (!State.SearchReady)
        {
            SearchError = "Embeddings are missing or stale. Run build-database.ps1 before searching. No substitute results were returned.";
            Response.StatusCode = 409;
            return Page();
        }
        try
        {
            if (prepared is not null)
            {
                Hits = await desk.SearchAsync(prepared.PreparedSearchId, token);
            }
            else
            {
                var profile = await desk.GetSearchProfileAsync(token)
                    ?? throw new EmbeddingUnavailableException("No embedding profile is active. Run build-database.ps1.");
                var vector = await embeddings.EmbedQueryAsync(profile, SearchedText, token);
                Hits = await desk.SearchLiveAsync(profile, vector, token);
            }
        }
        catch (SqlException exception) when (exception.Number == 51102)
        {
            logger.LogWarning("Search rejected because the active profile changed or embeddings are stale.");
            SearchError = "The active profile changed or case embeddings are stale. Check Environment, refresh embeddings if needed, and retry. No substitute results were returned.";
            Response.StatusCode = 409;
        }
        catch (EmbeddingUnavailableException exception)
        {
            logger.LogWarning("Live embedding validation failed: {Reason}", exception.Message);
            SearchError = exception.Message;
            Response.StatusCode = 503;
        }
        catch (Exception exception) when (exception is HttpRequestException or JsonException
            || exception is OperationCanceledException && !token.IsCancellationRequested)
        {
            logger.LogWarning("Local Ollama request failed ({FailureType}).", exception.GetType().Name);
            SearchError = "Ollama could not generate a valid query embedding within 60 seconds. Check the local service and matching model, then retry. No prepared query or fallback results were substituted.";
            Response.StatusCode = 503;
        }
        return Page();
    }
}
