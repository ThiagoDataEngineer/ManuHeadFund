# lib_mentor_hallucination_detector.ps1 -- 2026-05-21 PM6+870min.
#
# Detecta Mentor LLM alucinando "FQS indisponivel" quando FullContext tinha FQS valido.
# Background: bug PM6+870min revelou que mesmo com anti-hallucination rule no system
# prompt, Mentor (anthropic_sonnet) ainda invocava "FQS missing" pra justificar VETAR.
# Evidencia: TAO FQS=4 QUALITY no contexto, Mentor disse "FQS indisponivel".
#
# Pos-LLM validator: detecta pattern + persiste em journal pra audit.
# NAO bloqueia decisao (Mentor ainda VETAR), mas LOGA pra metricas + skill reforco.
#
# PS 5.1, UTF-8 BOM.

function Test-MentorFqsHallucination {
    <#
    .SYNOPSIS
        True se Mentor reason cita "FQS missing/indisponivel" mas FullContext tinha
        FQS != null E score > 0.
    .OUTPUTS
        PSCustomObject { is_hallucination, evidence, mentor_pattern, context_value }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $MentorReason,
        [Parameter()] [AllowNull()] [Nullable[int]] $FullContextFqsScore = $null,
        [Parameter()] [AllowEmptyString()] [string] $FullContextFqsCategory = ""
    )

    # Patterns que Mentor usa pra "FQS missing".
    # NOTE: usar prefix-only sem chars acentuados pra evitar mismatch UTF-8/UTF-16.
    $patterns = @(
        'FQS\s+indispon',                       # "indisponivel" ou "indisponível"
        'FQS\s+\w*o\s+declarad',                # "nao declarado" / "não declarado"
        'FQS\s+sem\s+entry\s+no\s+registry',
        'FQS\s+missing',
        'FQS\s*=\s*N\/A',
        'FQS\s+do\s+ativo\s+\w*o\s+foi\s+declarad'
    )

    $mentorClaimsMissing = $false
    $matchedPattern = ""
    foreach ($p in $patterns) {
        if ($MentorReason -imatch $p) {
            $mentorClaimsMissing = $true
            $matchedPattern = $p
            break
        }
    }

    if (-not $mentorClaimsMissing) {
        return [PSCustomObject]@{
            is_hallucination = $false
            evidence = "mentor_did_not_claim_fqs_missing"
            mentor_pattern = ""
            context_value = ""
        }
    }

    # Mentor claimed missing. Era REAL?
    $contextHadFqs = ($null -ne $FullContextFqsScore -and [int]$FullContextFqsScore -gt 0)
    if ($contextHadFqs) {
        return [PSCustomObject]@{
            is_hallucination = $true
            evidence = "fqs_was_in_context_score_$($FullContextFqsScore)_category_$($FullContextFqsCategory)"
            mentor_pattern = $matchedPattern
            context_value = "FQS=$FullContextFqsScore/7 $FullContextFqsCategory"
        }
    }

    # Mentor claimed missing AND realmente missing
    return [PSCustomObject]@{
        is_hallucination = $false
        evidence = "fqs_genuinely_absent_from_context"
        mentor_pattern = $matchedPattern
        context_value = "FQS=N/A"
    }
}

function Add-HallucinationEvent {
    <#
    .SYNOPSIS
        Persiste evento de hallucination em journal pra audit + metricas merit-only.
    .DESCRIPTION
        JSONL append-only. Replay analyzer pode filtrar decisoes com hallucination
        type pra computar metricas honestas (ja existe pattern em replay_decisions_analyzer).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Type,
        [Parameter(Mandatory)] [string] $MentorReason,
        [Parameter()] [string] $ContextValue = ""
    )
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $entry = [ordered]@{
        ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        market = $Market
        type = $Type
        mentor_reason_excerpt = ($MentorReason.Substring(0, [Math]::Min(200, $MentorReason.Length)))
        context_value = $ContextValue
    }
    $line = ($entry | ConvertTo-Json -Compress -Depth 3)
    Add-Content -Path $Path -Value $line -Encoding UTF8
}
