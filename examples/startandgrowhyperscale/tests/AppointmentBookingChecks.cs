using System.Reflection;
using CaldovaNetworkScheduling.Components.Pages;
using CaldovaNetworkScheduling.Models;
using CaldovaNetworkScheduling.Services;
using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;

internal static class AppointmentBookingChecks
{
    public static async Task RunAsync(Action<bool, string> check)
    {
        foreach (var key in new[] { "caldova", "northbrook", "ridgeview" })
        {
            var query = SqlAppointmentAvailabilityService.GetResetQuery(key);
            var database = SqlAppointmentAvailabilityService.GetDatabase(key);
            check(query.Contains($"FROM {SqlAppointmentAvailabilityService.GetSourceObject(key)} AS s")
                && query.Contains($"DELETE FROM [{database}].dbo.Appointment")
                && new[] { "caldova-scheduling", "northbrook-scheduling", "ridgeview-scheduling" }
                    .Where(d => d != database).All(d => !query.Contains($"[{d}]")),
                $"{key} reset writes only to the allowlisted provider database");
            check(query.Contains("a.AppointmentId = @AppointmentId AND a.SlotId = s.SlotId")
                && query.Contains("AppointmentId = @AppointmentId AND SlotId = @SlotId")
                && query.Contains("BookedVia = N'caldova-network'") && query.Contains("s.IsBooked = 1")
                && query.Split("IF @@ROWCOUNT <> 1").Length == 3,
                $"{key} reset guards the exact appointment and slot, rejecting stale or mismatched bookings");
            check(query.Contains("SET XACT_ABORT ON") && query.Contains("BEGIN TRANSACTION")
                && query.Contains("UPDLOCK, HOLDLOCK") && query.Contains("COMMIT TRANSACTION"),
                $"{key} reset locks the slot first and atomically reopens it and deletes only its appointment");
            check(SqlAppointmentAvailabilityService.GetBookingQuery(key).Contains("SCOPE_IDENTITY()"),
                $"{key} booking returns its exact appointment identity for subsequent reset");
        }
        try
        {
            SqlAppointmentAvailabilityService.GetResetQuery("ridgeview]; DROP TABLE dbo.Appointment;--");
            check(false, "Reset must reject arbitrary provider names");
        }
        catch (ArgumentException) { check(true, "Reset rejects arbitrary provider names"); }
        var disabled = new SqlAppointmentAvailabilityService(new ConfigurationBuilder().Build());
        check(!disabled.ResetEnabled, "Booking reset defaults to disabled");
        try
        {
            await disabled.ResetAsync("ridgeview", 8, 101);
            check(false, "Disabled reset must fail before connecting to SQL");
        }
        catch (InvalidOperationException ex) when (ex.Message.Contains("disabled"))
        { check(true, "Disabled reset cannot open SQL or mutate data"); }
        foreach (var url in new[] { "http://0.0.0.0:5099", "http://example.com:5099", null })
        {
            var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
            { ["BookingReset:Enabled"] = "true", ["urls"] = url }).Build();
            try
            {
                await new SqlAppointmentAvailabilityService(config).ResetAsync("ridgeview", 8, 101);
                check(false, "Reset requires explicit loopback binding");
            }
            catch (InvalidOperationException ex) when (ex.Message.Contains("localhost-bound"))
            { check(true, "Reset rejects public, wildcard, or missing bindings before SQL access"); }
        }
        var localConfig = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        { ["BookingReset:Enabled"] = "true", ["urls"] = "http://localhost:5099" }).Build();
        PoolScaler.ValidateHost(localConfig);
        check(new SqlAppointmentAvailabilityService(localConfig).ResetEnabled, "Reset accepts an explicitly opted-in localhost host");
        var service = new Availability();
        var services = new ServiceCollection().AddLogging()
            .AddSingleton<IAppointmentAvailabilityService>(service);
        await using var provider = services.BuildServiceProvider();
        await using var renderer = new HtmlRenderer(provider, provider.GetRequiredService<ILoggerFactory>());
        await renderer.Dispatcher.InvokeAsync(async () =>
        {
            Page? page = null;
            var root = await renderer.RenderComponentAsync<Page>(ParameterView.FromDictionary(
                new Dictionary<string, object?> { ["Capture"] = (Action<Page>)(value => page = value) }));
            async Task Invoke(string method, params object[] arguments)
            {
                await (Task)typeof(Appointments).GetMethod(method, BindingFlags.NonPublic | BindingFlags.Instance)!
                    .Invoke(page, arguments)!;
                page!.Refresh();
            }
            await Invoke("SearchAsync");
            await Invoke("BookAsync", service.Remote);
            var markup = root.ToHtmlString();
            check(markup.IndexOf("Behind the view", StringComparison.Ordinal) <
                markup.IndexOf("Booking · one transaction", StringComparison.Ordinal),
                "The native view SQL appears before the booking INSERT panel");
            check(service.BookCalls == 1 && service.SearchCalls == 1
                && markup.Contains("Booked Ridgeview") && markup.Contains(">Booked</button>")
                && System.Text.RegularExpressions.Regex.Matches(markup, "<tr>").Count == 3,
                "A successful booking stays in its original search results with a Booked button and no refresh");
            check(System.Text.RegularExpressions.Regex.IsMatch(markup, "<button[^>]*disabled[^>]*>Booked</button>")
                && System.Text.RegularExpressions.Regex.IsMatch(markup, "<button(?![^>]*disabled)[^>]*>Book slot</button>"),
                "Only the confirmed provider/slot is disabled, even when another provider has the same slot ID");
            await Invoke("BookAsync", service.Remote);
            check(service.BookCalls == 1, "The confirmed row cannot submit a second booking");
            await Invoke("SearchAsync");
            check(!root.ToHtmlString().Contains(">Booked</button>") && !root.ToHtmlString().Contains("<strong>Ridgeview</strong>"),
                "An explicit new search clears row markers and excludes the booked slot using availability");
            service.Booked = false;
            await Invoke("SearchAsync");
            check(root.ToHtmlString().Contains("<strong>Ridgeview</strong>")
                && !root.ToHtmlString().Contains(">Booked</button>"),
                "After a separately approved database reset, a new search offers that slot again");
            service.LoseRace = true;
            await Invoke("BookAsync", service.Remote);
            check(root.ToHtmlString().Contains("That slot is no longer available")
                && !root.ToHtmlString().Contains(">Booked</button>"),
                "A lost booking race is never labeled as a confirmed booking");
            service.Booked = false;
            service.LoseRace = false;
            service.Fail = true;
            await Invoke("SearchAsync");
            var before = service.BookCalls;
            await Invoke("BookAsync", service.Remote);
            check(service.BookCalls == before + 1 && root.ToHtmlString().Contains("Do not retry blindly")
                && !root.ToHtmlString().Contains(">Booked</button>"),
                "An uncertain booking outcome stays an explicit error, never a success marker or a write retry");
            service.Fail = false;
            service.Booked = false;
            await Invoke("SearchAsync");
            service.Pending = new TaskCompletionSource<BookingResult>(TaskCreationOptions.RunContinuationsAsynchronously);
            before = service.BookCalls;
            var pending = Invoke("BookAsync", service.Remote);
            await Invoke("BookAsync", service.Remote);
            check(service.BookCalls == before + 1, "An in-flight booking cannot submit a duplicate write");
            service.Pending.SetResult(new BookingResult(true, "booking SQL", 501));
            await pending;
            service.Pending = null;
            check(root.ToHtmlString().Contains(">Reset booking</button>"),
                "A confirmed booking with an exact receipt offers a Reset booking button");
            service.ResetPending = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var resetting = Invoke("ResetAsync", service.Remote);
            await Invoke("ResetAsync", service.Remote);
            check(service.ResetCalls == 1, "An in-flight reset cannot submit a duplicate write");
            service.ResetPending.SetResult();
            await resetting;
            service.ResetPending = null;
            markup = root.ToHtmlString();
            check(service.LastReset == ("ridgeview", 8L, 501L),
                "Reset sends the confirmed provider, slot, and exact appointment identity, not a bulk reset");
            check(markup.Contains("slot reopened") && markup.Contains("<strong>Ridgeview</strong>")
                && !markup.Contains(">Booked</button>") && !markup.Contains(">Reset booking</button>")
                && !service.Booked,
                "A confirmed reset keeps the row visible and restores its Book slot button");
            await Invoke("BookAsync", service.Remote);
            check(root.ToHtmlString().Contains(">Booked</button>"), "A reset row can be booked again");
            service.FailReset = true;
            var resets = service.ResetCalls;
            await Invoke("ResetAsync", service.Remote);
            check(service.ResetCalls == resets + 1 && root.ToHtmlString().Contains("Reset could not be confirmed")
                && root.ToHtmlString().Contains("Do not retry blindly")
                && !root.ToHtmlString().Contains("<strong>Ridgeview</strong>"),
                "An uncertain reset is not retried or presented as a successfully reopened slot");
            service.ResetEnabled = false;
            service.Booked = false;
            await Invoke("SearchAsync");
            await Invoke("BookAsync", service.Remote);
            check(!root.ToHtmlString().Contains(">Reset booking</button>"),
                "Reset controls stay hidden when reset is disabled");
            resets = service.ResetCalls;
            await Invoke("ResetAsync", service.Remote);
            check(service.ResetCalls == resets && root.ToHtmlString().Contains("Reset could not be confirmed"),
                "The page also rejects reset invocation when the host disables it");
            service.ResetEnabled = true;
            service.ReturnReceipt = false;
            service.Booked = false;
            await Invoke("SearchAsync");
            await Invoke("BookAsync", service.Remote);
            check(root.ToHtmlString().Contains(">Booked</button>") && !root.ToHtmlString().Contains(">Reset booking</button>"),
                "A booking without an exact appointment receipt cannot offer an unsafe reset");
        });
    }

    public sealed class Page : Appointments
    {
        [Parameter] public Action<Page>? Capture { get; set; }
        protected override void OnInitialized() => Capture?.Invoke(this);
        public void Refresh() => StateHasChanged();
    }

    private sealed class Availability : IAppointmentAvailabilityService, IAppointmentBookingResetService
    {
        public string Mode => "SQL";
        public IReadOnlyList<string> Specialties => ["Cardiology"];
        public string ViewDefinition => "";
        public AppointmentSlot Remote { get; } = new("ridgeview", "Ridgeview",
            "[ridgeview-scheduling].dbo.AppointmentSlot", true, "Clinic", "Doctor", "Cardiology",
            DateTime.UtcNow.AddDays(2), 30, 8);
        public bool Booked { get; set; }
        public bool LoseRace { get; set; }
        public bool Fail { get; set; }
        public bool ResetEnabled { get; set; } = true;
        public bool ReturnReceipt { get; set; } = true;
        public bool FailReset { get; set; }
        public TaskCompletionSource<BookingResult>? Pending { get; set; }
        public TaskCompletionSource? ResetPending { get; set; }
        public int ResetCalls { get; private set; }
        public (string ProviderKey, long SlotId, long AppointmentId)? LastReset { get; private set; }
        public int BookCalls { get; private set; }
        public int SearchCalls { get; private set; }
        public Task<AvailabilityResult> FindNextAsync(string specialty, bool networkWide, CancellationToken cancellationToken = default)
        {
            SearchCalls++;
            var local = Remote with { ProviderKey = "caldova", ProviderName = "Caldova", IsRemote = false };
            IReadOnlyList<AppointmentSlot> slots = Booked ? [local] : [Remote, local];
            return Task.FromResult(new AvailabilityResult(networkWide, "SELECT", slots, local));
        }
        public Task<BookingResult> BookAsync(string providerKey, long slotId, CancellationToken cancellationToken = default)
        {
            BookCalls++;
            if (Fail) throw new InvalidOperationException("Booking outcome unknown");
            if (Pending is not null) return Pending.Task;
            Booked = true;
            return Task.FromResult(new BookingResult(!LoseRace, "booking SQL", !LoseRace && ReturnReceipt ? 100L + BookCalls : null));
        }
        public async Task ResetAsync(string providerKey, long slotId, long appointmentId, CancellationToken cancellationToken = default)
        {
            ResetCalls++;
            LastReset = (providerKey, slotId, appointmentId);
            if (FailReset) throw new InvalidOperationException("Reset outcome unknown");
            if (ResetPending is not null) await ResetPending.Task;
            Booked = false;
        }
        public Task<NetworkCheck> CheckNetworkAsync(CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();
    }
}
