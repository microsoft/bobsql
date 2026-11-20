using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;

namespace MigrationStudio.Middleware;

public sealed class ApiExceptionHandler(ILogger<ApiExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext context, Exception exception, CancellationToken token)
    {
        var (status, detail) = exception switch
        {
            StudioException known => (known.StatusCode, known.Message),
            ValidationException => (400, "The selected migration configuration is invalid."),
            BadHttpRequestException => (400, "The request body or parameters are invalid."),
            OperationCanceledException => (408, "The operation was cancelled or timed out."),
            _ => (500, "An unexpected host error occurred. No migration success was assumed.")
        };
        logger.LogWarning("API {Method} {Path} failed with {ExceptionType}, HTTP {Status}. Sensitive exception details withheld.",
            context.Request.Method, context.Request.Path, exception.GetType().Name, status);
        context.Response.StatusCode = status;
        await context.Response.WriteAsJsonAsync(new ProblemDetails
        {
            Status = status, Title = status >= 500 ? "Operation unavailable" : "Operation not permitted",
            Detail = detail, Instance = context.Request.Path
        }, token);
        return true;
    }
}
