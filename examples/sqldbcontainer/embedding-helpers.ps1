function Assert-OllamaEmbeddingBatch {
    param(
        [Parameter(Mandatory)]$Response,
        [Parameter(Mandatory)][int]$Count,
        [int]$Dimensions = 0
    )
    if (@($Response.embeddings).Count -ne $Count) {
        throw "Ollama must return exactly $Count embeddings for this batch."
    }
    foreach ($embedding in $Response.embeddings) {
        if (@($embedding).Count -eq 0 -or ($Dimensions -gt 0 -and @($embedding).Count -ne $Dimensions)) {
            throw "Ollama returned an empty embedding or a dimension mismatch (expected $Dimensions when specified)."
        }
        $norm = 0.0
        foreach ($value in $embedding) {
            if (($value -isnot [double] -and $value -isnot [long] -and $value -isnot [int] -and $value -isnot [decimal]) -or
                -not [double]::IsFinite([double]$value)) {
                throw 'Ollama returned an embedding containing a nonnumeric or nonfinite value.'
            }
            $norm += [double]$value * [double]$value
        }
        if (-not [double]::IsFinite($norm) -or $norm -le 0) {
            throw 'Ollama returned a zero or invalid embedding; cosine search requires a nonzero vector.'
        }
    }
}
