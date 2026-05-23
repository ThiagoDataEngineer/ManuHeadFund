# lib_fqs_enrichment_queue.ps1 -- Helper idempotente p/ enqueue FQS enrichment.
#
# Background:
#   Antes (PM6): apenas Build-MentorFullContext (mentor_agent.ps1) enfileirava
#   markets faltantes -- markets blocked antes de Mentor (GEM track via Tori, Tier D
#   via scanner score) nunca eram detectados. Gap morning 2026-05-21:
#   ARRR/ASTER/PROVE/WIF apareceram em scan + 0 entries em queue.
#
# Esta lib oferece uma porta unica:
#   Add-FqsEnrichmentRequest -Market X -Source Y
#     - Skip se market ja esta em registry (no point re-enrich)
#     - Skip se ja foi enqueued nas ultimas 24h (anti-spam queue)
#     - Append idempotente em journal/fqs_enrichment_queue.jsonl
#
#   Get-FqsCoverage -Markets [array]
#     - Retorna { covered=[...]; missing=[...] } para audit
#
# Design: fail-open (silencioso em erro de IO) -- enrichment eh otimizacao,
# nao bloqueio operacional. Se falha, mentor_full_context fallback ainda gera
# ctx.fqs N/A_no_registry e segue.

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function _FqsQueueFile {
    Join-Path $global:JOURNAL_DIR "fqs_enrichment_queue.jsonl"
}

function _FqsRegistryFile {
    Join-Path $global:JOURNAL_DIR "coin_registry.json"
}


function Test-MarketInRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Market,
        [string] $RegistryPath = (_FqsRegistryFile)
    )
    if (-not (Test-Path $RegistryPath)) { return $false }
    try {
        $reg = Get-Content $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return [bool]($reg.PSObject.Properties[$Market])
    } catch {
        return $false
    }
}


function Test-MarketRecentlyEnqueued {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Market,
        [int] $WithinHours = 24,
        [string] $QueueFile = (_FqsQueueFile)
    )
    if (-not (Test-Path $QueueFile)) { return $false }
    $cutoff = (Get-Date).AddHours(-1 * [Math]::Abs($WithinHours))
    try {
        $lines = Get-Content $QueueFile -Encoding UTF8 -ErrorAction Stop
        foreach ($line in $lines) {
            $line = $line.Trim()
            if (-not $line) { continue }
            try {
                $e = $line | ConvertFrom-Json -ErrorAction Stop
                if ($e.market -eq $Market -and $e.queued_at) {
                    [datetime]$ts = [datetime]::MinValue
                    if ([DateTime]::TryParse([string]$e.queued_at, [ref]$ts)) {
                        if ($ts -ge $cutoff) { return $true }
                    }
                }
            } catch { continue }
        }
    } catch {}
    return $false
}


function Add-FqsEnrichmentRequest {
    <#
    .SYNOPSIS
    Enqueue idempotente. Skip se ja registrado OU ja enqueued nas ultimas 24h.

    .OUTPUTS
    [PSCustomObject] @{ market; action='enqueued'|'skip_registered'|'skip_recent'|'error'; reason }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Market,
        [string] $Source = "scan_master",
        [int] $DedupeWindowHours = 24,
        [string] $QueueFile = (_FqsQueueFile),
        [string] $RegistryPath = (_FqsRegistryFile)
    )

    if (Test-MarketInRegistry -Market $Market -RegistryPath $RegistryPath) {
        return [PSCustomObject]@{ market=$Market; action='skip_registered'; reason='already_in_registry' }
    }
    if (Test-MarketRecentlyEnqueued -Market $Market -WithinHours $DedupeWindowHours -QueueFile $QueueFile) {
        return [PSCustomObject]@{ market=$Market; action='skip_recent'; reason="enqueued_within_${DedupeWindowHours}h" }
    }

    try {
        $entry = @{
            market    = $Market
            source    = $Source
            queued_at = (Get-Date).ToString('o')
        }
        $entry | ConvertTo-Json -Compress | Add-Content -Path $QueueFile -Encoding utf8 -ErrorAction Stop
        return [PSCustomObject]@{ market=$Market; action='enqueued'; reason='ok' }
    } catch {
        return [PSCustomObject]@{ market=$Market; action='error'; reason=$_.Exception.Message }
    }
}


function Get-FqsCoverage {
    <#
    .SYNOPSIS
    Audit: para uma lista de markets, retorna quais tem entry no registry e quais nao.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $Markets,
        [string] $RegistryPath = (_FqsRegistryFile)
    )
    $covered = New-Object System.Collections.Generic.List[string]
    $missing = New-Object System.Collections.Generic.List[string]
    $regKeys = @{}
    if (Test-Path $RegistryPath) {
        try {
            $reg = Get-Content $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $reg.PSObject.Properties) { $regKeys[$p.Name] = $true }
        } catch {}
    }
    foreach ($m in $Markets) {
        if ($regKeys.ContainsKey($m)) { $covered.Add($m) } else { $missing.Add($m) }
    }
    return [PSCustomObject]@{
        total           = $Markets.Count
        covered         = [string[]]@($covered)
        missing         = [string[]]@($missing)
        coverage_pct    = if ($Markets.Count) { [Math]::Round(($covered.Count / $Markets.Count) * 100, 1) } else { 0 }
    }
}
