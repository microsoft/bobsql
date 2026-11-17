using CaldovaNetworkScheduling.Models;
using Microsoft.Extensions.Options;

namespace CaldovaNetworkScheduling.Services;

/// <summary>
/// Deterministic, scripted clinic day for the serverless scene (about 70 seconds).
/// One script second normally equals six simulated minutes, so the documented 60-minute
/// Hyperscale auto-pause delay plays out in 10 seconds. While the database resumes the
/// clock slows to 15 simulated seconds per script second, so the resume reads as well
/// under the documented "generally less than one minute". Nothing here touches a database.
/// </summary>
public sealed class ScriptedScaleWorkload : IScaleWorkload, IDisposable
{
    private const double TickSeconds = 0.25;
    private const double SimMinutesPerScriptSecond = 6;
    private const double ResumeSimMinutesPerScriptSecond = 0.25;
    private const double OpenSeconds = 1;
    private const double RampUpSeconds = 20;
    private const double HoldSeconds = 10;
    private const double RampDownSeconds = 15;
    private const double PausedHoldSeconds = 4;
    private const double ResumeSeconds = 3;
    private const int AfternoonUsers = 6;
    private const double AfternoonJoinSeconds = 0.5;
    private const double AfternoonSeconds = 6;
    private const double VCoreResponseSeconds = 0.15;
    // Serverless vCore values in the Hyperscale resource-limits table fall on 0.25-vCore steps.
    private const double VCoreIncrement = 0.25;
    private const int RandomSeed = 2026;
    private static readonly TimeOnly SimulatedStart = new(7, 0);
    private static readonly (string Role, string Location)[] Seats = ClinicCast.Seats;
    private static readonly string[] Patients = ClinicCast.Patients;
    private static readonly (string Specialty, string Clinic)[] Services = ClinicCast.Services;

    private readonly ServerlessScriptOptions _options;
    private readonly object _gate = new();
    private readonly List<ScaleSample> _samples = [];
    private readonly List<SimulatedUser> _users = [];
    private readonly Dictionary<int, double> _nextActionAt = [];
    private readonly List<AppActivity> _activity = [];
    private readonly double _rampUpEnd;
    private readonly double _holdEnd;
    private readonly double _rampDownEnd;
    private readonly double _pauseAt;
    private readonly double _resumeAt;
    private readonly double _resumedAt;
    private readonly double _end;

    private CancellationTokenSource? _loop;
    private Random _random = new(RandomSeed);
    private double _t;
    private double _simMinutes;
    private double _vCores;
    private int _peakUsers;
    private int _nextUserId;
    private int _sequence;
    private int _booked;
    private int _checkedIn;
    private int _rescheduled;
    private ServerlessStatus _status;
    private bool _complete;

    public ScriptedScaleWorkload(IOptions<ServerlessScriptOptions> options)
    {
        _options = options.Value;
        _rampUpEnd = OpenSeconds + RampUpSeconds;
        _holdEnd = _rampUpEnd + HoldSeconds;
        _rampDownEnd = _holdEnd + RampDownSeconds;
        _pauseAt = _rampDownEnd + _options.AutoPauseDelayMinutes / SimMinutesPerScriptSecond;
        _resumeAt = _pauseAt + PausedHoldSeconds;
        _resumedAt = _resumeAt + ResumeSeconds;
        _end = _resumedAt + AfternoonSeconds;
        ResetCore();
    }

    public event Action? Changed;

    public string Mode => "Scripted";

    public ScaleSnapshot GetSnapshot()
    {
        lock (_gate)
        {
            return new ScaleSnapshot(
                IsRunning: _loop is not null,
                IsComplete: _complete,
                ScriptSeconds: _t,
                TotalScriptSeconds: _end,
                SimulatedTime: SimulatedNow(),
                Status: _status,
                StatusDetail: DescribeStatus(),
                ActiveUsers: _users.Count,
                PeakUsers: _peakUsers,
                VCores: Snap(_vCores),
                MinVCores: _options.MinVCores,
                MaxVCores: _options.MaxVCores,
                DatabaseName: _options.DatabaseName,
                ServiceObjective: _options.ServiceObjective,
                AutoPauseDelayMinutes: _options.AutoPauseDelayMinutes,
                Booked: _booked,
                CheckedIn: _checkedIn,
                Rescheduled: _rescheduled,
                Samples: _samples.ToArray(),
                Users: _users.ToArray(),
                Activity: Enumerable.Reverse(_activity).Take(7).ToArray());
        }
    }

    public void Play()
    {
        CancellationTokenSource cts;
        lock (_gate)
        {
            if (_loop is not null) return;
            if (_complete) ResetCore();
            cts = new CancellationTokenSource();
            _loop = cts;
        }

        _ = RunAsync(cts);
        Changed?.Invoke();
    }

    public void Pause()
    {
        CancellationTokenSource? cts;
        lock (_gate)
        {
            cts = _loop;
            _loop = null;
        }

        cts?.Cancel();
        Changed?.Invoke();
    }

    public void Reset()
    {
        Pause();
        lock (_gate) ResetCore();
        Changed?.Invoke();
    }

    public void Dispose()
    {
        lock (_gate)
        {
            _loop?.Cancel();
            _loop = null;
        }
    }

    private async Task RunAsync(CancellationTokenSource cts)
    {
        try
        {
            using var timer = new PeriodicTimer(TimeSpan.FromSeconds(TickSeconds));
            while (await timer.WaitForNextTickAsync(cts.Token))
            {
                bool done;
                lock (_gate)
                {
                    if (!ReferenceEquals(_loop, cts)) return;
                    StepOnce(TickSeconds);
                    done = _complete;
                    if (done) _loop = null;
                }

                Changed?.Invoke();
                if (done) return;
            }
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            cts.Dispose();
        }
    }

    private void ResetCore()
    {
        _samples.Clear();
        _users.Clear();
        _nextActionAt.Clear();
        _activity.Clear();
        _random = new Random(RandomSeed);
        _t = 0;
        _simMinutes = 0;
        _vCores = _options.MinVCores;
        _peakUsers = 0;
        _nextUserId = 1;
        _sequence = 0;
        _booked = 0;
        _checkedIn = 0;
        _rescheduled = 0;
        _status = ServerlessStatus.Online;
        _complete = false;
        _samples.Add(new ScaleSample(0, 0, _vCores, _status));
    }

    private void StepOnce(double dt)
    {
        var previous = _t;
        _t = Math.Min(_t + dt, _end);
        var clockRate = previous >= _resumeAt && previous < _resumedAt ? ResumeSimMinutesPerScriptSecond : SimMinutesPerScriptSecond;
        _simMinutes += (_t - previous) * clockRate;
        var resuming = _t >= _resumeAt && _t < _resumedAt;

        var targetUsers = TargetUsers(_t);
        while (_users.Count < targetUsers) AddUser();
        while (_users.Count > targetUsers) RemoveUser();
        _peakUsers = Math.Max(_peakUsers, _users.Count);

        foreach (var user in _users)
        {
            if (resuming || _t < _nextActionAt[user.Id]) continue;
            RecordActivity(user);
            _nextActionAt[user.Id] = _t + 2.0 + _random.NextDouble() * 2.5;
        }

        if (_t >= _pauseAt && _t < _resumeAt)
        {
            _status = ServerlessStatus.Paused;
            _vCores = 0;
        }
        else if (resuming)
        {
            _status = ServerlessStatus.Resuming;
            _vCores = 0;
        }
        else
        {
            _status = _users.Count > 0
                ? ServerlessStatus.Active
                : _t >= _rampDownEnd ? ServerlessStatus.IdleAwaitingPause : ServerlessStatus.Online;

            var target = TargetVCores(_users.Count, _t);
            _vCores += (target - _vCores) * (1 - Math.Exp(-dt / VCoreResponseSeconds));
        }

        _samples.Add(new ScaleSample(_t, _users.Count, Snap(_vCores), _status));
        if (_t >= _end) _complete = true;
    }

    private static double Snap(double vCores) => Math.Round(vCores / VCoreIncrement) * VCoreIncrement;

    private int TargetUsers(double t)
    {
        var peak = _options.PeakUsers;
        if (t < OpenSeconds) return 0;
        if (t < _rampUpEnd) return Math.Min(peak, (int)((t - OpenSeconds) / (RampUpSeconds / peak)) + 1);
        if (t < _holdEnd) return peak;
        if (t < _rampDownEnd) return Math.Max(1, peak - (int)((t - _holdEnd) / (RampDownSeconds / peak)));
        if (t >= _resumedAt) return Math.Min(AfternoonUsers, 1 + (int)((t - _resumedAt) / AfternoonJoinSeconds));
        if (t >= _resumeAt) return 1;
        return 0;
    }

    private double TargetVCores(int users, double t)
    {
        if (users == 0) return _options.MinVCores;
        return Math.Clamp(_options.MinVCores + users * _options.VCoresPerUser, _options.MinVCores, _options.MaxVCores);
    }

    private void AddUser()
    {
        var id = _nextUserId++;
        var seat = Seats[(id - 1) % Seats.Length];
        _users.Add(new SimulatedUser(id, $"Staff {id:00}", seat.Role, seat.Location));
        _nextActionAt[id] = _t + 0.3 + _random.NextDouble() * 1.2;
    }

    private void RemoveUser()
    {
        _nextActionAt.Remove(_users[0].Id);
        _users.RemoveAt(0);
    }

    private void RecordActivity(SimulatedUser user)
    {
        var roll = _random.NextDouble();
        var service = Services[_random.Next(Services.Length)];
        var patient = Patients[_random.Next(Patients.Length)];
        var now = SimulatedNow();

        string kind;
        string when;
        if (roll < 0.6)
        {
            kind = "Booked";
            _booked++;
            when = FutureSlot();
        }
        else if (roll < 0.85)
        {
            kind = "Checked in";
            _checkedIn++;
            when = $"Today {now:h:mm tt}";
        }
        else
        {
            kind = "Rescheduled";
            _rescheduled++;
            when = FutureSlot();
        }

        _activity.Add(new AppActivity(++_sequence, now, user.Id, kind, patient, service.Specialty, service.Clinic, when));
        if (_activity.Count > 100) _activity.RemoveRange(0, _activity.Count - 100);
    }

    private string FutureSlot() => ClinicCast.FutureSlot(_random);

    private string DescribeStatus() => _status switch
    {
        ServerlessStatus.Active => "Compute follows demand",
        ServerlessStatus.IdleAwaitingPause => $"Idle · auto-pause in {Math.Max(1, (int)Math.Ceiling((_pauseAt - _t) * SimMinutesPerScriptSecond))} min",
        ServerlessStatus.Paused => "Resumes automatically on the next sign-in",
        ServerlessStatus.Resuming => "First sign-in woke the database (error 40613); the app retries · usually under a minute",
        _ => "Waiting for the first sign-in",
    };

    private TimeOnly SimulatedNow() => SimulatedStart.Add(TimeSpan.FromMinutes(_simMinutes));
}
