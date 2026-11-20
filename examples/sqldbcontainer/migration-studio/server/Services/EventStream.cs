using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Threading.Channels;

namespace MigrationStudio.Services;

public sealed record StreamEnvelope(long Id, string Name, string Json);

public interface IEventStream
{
    StudioEvent Publish(string stage, string state, string message, string? runId = null, string? subject = null);
    void Copilot(string kind, string text);
    IAsyncEnumerable<StreamEnvelope> Subscribe(long after, CancellationToken token);
}

public sealed class EventStream : IEventStream
{
    private readonly object gate = new();
    private readonly Queue<StreamEnvelope> history = new();
    private readonly ConcurrentDictionary<Guid, Channel<StreamEnvelope>> subscribers = new();
    private long sequence;

    public StudioEvent Publish(string stage, string state, string message, string? runId = null, string? subject = null)
    {
        lock (gate)
        {
            var entry = new StudioEvent(++sequence, DateTimeOffset.UtcNow, stage, state, message, runId, subject);
            Broadcast(new(entry.Id, "message", JsonSerializer.Serialize(entry, StudioPaths.Json)));
            return entry;
        }
    }

    public void Copilot(string kind, string text)
    {
        lock (gate)
            Broadcast(new(++sequence, "copilot", JsonSerializer.Serialize(new { kind, text }, StudioPaths.Json)));
    }

    private void Broadcast(StreamEnvelope entry)
    {
        history.Enqueue(entry);
        while (history.Count > 500) history.Dequeue();
        foreach (var channel in subscribers.Values)
        {
            if (!channel.Writer.TryWrite(entry))
                channel.Writer.TryComplete(new IOException("Event consumer fell behind. Reconnect for current state."));
        }
    }

    public async IAsyncEnumerable<StreamEnvelope> Subscribe(long after,
        [EnumeratorCancellation] CancellationToken token)
    {
        var id = Guid.NewGuid();
        var channel = Channel.CreateBounded<StreamEnvelope>(new BoundedChannelOptions(1024)
        {
            SingleReader = true, FullMode = BoundedChannelFullMode.Wait
        });
        lock (gate)
        {
            foreach (var entry in history.Where(e => e.Id > after))
                channel.Writer.TryWrite(entry);
            subscribers[id] = channel;
        }
        try
        {
            await foreach (var entry in channel.Reader.ReadAllAsync(token))
                yield return entry;
        }
        finally
        {
            subscribers.TryRemove(id, out _);
            channel.Writer.TryComplete();
        }
    }
}
