using System.Net.Http.Json;

namespace CustomerServiceDesk.Data;

public sealed class EmbeddingUnavailableException(string message) : Exception(message);

public sealed class OllamaEmbeddings(HttpClient client)
{
    public async Task<float[]> EmbedQueryAsync(SearchProfile profile, string text, CancellationToken token)
    {
        if (profile.Provider != "Ollama" || profile.Dimensions != 768)
            throw new EmbeddingUnavailableException("The active profile is not a supported local Ollama profile. No alternative model was used.");

        var tags = await client.GetFromJsonAsync<ModelList>("api/tags", token);
        var model = tags?.Models?.SingleOrDefault(m => m.Name == profile.ModelName);
        if (model is null || model.Digest != profile.ModelVersion)
            throw new EmbeddingUnavailableException("The installed Ollama model does not match the corpus model digest. Restore the matching model or rebuild embeddings under a new profile.");

        using var response = await client.PostAsJsonAsync("api/embed", new
        {
            model = profile.ModelName,
            input = profile.QueryPrefix + text,
            truncate = false,
            keep_alive = "30m"
        }, token);
        response.EnsureSuccessStatusCode();
        var result = await response.Content.ReadFromJsonAsync<EmbeddingResult>(token);
        if (result?.Model != profile.ModelName || result.Embeddings is not { Length: 1 }
            || result.Embeddings[0] is not { } vector || vector.Length != profile.Dimensions
            || vector.Any(value => !float.IsFinite(value))
            || vector.Sum(value => (double)value * value) <= 0)
            throw new EmbeddingUnavailableException("Ollama returned an invalid embedding or a different model. No substitute results were returned.");
        return vector;
    }

    private sealed record ModelList(ModelInfo[]? Models);
    private sealed record ModelInfo(string Name, string Digest);
    private sealed record EmbeddingResult(string Model, float[][]? Embeddings);
}
