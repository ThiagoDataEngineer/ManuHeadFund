# knowledge_retriever.ps1 -- Retrieval simples de chunks de knowledge/*.md por tag
# Dot-source: . (Join-Path $PSScriptRoot "knowledge_retriever.ps1")
#
# Contrato:
#   Get-RelevantKnowledge -Tags @("livermore","wyckoff") [-MaxChunks 3]
#     -> retorna array de [PSCustomObject]@{ source; tag; text } ou @() vazio
#
# Design:
#   - Substring match case-insensitive em conteudo bruto dos .md
#   - Para cada tag, primeiro arquivo que contem a tag fornece um chunk
#   - text = ~800 chars do paragrafo onde a tag apareceu
#   - Sem embeddings, sem dependencias externas. Zero custo LLM.
#   - Knowledge dir resolvido relativo ao script: $PSScriptRoot\..\knowledge

$KB_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "knowledge"
$KB_CHUNK_MAX_CHARS = 800


function Get-RelevantKnowledge {
    param(
        [string[]]$Tags = @(),
        [int]$MaxChunks = 3
    )

    if (-not $Tags -or $Tags.Count -eq 0) { return @() }
    if ($MaxChunks -le 0) { return @() }

    if (-not (Test-Path $KB_DIR)) { return @() }

    $files = Get-ChildItem -Path $KB_DIR -Filter "*.md" -ErrorAction SilentlyContinue
    if (-not $files) { return @() }

    $results = New-Object System.Collections.ArrayList

    foreach ($tag in $Tags) {
        if ($results.Count -ge $MaxChunks) { break }
        if ([string]::IsNullOrWhiteSpace($tag)) { continue }
        $tagLower = $tag.ToLowerInvariant()

        foreach ($file in $files) {
            if ($results.Count -ge $MaxChunks) { break }
            try {
                $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
            } catch {
                continue
            }
            if (-not $content) { continue }

            $idx = $content.ToLowerInvariant().IndexOf($tagLower)
            if ($idx -lt 0) { continue }

            # Extrai contexto: ~200 chars antes ate +600 depois (ou ate fim)
            $start = [math]::Max(0, $idx - 200)
            $end   = [math]::Min($content.Length, $idx + 600)
            $chunk = $content.Substring($start, $end - $start)
            if ($chunk.Length -gt $KB_CHUNK_MAX_CHARS) {
                $chunk = $chunk.Substring(0, $KB_CHUNK_MAX_CHARS)
            }

            $null = $results.Add([PSCustomObject]@{
                source = $file.Name
                tag    = $tagLower
                text   = $chunk.Trim()
            })
            # Uma tag = um chunk (do primeiro arquivo que casou)
            break
        }
    }

    # Prefixo virgula forca retorno como array (evita unwrap de 1 elemento)
    return ,$results.ToArray()
}
