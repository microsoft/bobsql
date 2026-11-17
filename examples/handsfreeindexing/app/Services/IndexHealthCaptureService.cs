namespace CaldovaPatientAccessOps.Services;

public sealed class IndexHealthCaptureService(
    IServiceScopeFactory scopeFactory,
    IConfiguration configuration,
    ILogger<IndexHealthCaptureService> logger) : BackgroundService
{
    private readonly TimeSpan interval = TimeSpan.FromSeconds(
        Math.Max(5, configuration.GetValue("IndexHealthCapture:IntervalSeconds", 10)));

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(interval);
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = scopeFactory.CreateScope();
                var dataService = scope.ServiceProvider.GetRequiredService<IOperationsDataService>();
                if (await dataService.IsReadyAsync(stoppingToken))
                {
                    var controlState = await dataService.GetDemoControlStateAsync(stoppingToken);
                    if (controlState.Phase == "Compaction Running")
                    {
                        await dataService.GetDashboardDataAsync(42, DateTime.UtcNow.AddDays(-365), stoppingToken);
                        await dataService.CaptureIndexHealthAsync(stoppingToken);
                    }
                }
            }
            catch (Exception exception) when (exception is not OperationCanceledException)
            {
                logger.LogWarning(exception, "Index health capture failed; the next interval will retry.");
            }

            if (!await timer.WaitForNextTickAsync(stoppingToken))
            {
                break;
            }
        }
    }
}