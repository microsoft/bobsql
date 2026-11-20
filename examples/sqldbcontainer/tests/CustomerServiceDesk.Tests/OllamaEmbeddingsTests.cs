using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using CustomerServiceDesk.Data;

namespace CustomerServiceDesk.Tests;

public class OllamaEmbeddingsTests
{
    private static readonly SearchProfile Profile = new(1, "Ollama", "nomic-embed-text:v1.5",
        "expected-digest", 768, "search_query: ");

    [Fact]
    public async Task UsesExactModelPrefixAndDoesNotTruncateQuestion()
    {
        JsonElement requestBody = default;
        using var client = Client((request, _) =>
        {
            if (request.RequestUri!.AbsolutePath == "/api/tags")
                return Task.FromResult(Tags("expected-digest"));
            return CaptureEmbeddingAsync(request);
        });
        async Task<HttpResponseMessage> CaptureEmbeddingAsync(HttpRequestMessage request)
        {
            requestBody = await request.Content!.ReadFromJsonAsync<JsonElement>();
            return Embedding(Enumerable.Repeat(0.5f, 768).ToArray());
        }

        var vector = await new OllamaEmbeddings(client).EmbedQueryAsync(Profile, "A new question", default);

        Assert.Equal(768, vector.Length);
        Assert.Equal(Profile.ModelName, requestBody.GetProperty("model").GetString());
        Assert.Equal("search_query: A new question", requestBody.GetProperty("input").GetString());
        Assert.False(requestBody.GetProperty("truncate").GetBoolean());
    }

    [Theory]
    [InlineData("different-digest")]
    [InlineData("")]
    public async Task RejectsModelDigestMismatchBeforeInference(string digest)
    {
        var calls = 0;
        using var client = Client((_, _) =>
        {
            calls++;
            return Task.FromResult(Tags(digest));
        });
        await Assert.ThrowsAsync<EmbeddingUnavailableException>(() =>
            new OllamaEmbeddings(client).EmbedQueryAsync(Profile, "Question", default));
        Assert.Equal(1, calls);
    }

    [Theory]
    [InlineData(767, 0.5f)]
    [InlineData(768, 0f)]
    public async Task RejectsInvalidVector(int dimensions, float value)
    {
        using var client = Client((request, _) => Task.FromResult(
            request.RequestUri!.AbsolutePath == "/api/tags" ? Tags("expected-digest")
                : Embedding(Enumerable.Repeat(value, dimensions).ToArray())));
        await Assert.ThrowsAsync<EmbeddingUnavailableException>(() =>
            new OllamaEmbeddings(client).EmbedQueryAsync(Profile, "Question", default));
    }

    [Fact]
    public async Task RejectsDifferentModelInEmbeddingResponse()
    {
        using var client = Client((request, _) => Task.FromResult(
            request.RequestUri!.AbsolutePath == "/api/tags" ? Tags("expected-digest")
                : new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = JsonContent.Create(new { model = "other", embeddings = new[] { new float[768] } })
                }));
        await Assert.ThrowsAsync<EmbeddingUnavailableException>(() =>
            new OllamaEmbeddings(client).EmbedQueryAsync(Profile, "Question", default));
    }

    [Fact]
    public async Task PropagatesServiceFailureWithoutPreparedFallback()
    {
        using var client = Client((_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable)));
        await Assert.ThrowsAsync<HttpRequestException>(() =>
            new OllamaEmbeddings(client).EmbedQueryAsync(Profile, "Question", default));
    }

    [Fact]
    public async Task RejectsUnsupportedProviderBeforeCallingService()
    {
        using var client = Client((_, _) => throw new InvalidOperationException("Should not call the service."));
        await Assert.ThrowsAsync<EmbeddingUnavailableException>(() =>
            new OllamaEmbeddings(client).EmbedQueryAsync(Profile with { Provider = "Foundry" }, "Question", default));
    }

    private static HttpResponseMessage Tags(string digest) => new(HttpStatusCode.OK)
    {
        Content = JsonContent.Create(new { models = new[] { new { name = Profile.ModelName, digest } } })
    };

    private static HttpResponseMessage Embedding(float[] vector) => new(HttpStatusCode.OK)
    {
        Content = JsonContent.Create(new { model = Profile.ModelName, embeddings = new[] { vector } })
    };

    private static HttpClient Client(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) =>
        new(new StubHandler(send)) { BaseAddress = new Uri("http://localhost:11434/") };

    private sealed class StubHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send)
        : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            send(request, cancellationToken);
    }
}
