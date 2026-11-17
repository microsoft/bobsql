namespace CaldovaNetworkScheduling.Models;

public sealed record ProviderDemoProfile(string Key, string Name, string Role, string Database, string Compute,
    int Patients, int Staff, int Departments, string Capabilities);

public static class ProviderProfiles
{
    public static IReadOnlyList<ProviderDemoProfile> All { get; } =
    [
        new("caldova", "Caldova Health", "Acquirer", "caldova-scheduling", "Hyperscale serverless · 1-8 vCores",
            24000, 180, 5, "Primary care, pediatrics, dermatology, cardiology, and orthopedics"),
        new("northbrook", "Northbrook Family Clinics", "Acquired · primary care and pediatrics", "northbrook-scheduling", "Provisioned Hyperscale · 2 vCores",
            6000, 45, 3, "Primary care, pediatrics, and dermatology"),
        new("ridgeview", "Ridgeview Specialty Care", "Acquired · cardiology and orthopedics", "ridgeview-scheduling", "Provisioned Hyperscale · 4 vCores",
            12000, 90, 3, "Cardiology, orthopedics, and dermatology"),
    ];
}
