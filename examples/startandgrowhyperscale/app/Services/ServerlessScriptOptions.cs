namespace CaldovaNetworkScheduling.Services;

public sealed class ServerlessScriptOptions
{
    public string DatabaseName { get; set; } = "caldova-scheduling";
    public string ServiceObjective { get; set; } = "HS_S_Gen5_8";
    public double MinVCores { get; set; } = 1;
    public double MaxVCores { get; set; } = 8;
    public int PeakUsers { get; set; } = 24;
    public double VCoresPerUser { get; set; } = 0.125;
    public int AutoPauseDelayMinutes { get; set; } = 60;
}
