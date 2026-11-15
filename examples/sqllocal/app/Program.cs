using Caldova.TransferCenter.Data;
using Caldova.TransferCenter.Models;
using Microsoft.Data.SqlClient;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddProblemDetails();
builder.Services.AddScoped<CaldovaRepository>();

var app = builder.Build();

app.UseExceptionHandler();
app.UseDefaultFiles();
app.UseStaticFiles();

app.MapGet("/api/health", async (CaldovaRepository repository, CancellationToken cancellationToken) =>
	Results.Ok(await repository.GetHealthAsync(cancellationToken)));

app.MapGet("/api/transfers", async (CaldovaRepository repository, CancellationToken cancellationToken) =>
	Results.Ok(await repository.GetTransfersAsync(cancellationToken)));

app.MapGet("/api/transfers/{transferNumber}", async (
	string transferNumber,
	CaldovaRepository repository,
	CancellationToken cancellationToken) =>
{
	var detail = await repository.GetTransferDetailAsync(transferNumber, cancellationToken);
	return detail is null ? Results.NotFound() : Results.Ok(detail);
});

app.MapGet("/api/transfers/{transferNumber}/audit", async (
    string transferNumber,
    CaldovaRepository repository,
    CancellationToken cancellationToken) =>
{
    if (transferNumber.Length > 30)
        return Results.Problem(statusCode: 400, title: "Invalid transfer number",
            detail: "Use a transfer number up to 30 characters.");
    return Results.Ok(await repository.GetAuditHistoryAsync(transferNumber, cancellationToken));
});

app.MapPost("/api/transfers/{transferNumber}/briefings", async (
	string transferNumber,
	HttpRequest httpRequest,
	CaldovaRepository repository,
	ILogger<CaldovaRepository> logger,
	CancellationToken cancellationToken) =>
{
	BriefingRequest? request = null;
	using var bodyReader = new StreamReader(httpRequest.Body, leaveOpen: true);
	var body = await bodyReader.ReadToEndAsync(cancellationToken);
	if (!string.IsNullOrWhiteSpace(body))
	{
		if (!httpRequest.HasJsonContentType())
			return Results.Problem(statusCode: 415, title: "JSON briefing options required",
				detail: "Send briefing options as application/json, or omit the body for a current-facts-only briefing.");
		try
		{
			request = JsonSerializer.Deserialize<BriefingRequest>(body, JsonSerializerOptions.Web);
		}
		catch (JsonException)
		{
			return Results.Problem(statusCode: 400, title: "Invalid briefing options JSON",
				detail: "Provide includeHistory as a boolean or historicalNotes as an array of note IDs and source versions.");
		}
	}
	var notes = request?.HistoricalNotes;
	if (transferNumber.Length > 30 || notes is { Count: > 3 }
		|| (request?.IncludeHistory == true && notes is { Count: > 0 })
		|| (notes is not null && (notes.Any(note => note is null || note.HistoricalNoteId <= 0
			|| string.IsNullOrWhiteSpace(note.SourceVersion) || note.SourceVersion.Length != 18)
			|| notes.Select(note => note.HistoricalNoteId).Distinct().Count() != notes.Count)))
		return Results.Problem(statusCode: 400, title: "Invalid historical selection",
			detail: "Use includeHistory to retrieve the top three notes, or provide up to three distinct note IDs and source versions; do not combine both.");
	try
	{
		return Results.Ok(await repository.GenerateBriefingAsync(transferNumber, request, cancellationToken));
	}
	catch (SqlException exception) when (exception.Number is 42227 or 50046 or 50047 or 50050 or 50051)
	{
		logger.LogWarning(exception, "Briefing generation rejected for transfer {TransferNumber}", transferNumber);
		return Results.Problem(statusCode: exception.Number == 50046 ? 404 : exception.Number == 50050 ? 400 : 409,
			title: "Briefing generation unavailable", detail: exception.Message);
	}
});

app.MapPost("/api/transfers/{transferNumber}/history-search", async (
	string transferNumber,
	HistorySearchRequest request,
	CaldovaRepository repository,
	ILogger<CaldovaRepository> logger,
	CancellationToken cancellationToken) =>
{
	if (transferNumber.Length > 30 || string.IsNullOrWhiteSpace(request.Query)
		|| request.Query.Length > 4000 || request.TopK is < 1 or > 20)
	{
		return Results.Problem(statusCode: 400, title: "Invalid history search",
			detail: "Use a transfer number up to 30 characters, a query of 1 to 4000 characters, and TopK from 1 to 20.");
	}
	try
	{
		return Results.Ok(await repository.SearchHistoryAsync(transferNumber, request, cancellationToken));
	}
	catch (SqlException exception) when (exception.Number is 42227 or 50046 or 50047)
	{
		logger.LogWarning(exception, "History search unavailable for transfer {TransferNumber}", transferNumber);
		return Results.Problem(statusCode: exception.Number == 50046 ? 404 : 409,
			title: "History search unavailable", detail: exception.Message);
	}
});

app.MapFallbackToFile("index.html");

app.Run();
