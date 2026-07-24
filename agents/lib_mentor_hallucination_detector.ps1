# lib_mentor_hallucination_detector.ps1 -- Mentor hallucination detector v2

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

# 2026-07-23 IMPLEMENTADO: TDD existia desde 2026-05-21 (PM6+870min,
# tests/fqs_hallucination_detector.Tests.ps1, 6 casos) mas as funcoes nunca
# foram escritas -- agents/mentor_agent.ps1 ja CHAMA ambas (linhas ~1051 e
# ~1068, atras de Get-Command -ErrorAction SilentlyContinue), entao a
# deteccao de alucinacao especifica de FQS estava silenciosamente inativa
# em producao desde que foi "wired" no mentor_agent, apesar do codigo
# parecer conectado. Achado durante auditoria de integridade 2026-07-23.

function Test-MentorFqsHallucination {
    <#
    .SYNOPSIS
        Detecta o Mentor alegando "FQS indisponivel" quando o FullContext
        real tinha um FQS score valido (Mentor alucinando, nao um caso
        legitimo de mercado sem entry no registry).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $MentorReason,
        [Nullable[int]] $FullContextFqsScore = $null,
        [string] $FullContextFqsCategory = ""
    )

    $missingPattern = "FQS\s*=?\s*(indisponivel|nao declarado|sem entry|missing|N/?A)"
    $mentionsFqsMissing = $MentorReason -match $missingPattern

    if (-not $mentionsFqsMissing) {
        return [PSCustomObject]@{
            is_hallucination = $false
            evidence = "no_fqs_missing_claim"
            context_value = ""
        }
    }

    # FQS=0 e o "registry no_entry path" -- valor sentinela que o pipeline
    # usa quando o market nao tem entry real no registry (categoria AVOID),
    # equivalente a "legitimamente ausente" pro proposito desta deteccao.
    # So um score >0 conta como "FQS estava de fato disponivel no contexto".
    $fqsWasInContext = ($null -ne $FullContextFqsScore -and $FullContextFqsScore -gt 0)

    if ($fqsWasInContext) {
        return [PSCustomObject]@{
            is_hallucination = $true
            evidence = "fqs_was_in_context"
            context_value = "FQS=$FullContextFqsScore/7 $FullContextFqsCategory"
        }
    }

    return [PSCustomObject]@{
        is_hallucination = $false
        evidence = "fqs_legitimately_missing"
        context_value = $FullContextFqsCategory
    }
}

function Add-HallucinationEvent {
    <#
    .SYNOPSIS
        Persiste um evento de alucinacao detectada em JSONL para audit.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Type,
        [Parameter(Mandatory)] [string] $MentorReason,
        [string] $ContextValue = ""
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $entry = [ordered]@{
        ts_utc = (Get-Date).ToUniversalTime().ToString("o")
        market = $Market
        type = $Type
        mentor_reason = $MentorReason
        context_value = $ContextValue
    } | ConvertTo-Json -Compress

    Add-Content -Path $Path -Value $entry -Encoding UTF8
}

function Invoke-MentorHallucinationAudit {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $MentorOutput,
        [string] $JournalDir = $global:JOURNAL_DIR,
        [datetime] $Now = (Get-Date)
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $hallucinPath = Join-Path $JournalDir "mentor_hallucinations.jsonl"

    $isHallucination = $false
    $reasons = @()

    # Check 1: conviction sem data sources
    if ($MentorOutput.conviction -gt 0 -and ($null -eq $MentorOutput.data_sources -or $MentorOutput.data_sources.Count -eq 0)) {
        $isHallucination = $true
        $reasons += "Conviction $($MentorOutput.conviction) sem fontes de dados"
    }

    # Check 2: reasoning menciona metricas não calculadas
    if ($null -ne $MentorOutput.reasoning -and $null -ne $MentorOutput.calculated_metrics) {
        $reasoning = $MentorOutput.reasoning
        if ($reasoning -match "RSI" -and $MentorOutput.calculated_metrics -notcontains "RSI") {
            $isHallucination = $true
            $reasons += "Reasoning cita RSI mas não foi calculado"
        }
    }

    # Registra audit entry
    $auditEntry = [ordered]@{
        timestamp = $timestamp
        market = $MentorOutput.market
        conviction = $MentorOutput.conviction
        is_hallucination = $isHallucination
        reason = ($reasons -join " | ")
    } | ConvertTo-Json -Compress

    Add-Content -Path $hallucinPath -Value $auditEntry -Encoding UTF8

    return [PSCustomObject]@{
        is_hallucination = $isHallucination
        reason = ($reasons -join " | ")
        market = $MentorOutput.market
        conviction = $MentorOutput.conviction
    }
}
