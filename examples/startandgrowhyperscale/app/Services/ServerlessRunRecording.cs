using System.Text.Json;
using CaldovaNetworkScheduling.Models;

namespace CaldovaNetworkScheduling.Services;

public sealed record SavedServerlessFrame(double ElapsedSeconds, ScaleSnapshot Scene, int CpuSampleCount,
    DateTimeOffset? CpuIntervalEnd, bool AwaitingCpu, long CompletedBatches);

public sealed record SavedServerlessRun(int Version, string Source, DateTimeOffset Started,
    IReadOnlyList<ServerlessCpuSample> CpuSamples, IReadOnlyList<SavedServerlessFrame> Frames);

public sealed record ServerlessRecordingSettings(string Mode, string? File, double Speed,
    SavedServerlessRun? Replay = null)
{
    public bool IsReplay => Mode == "Replay";
    public bool CaptureEnabled => Mode == "Live" && File is not null;

    public static ServerlessRecordingSettings Read(IConfiguration configuration, string contentRoot)
    {
        var mode = configuration["ServerlessRecording:Mode"] ?? "Live";
        if (mode is not ("Live" or "Replay"))
            throw new InvalidOperationException("ServerlessRecording:Mode must be Live or Replay.");
        var speed = configuration.GetValue<double?>("ServerlessRecording:Speed") ?? 2;
        if (!double.IsFinite(speed) || speed is < 0.25 or > 10)
            throw new InvalidOperationException("ServerlessRecording:Speed must be between 0.25 and 10.");
        var configuredFile = configuration["ServerlessRecording:File"];
        var file = string.IsNullOrWhiteSpace(configuredFile) ? null : Path.GetFullPath(configuredFile, contentRoot);
        if (file is not null)
        {
            var relative = Path.GetRelativePath(Path.Combine(contentRoot, "wwwroot"), file);
            if (!Path.IsPathRooted(relative) && relative != ".."
                && !relative.StartsWith($"..{Path.DirectorySeparatorChar}", StringComparison.Ordinal))
                throw new InvalidOperationException("Save serverless recordings outside wwwroot.");
            if (!file.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("ServerlessRecording:File must name a JSON file.");
            if (configuration.GetValue<bool>("Demo:Playback"))
                throw new InvalidOperationException("Saved SQL runs cannot be combined with synthetic Demo:Playback.");
        }
        if (mode == "Replay" && file is null)
            throw new InvalidOperationException("Replay requires ServerlessRecording:File from a completed live Run.");
        return new(mode, file, speed, mode == "Replay" ? ServerlessRunRecording.Load(file!) : null);
    }
}

public sealed class ServerlessRunRecording(ServerlessRecordingSettings settings, TimeProvider clock)
{
    private const int Version = 1;
    private const string Source = "sys.dm_db_resource_stats";
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) { IgnoreReadOnlyProperties = true };
    private readonly List<SavedServerlessFrame> frames = [];
    private IReadOnlyList<ServerlessCpuSample> cpuSamples = [];
    private DateTimeOffset started;
    private long? playbackStarted;
    private double position;
    private bool played;

    public bool IsReplay => settings.IsReplay;
    public bool CaptureEnabled => settings.CaptureEnabled;
    public bool IsCapturing { get; private set; }
    public bool IsPlaying => playbackStarted is not null;
    public DateTimeOffset ReplayOrigin => RequireReplay().Started;
    public double SourceSeconds => PlaybackPosition();

    public void Begin(DateTimeOffset at)
    {
        if (!CaptureEnabled) throw new InvalidOperationException("Live capture is not configured.");
        Abort();
        started = at;
        IsCapturing = true;
    }

    public void Record(DateTimeOffset at, ScaleSnapshot scene, IReadOnlyList<ServerlessCpuSample> samples,
        DateTimeOffset? intervalEnd, bool awaitingCpu, long completedBatches)
    {
        if (!IsCapturing) throw new InvalidOperationException("Start a live capture before recording frames.");
        cpuSamples = samples.ToArray();
        var seconds = (at - started).TotalSeconds;
        var frame = new SavedServerlessFrame(seconds, scene, samples.Count, intervalEnd, awaitingCpu, completedBatches);
        if (frames.Count > 0 && seconds <= frames[^1].ElapsedSeconds) frames[^1] = frame;
        else frames.Add(frame);
    }

    public void Abort()
    {
        IsCapturing = false;
        frames.Clear();
        cpuSamples = [];
    }

    public async Task SaveAsync(CancellationToken token)
    {
        if (!IsCapturing) throw new InvalidOperationException("There is no live capture to save.");
        var saved = new SavedServerlessRun(Version, Source, started, cpuSamples.ToArray(), frames.ToArray());
        Validate(saved);
        IsCapturing = false;
        var file = settings.File ?? throw new InvalidOperationException("Capture file is not configured.");
        var temporary = $"{file}.{Guid.NewGuid():N}.tmp";
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        try
        {
            await using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                65536, FileOptions.Asynchronous))
            {
                await JsonSerializer.SerializeAsync(stream, saved, Json, token);
                await stream.FlushAsync(token);
            }
            if (new FileInfo(temporary).Length > 32 * 1024 * 1024)
                throw new InvalidDataException("Saved serverless run exceeds the 32 MiB limit.");
            token.ThrowIfCancellationRequested();
            File.Move(temporary, file, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    public static SavedServerlessRun Load(string file)
    {
        if (new FileInfo(file).Length > 32 * 1024 * 1024)
            throw new InvalidDataException("Saved serverless run exceeds the 32 MiB limit.");
        var saved = JsonSerializer.Deserialize<SavedServerlessRun>(File.ReadAllText(file), Json)
            ?? throw new InvalidDataException("Saved serverless run is empty.");
        Validate(saved);
        return saved;
    }

    private static void Validate(SavedServerlessRun saved)
    {
        if (saved.Version != Version || saved.Source != Source || saved.Started == default
            || saved.CpuSamples is null || saved.CpuSamples.Count is < 1 or > 7200
            || saved.Frames is null || saved.Frames.Count is < 2 or > 7200)
            throw new InvalidDataException("A version-1 completed SQL DMV run with CPU samples and frames is required.");
        DateTimeOffset? previousSample = null;
        foreach (var sample in saved.CpuSamples)
        {
            if (sample is null || sample.At < saved.Started || previousSample >= sample.At)
                throw new InvalidDataException("Saved CPU samples must retain increasing source timestamps.");
            _ = sample.UsedVCores;
            previousSample = sample.At;
        }
        double previousSeconds = -1;
        var previousCount = 0;
        foreach (var frame in saved.Frames)
        {
            if (frame is null || !double.IsFinite(frame.ElapsedSeconds) || frame.ElapsedSeconds < 0
                || frame.ElapsedSeconds <= previousSeconds || frame.ElapsedSeconds > 3600
                || frame.CpuSampleCount < previousCount || frame.CpuSampleCount > saved.CpuSamples.Count
                || frame.Scene is not { Samples: not null, Users: not null, Activity: not null } scene
                || scene.Samples.Count != frame.CpuSampleCount || scene.ActiveUsers != scene.Users.Count
                || !double.IsFinite(scene.MinVCores) || !double.IsFinite(scene.MaxVCores)
                || scene.MinVCores < 0 || scene.MaxVCores < scene.MinVCores || scene.MaxVCores <= 0
                || !double.IsFinite(scene.TotalScriptSeconds) || scene.TotalScriptSeconds <= 0
                || !double.IsFinite(scene.VCores) || scene.VCores < 0 || frame.CompletedBatches < 0)
                throw new InvalidDataException("Saved serverless frame has invalid timing, staff, or CPU data.");
            for (var i = 0; i < frame.CpuSampleCount; i++)
            {
                var sample = saved.CpuSamples[i];
                var point = scene.Samples[i];
                if (point is null || point.VCores != sample.UsedVCores
                    || point.ScriptSeconds != (sample.At - saved.Started).TotalSeconds)
                    throw new InvalidDataException("Saved chart points must match the original CPU samples and timestamps.");
            }
            if (frame.CpuIntervalEnd is { } end
                && (frame.CpuSampleCount == 0 || end != saved.CpuSamples[frame.CpuSampleCount - 1].At))
                throw new InvalidDataException("Saved staff frame must refer to its displayed CPU interval.");
            previousSeconds = frame.ElapsedSeconds;
            previousCount = frame.CpuSampleCount;
        }
        if (!saved.Frames[^1].Scene.IsComplete || previousCount != saved.CpuSamples.Count)
            throw new InvalidDataException("Only a completed live Run can be replayed. Stopped or failed runs are not saved.");
    }

    public void Play()
    {
        var saved = RequireReplay();
        if (PlaybackPosition() >= saved.Frames[^1].ElapsedSeconds) Reset();
        played = true;
        playbackStarted ??= clock.GetTimestamp();
    }

    public void Pause()
    {
        position = PlaybackPosition();
        playbackStarted = null;
    }

    public void Reset()
    {
        RequireReplay();
        playbackStarted = null;
        position = 0;
        played = false;
    }

    public SavedServerlessFrame GetReplayFrame()
    {
        var saved = RequireReplay();
        var seconds = PlaybackPosition();
        var frame = saved.Frames[0];
        var previousStaff = 0;
        foreach (var candidate in saved.Frames)
        {
            if (candidate.ElapsedSeconds > seconds) break;
            if (candidate.Scene.ActiveUsers != frame.Scene.ActiveUsers) previousStaff = frame.Scene.ActiveUsers;
            frame = candidate;
        }
        var complete = played && seconds >= saved.Frames[^1].ElapsedSeconds;
        var scene = frame.CpuSampleCount == 0 ? MeasuredClinicScene.InitialView(frame.Scene) : frame.Scene;
        return frame with
        {
            Scene = scene with
            {
                IsRunning = IsPlaying,
                IsComplete = complete,
                StatusDetail = !played ? "Press Run to start the day."
                    : complete && scene.VCores == 0 ? "Everyone has signed out"
                    : frame.CpuSampleCount == 0 ? "Staff signing in"
                    : MeasuredClinicScene.DescribeStaff(scene.ActiveUsers, previousStaff,
                        saved.Frames.Max(f => f.Scene.PeakUsers), scene.VCores),
            },
            AwaitingCpu = played && frame.AwaitingCpu,
        };
    }

    public IReadOnlyList<ServerlessCpuSample> ReplaySamples(int count) =>
        RequireReplay().CpuSamples.Take(count).ToArray();

    private double PlaybackPosition()
    {
        var saved = RequireReplay();
        var seconds = position + (playbackStarted is { } timestamp
            ? clock.GetElapsedTime(timestamp).TotalSeconds * settings.Speed : 0);
        var end = saved.Frames[^1].ElapsedSeconds;
        if (seconds >= end)
        {
            position = end;
            playbackStarted = null;
            return end;
        }
        return seconds;
    }

    private SavedServerlessRun RequireReplay() => settings.Replay
        ?? throw new InvalidOperationException("No saved serverless run is loaded for replay.");
}
