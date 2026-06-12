# lib_decision_reflection.ps1 -- Pending->Resolved reflection loop (Tauric-inspired).
#
# E3 (2026-05-22): cycle fechado. Decisao -> trade outcome -> reflection LLM-distilled.
# Proxima decisao mesmo market injeta 5 reflections no prompt.
#
# Filosofia (vs Tauric):
#   - Tauric: alpha vs SPY/N225 + reflection 2-4 frases
#   - Nosso:  alpha vs BTC (regra-ouro #13) + reflection focada em lesson
#   - Holding window depende tier: Tier A LIVE=4d, GEM=21d, swing=30d
#
# Operacao:
#   1. Lib expoe Add-PendingReflection (escreve pending entry pra closing futuro)
#   2. Cron MentorReflector le pending sem outcome, cruza com trade_close, computa
#      alpha_vs_btc, spawn Haiku LLM call ($0.001) pra distilar lesson
#   3. Reflection persistida em journal/decision_reflections.jsonl
#   4. Build-MentorFullContext (callable) adiciona PRIOR RESOLVED block ao prompt
#
# Fail-soft em CADA step: erro nao bloqueia core flow.
#
# PS 5.1. UTF-8 BOM.


$script:DEFAULT_REFLECTIONS_PATH = $null

function _Init-ReflectionsPath {
    if (-not $script:DEFAULT_REFLECTIONS_PATH) {
        $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" }
        $script:DEFAULT_REFLECTIONS_PATH = Join-Path $journalDir "decision_reflections.jsonl"
    }
}


function Add-PendingReflection {
    <#
    .SYNOPSIS
    Append entry "pending" ao reflections.jsonl quando trade abre.

    .DESCRIPTION
    Entry contem decisao original + setup info. Cron Reflector pega depois pra fechar.

    Idempotente: skip se ja existe entry com mesmo (trade_id) status=pending OR resolved.

    .PARAMETER TradeId
    Unique ID do trade (timestamp+market sufice se nao tiver UUID).

    .PARAMETER Market
    Market symbol.

    .PARAMETER EntryDateUtc
    YYYY-MM-DD UTC.

    .PARAMETER MentorVeredicto
    EXECUTAR/REVISAR/ABORTAR.

    .PARAMETER MentorConfidence
    0-100.

    .PARAMETER MentorMensagem
    Texto original do Mentor.

    .PARAMETER MesaSinal
    LONG/SHORT/NEUTRO.

    .PARAMETER Tier
    A_LIVE / A_PAPER / B_PAPER / GEM.

    .PARAMETER ReflectionsPath
    Override path (testing).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TradeId,
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $EntryDateUtc,
        [string] $MentorVeredicto = "",
        [int]    $MentorConfidence = 0,
        [string] $MentorMensagem = "",
        [string] $MesaSinal = "",
        [string] $Tier = "",
        [string] $ReflectionsPath = ""
    )

    if ($ReflectionsPath) { $script:DEFAULT_REFLECTIONS_PATH = $ReflectionsPath } else { _Init-ReflectionsPath }
    $path = $script:DEFAULT_REFLECTIONS_PATH

    # Idempotency: skip se ja existe entry com mesmo trade_id (pending OR resolved)
    if (Test-Path $path) {
        try {
            $existing = @(Get-Content $path -Encoding UTF8 -ErrorAction SilentlyContinue)
            foreach ($line in $existing) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                try {
                    $obj = $line | ConvertFrom-Json -ErrorAction Stop
                    if ($obj.trade_id -eq $TradeId) { return }  # already exists, skip
                } catch {}
            }
        } catch {}
    }

    $entry = [ordered]@{
        trade_id          = $TradeId
        market            = $Market
        entry_date_utc    = $EntryDateUtc
        mentor_veredicto  = $MentorVeredicto
        mentor_confidence = $MentorConfidence
        mentor_mensagem   = $MentorMensagem
        mesa_sinal        = $MesaSinal
        tier              = $Tier
        status            = "pending"
        added_at          = (Get-Date).ToUniversalTime().ToString("o")
    }

    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -Path $path -Value ($entry | ConvertTo-Json -Compress) -Encoding UTF8
}


function Get-PendingReflections {
    <#
    .SYNOPSIS
    Le reflections pending (sem resolved entry posterior).

    .DESCRIPTION
    JSONL append-only: status=pending eh entry inicial; status=resolved eh adicionada
    apos cron processar. Pending verdadeiros = trade_ids sem entry resolved.

    .PARAMETER ReflectionsPath
    Override path (testing).
    #>
    [CmdletBinding()]
    param([string] $ReflectionsPath = "")

    if ($ReflectionsPath) { $script:DEFAULT_REFLECTIONS_PATH = $ReflectionsPath } else { _Init-ReflectionsPath }
    $path = $script:DEFAULT_REFLECTIONS_PATH
    if (-not (Test-Path $path)) { return @() }

    $byTradeId = @{}
    try {
        $lines = @(Get-Content $path -Encoding UTF8 -ErrorAction Stop)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop
                $tid = $obj.trade_id
                if (-not $byTradeId.ContainsKey($tid)) { $byTradeId[$tid] = @() }
                $byTradeId[$tid] += $obj
            } catch {}
        }
    } catch { return @() }

    # Pending = trade_ids onde nao existe entry status=resolved
    $pending = New-Object System.Collections.ArrayList
    foreach ($tid in $byTradeId.Keys) {
        $entries = $byTradeId[$tid]
        $hasResolved = @($entries | Where-Object { $_.status -eq "resolved" }).Count -gt 0
        if (-not $hasResolved) {
            $pendingEntry = @($entries | Where-Object { $_.status -eq "pending" } | Select-Object -First 1)[0]
            if ($pendingEntry) { [void]$pending.Add($pendingEntry) }
        }
    }
    return ,@($pending.ToArray())
}


function Add-ResolvedReflection {
    <#
    .SYNOPSIS
    Append entry "resolved" pra um trade_id pending, com outcome + reflection.

    .PARAMETER TradeId
    Mesmo que pending entry.

    .PARAMETER ExitDateUtc
    YYYY-MM-DD UTC fechamento.

    .PARAMETER PnlPct
    Trade return %.

    .PARAMETER AlphaVsBtc
    Alpha computed (Compute-AlphaVsBtc). Pode ser null se cache miss.

    .PARAMETER HoldingDays
    Quantos dias position aberta.

    .PARAMETER Reflection
    Texto distilled (geralmente 2-4 frases produzidas por Haiku).

    .PARAMETER ReflectionsPath
    Override (testing).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TradeId,
        [Parameter(Mandatory)] [string] $ExitDateUtc,
        [double] $PnlPct = 0,
        [Nullable[double]] $AlphaVsBtc = $null,
        [int] $HoldingDays = 0,
        [string] $Reflection = "",
        [string] $ReflectionsPath = ""
    )

    if ($ReflectionsPath) { $script:DEFAULT_REFLECTIONS_PATH = $ReflectionsPath } else { _Init-ReflectionsPath }
    $path = $script:DEFAULT_REFLECTIONS_PATH

    $entry = [ordered]@{
        trade_id        = $TradeId
        status          = "resolved"
        exit_date_utc   = $ExitDateUtc
        pnl_pct         = [math]::Round($PnlPct, 2)
        alpha_vs_btc    = if ($null -ne $AlphaVsBtc) { [math]::Round($AlphaVsBtc, 2) } else { $null }
        holding_days    = $HoldingDays
        reflection      = $Reflection
        resolved_at     = (Get-Date).ToUniversalTime().ToString("o")
    }

    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -Path $path -Value ($entry | ConvertTo-Json -Compress) -Encoding UTF8
}


function Get-PriorReflectionsForMarket {
    <#
    .SYNOPSIS
    Retorna ultimas N reflections RESOLVED para um market (chronological reverse).

    .DESCRIPTION
    Usado por Build-MentorFullContext pra injetar "PRIOR RESOLVED" block.

    .PARAMETER Market
    Market symbol.

    .PARAMETER MaxN
    Maximo de reflections (default 5).

    .PARAMETER ReflectionsPath
    Override (testing).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [int] $MaxN = 5,
        [string] $ReflectionsPath = ""
    )

    if ($ReflectionsPath) { $script:DEFAULT_REFLECTIONS_PATH = $ReflectionsPath } else { _Init-ReflectionsPath }
    $path = $script:DEFAULT_REFLECTIONS_PATH
    if (-not (Test-Path $path)) { return @() }

    # Aggregate by trade_id
    $byTradeId = @{}
    $resolvedEntries = @()
    try {
        $lines = @(Get-Content $path -Encoding UTF8 -ErrorAction Stop)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop
                $tid = $obj.trade_id
                if (-not $byTradeId.ContainsKey($tid)) { $byTradeId[$tid] = @{} }
                if ($obj.status -eq "pending") {
                    $byTradeId[$tid].pending = $obj
                } elseif ($obj.status -eq "resolved") {
                    $byTradeId[$tid].resolved = $obj
                }
            } catch {}
        }
    } catch { return @() }

    # Filtra: market match + resolved entries
    foreach ($tid in $byTradeId.Keys) {
        $pair = $byTradeId[$tid]
        if (-not $pair.pending -or -not $pair.resolved) { continue }
        if ($pair.pending.market -ne $Market) { continue }
        $resolvedEntries += [PSCustomObject]@{
            trade_id          = $tid
            market            = $pair.pending.market
            entry_date_utc    = $pair.pending.entry_date_utc
            exit_date_utc     = $pair.resolved.exit_date_utc
            mentor_veredicto  = $pair.pending.mentor_veredicto
            mentor_confidence = $pair.pending.mentor_confidence
            pnl_pct           = $pair.resolved.pnl_pct
            alpha_vs_btc      = $pair.resolved.alpha_vs_btc
            holding_days      = $pair.resolved.holding_days
            reflection        = $pair.resolved.reflection
            resolved_at       = $pair.resolved.resolved_at
        }
    }

    # Sort by resolved_at descending (most recent first), take MaxN
    $sorted = $resolvedEntries | Sort-Object -Property resolved_at -Descending | Select-Object -First $MaxN
    return @($sorted)
}


function Format-PriorReflectionsBlock {
    <#
    .SYNOPSIS
    Renderiza prior reflections como bloco pro Mentor prompt.

    .DESCRIPTION
    Output:
      === PRIOR RESOLVED DECISIONS (this market, last N) ===
      [2026-05-18 EXECUTAR conf=72] +3.2% alpha -1.1% vs BTC in 4d
        REFLECTION: Bull thesis on RENDER GPU narrative held; entry timing late (16% above trendline). Lesson: NEAR proximity scanner needed before entry.
      ...
      === END PRIOR ===

    .PARAMETER Reflections
    Array PSCustomObject from Get-PriorReflectionsForMarket.
    #>
    [CmdletBinding()]
    param([object[]] $Reflections = @())

    if (-not $Reflections -or $Reflections.Count -eq 0) { return "" }

    $lines = @("=== PRIOR RESOLVED DECISIONS (this market, last $($Reflections.Count)) ===")
    foreach ($r in $Reflections) {
        $alphaStr = if ($null -ne $r.alpha_vs_btc) { " alpha $($r.alpha_vs_btc)pp vs BTC" } else { " (alpha n/a)" }
        $lines += "[$($r.entry_date_utc) $($r.mentor_veredicto) conf=$($r.mentor_confidence)] $($r.pnl_pct)%$alphaStr in $($r.holding_days)d"
        if ($r.reflection) {
            $lines += "  REFLECTION: $($r.reflection)"
        }
    }
    $lines += "=== END PRIOR ==="

    return ($lines -join "`n")
}
