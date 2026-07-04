# lib_crowding_signal.ps1 — Sinal de CROWDING via funding rate (ESTUDO 2026-07-04)
# Disciplina: estudo -> evidencia -> SHADOW -> producao.
#
# EVIDENCIA (n=5.133 obs, 59 futures, funding 8h vs retorno 24h a frente):
#   funding >= +0.10%  -> fwd24h mediana -0.73% (baseline -0.15%), SHORT acerta 56%
#   funding +0.03..0.10 -> fwd24h +0.37% (momentum CONTINUA; so o extremo reverte)
#   funding <= -0.10%  -> fwd24h -0.83%, LONG acerta so 43% -> REPROVADO como gatilho
# Conclusao: crowding de LONGS (funding extremo+) e AMPLIFICADOR de SHORT e
# CAUTELA de LONG. Crowding de shorts NAO habilita long (knife-catching).
#
# SHADOW: Get-CrowdingSignal alimenta (a) bloco informativo no mentor,
# (b) journal/crowding_shadow.jsonl para grading posterior (grade_llm_decisions
# do sinal em si). Thresholds re-estudados 4x/dia pelo guardian (api research).
# Exchange-agnostic no CORE: o threshold/decisao e puro; so o fetch e CoinEx.

$script:CROWDING_THRESHOLD_EXTREME = 0.10   # % por periodo de funding
$script:CROWDING_CACHE = @{}
$script:CROWDING_CACHE_AT = @{}

function Get-CrowdingThresholds {
    # Overlay re-estudado pelo research cycle (bounded 0.05..0.30; fail-safe default)
    [CmdletBinding()] param([string]$JournalDir = "")
    if (-not $JournalDir) { $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" } }
    $thr = $script:CROWDING_THRESHOLD_EXTREME
    $p = Join-Path $JournalDir "crowding_thresholds.json"
    if (Test-Path $p) {
        try {
            $o = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($o.extreme_pct) {
                $v = [double]$o.extreme_pct
                if ($v -lt 0.05) { $v = 0.05 }
                if ($v -gt 0.30) { $v = 0.30 }
                $thr = $v
            }
        } catch { }
    }
    return [PSCustomObject]@{ extreme_pct = $thr }
}

function Resolve-CrowdingVerdict {
    # PURA (testavel): funding% -> veredicto por evidencia
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $FundingPct,   # % por periodo (ex: 0.12)
        [double] $ExtremePct = 0.10
    )
    if ($FundingPct -ge $ExtremePct) {
        return [PSCustomObject]@{
            crowding = "CROWDED_LONGS"
            short_boost = $true      # evidencia: 56% win, -0.73% mediana
            long_caution = $true
            long_enable = $false
            note = "funding +$FundingPct% >= $ExtremePct% -> longs crowded (hist: fwd24h -0.73%, SHORT 56%)"
        }
    }
    if ($FundingPct -le -$ExtremePct) {
        return [PSCustomObject]@{
            crowding = "CROWDED_SHORTS"
            short_boost = $false
            long_caution = $true     # REPROVADO como gatilho de long (43%); downtrend forte
            long_enable = $false
            note = "funding $FundingPct% <= -$ExtremePct% -> downtrend forte (hist: LONG so 43%; NAO e gatilho de long)"
        }
    }
    return [PSCustomObject]@{
        crowding = "NEUTRAL"; short_boost = $false; long_caution = $false; long_enable = $false
        note = "funding $FundingPct% em faixa neutra"
    }
}

function Get-CrowdingSignal {
    # I/O CoinEx (cache 30min por market) -> veredicto + shadow log
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $JournalDir = ""
    )
    if (-not $JournalDir) { $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" } }
    $now = Get-Date
    if ($script:CROWDING_CACHE.ContainsKey($Market) -and ($now - $script:CROWDING_CACHE_AT[$Market]).TotalMinutes -lt 30) {
        return $script:CROWDING_CACHE[$Market]
    }
    $fundingPct = $null
    try {
        $r = Invoke-RestMethod -Uri "https://api.coinex.com/v2/futures/funding-rate?market=$Market" -TimeoutSec 8
        if ($r.code -eq 0 -and $r.data) {
            $row = if ($r.data -is [array]) { $r.data[0] } else { $r.data }
            $fundingPct = [math]::Round([double]$row.latest_funding_rate * 100, 4)
        }
    } catch { }
    if ($null -eq $fundingPct) {
        $sig = [PSCustomObject]@{ market=$Market; available=$false; funding_pct=$null; crowding="UNKNOWN"; short_boost=$false; long_caution=$false; note="sem futures/funding" }
    } else {
        $thr = (Get-CrowdingThresholds -JournalDir $JournalDir).extreme_pct
        $v = Resolve-CrowdingVerdict -FundingPct $fundingPct -ExtremePct $thr
        $sig = [PSCustomObject]@{ market=$Market; available=$true; funding_pct=$fundingPct
            crowding=$v.crowding; short_boost=$v.short_boost; long_caution=$v.long_caution; note=$v.note }
        # SHADOW log (grading posterior: o sinal previu o mercado?)
        try {
            $shadow = @{ ts=(Get-Date).ToUniversalTime().ToString("o"); market=$Market
                         funding_pct=$fundingPct; crowding=$v.crowding } | ConvertTo-Json -Compress
            Add-Content -Path (Join-Path $JournalDir "crowding_shadow.jsonl") -Value $shadow -Encoding utf8
        } catch { }
    }
    $script:CROWDING_CACHE[$Market] = $sig
    $script:CROWDING_CACHE_AT[$Market] = $now
    return $sig
}

function Get-CrowdingBlock {
    # Bloco pro prompt do mentor (informativo, evidencia citada)
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Market, [string] $JournalDir = "")
    $s = Get-CrowdingSignal -Market $Market -JournalDir $JournalDir
    if (-not $s.available -or $s.crowding -eq "NEUTRAL") { return "" }
    $lines = @("[CROWDING] funding=$($s.funding_pct)%/periodo -> $($s.crowding)")
    if ($s.short_boost)  { $lines += "  Evidencia (n=5133): fwd24h mediana -0.73% vs -0.15% baseline; SHORT acerta 56% -> confluencia A FAVOR de SHORT." }
    if ($s.long_caution) { $lines += "  CAUTELA para LONG neste momento (crowding/downtrend). NAO e gatilho standalone." }
    return ($lines -join "`n")
}
