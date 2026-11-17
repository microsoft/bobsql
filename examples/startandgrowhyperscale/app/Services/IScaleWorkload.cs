using CaldovaNetworkScheduling.Models;

namespace CaldovaNetworkScheduling.Services;

/// <summary>
/// Drives the serverless scale scene. The scripted implementation animates a fixed
/// clinic morning; a measured implementation will run real sessions and read telemetry.
/// </summary>
public interface IScaleWorkload
{
    event Action? Changed;
    string Mode { get; }
    ScaleSnapshot GetSnapshot();
    void Play();
    void Pause();
    void Reset();
}
