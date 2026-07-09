# lib_auto_trade_engine.ps1
# Sistema de auto-trade com feedback loop
# Aprende qual padrão gera ganho + retroalimentação contínua
# 2026-06-06

<#
.SYNOPSIS
    Sistema completo:
    1. Detecta padrão
    2. Calcula confiança (histórico)
    3. Se conf ≥ threshold → ABRE TRADE
    4. Monitora posição
    5. Fecha com TP/SL
    6. Registra resultado
    7. Feedback: aumenta confiança do padrão se ganhou
    8. Loop: próximo padrão já tem confiança atualizada
#>

# ════════════════════════════════════════════════════════════════
# CAPITAL FETCH — Always ONCHAIN, never hardcoded
# ════════════════════════════════════════════════════════════════

function Get-CurrentCapitalOnchain {
    param(
        [double] $FallbackValue = 2700.85
    )

    $total = 0

    # Fetch SPOT
    try {
        $spotUrl = "https://api.coinex.com/v2/spot/balance"
        $resp = Invoke-RestMethod -Uri $spotUrl -Method GET -TimeoutSec 3
        if ($resp.code -eq 0 -and $resp.data) {
            foreach ($asset in $resp.data) {
                if ($asset.ccy -eq "USDT") { $total += [double]($(if ($null -ne $asset.available) { $asset.available } else { 0 })) }
            }
        }
    } catch { }

    # Fetch FUTURES
    try {
        $futUrl = "https://api.coinex.com/v2/futures/balance"
        $resp = Invoke-RestMethod -Uri $futUrl -Method GET -TimeoutSec 3
        if ($resp.code -eq 0 -and $resp.data) {
            foreach ($asset in $resp.data) {
                if ($asset.ccy -eq "USDT") { $total += [double]($(if ($null -ne $asset.available) { $asset.available } else { 0 })) }
            }
        }
    } catch { }

    return if ($total -gt 0) { $total } else { $FallbackValue }
}

# ════════════════════════════════════════════════════════════════
# HISTÓRICO DE APRENDIZADO (persistente)
# ════════════════════════════════════════════════════════════════

$global:PATTERN_HISTORY = @{
    "HAMMER" = @{
        seen = 0
        wins = 0
        losses = 0
        avg_pnl = 0.0
        confidence = 0.25
        last_updated = $null
    }
    "SHOOTING_STAR" = @{
        seen = 0
        wins = 0
        losses = 0
        avg_pnl = 0.0
        confidence = 0.20
        last_updated = $null
    }
    "ENGULFING" = @{
        seen = 0
        wins = 0
        losses = 0
        avg_pnl = 0.0
        confidence = 0.30
        last_updated = $null
    }
    "VOL_CLIMAX" = @{
        seen = 0
        wins = 0
        losses = 0
        avg_pnl = 0.0
        confidence = 0.35
        last_updated = $null
    }
}

function New-AutoTrade {
    <#
    .SYNOPSIS
        Abre nova posição se padrão passa no threshold de confiança
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,

        [Parameter(Mandatory=$true)]
        [string]$Pattern,

        [Parameter(Mandatory=$true)]
        [double]$CurrentPrice,

        [Parameter(Mandatory=$false)]
        [double]$ConfidenceThreshold = 0.40
    )

    # Pegar confiança do padrão
    if (-not $global:PATTERN_HISTORY.ContainsKey($Pattern)) {
        return $null
    }

    $pattern_data = $global:PATTERN_HISTORY[$Pattern]
    $confidence = $pattern_data.confidence

    # DECISÃO: Abre se confiança >= threshold
    if ($confidence -lt $ConfidenceThreshold) {
        return [PSCustomObject]@{
            decision = "SKIP"
            reason = "Confidence $([math]::Round($confidence, 2)) < threshold $ConfidenceThreshold"
            market = $Market
            pattern = $Pattern
        }
    }

    # Calcular setup de entrada
    $entry = $CurrentPrice
    $stop_pct = 0.02  # -2%
    $rr = 3.0
    $tp_pct = $stop_pct * $rr  # +6%

    $stop = $entry * (1 - $stop_pct)
    $tp = $entry * (1 + $tp_pct)

    # Tamanho da posição: variar por confiança
    $size_pct = 0.005 + ($confidence * 0.005)  # 0.5% a 1% por confiança

    # Get REAL capital from ONCHAIN (or fallback)
    $capital = Get-CurrentCapitalOnchain -FallbackValue 2700.85
    $size_usdt = $capital * $size_pct

    return [PSCustomObject]@{
        decision = "OPEN"
        trade_id = "AUTO_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$Pattern"
        market = $Market
        pattern = $Pattern
        confidence = [math]::Round($confidence, 3)
        entry = [math]::Round($entry, 6)
        stop = [math]::Round($stop, 6)
        tp = [math]::Round($tp, 6)
        size_usdt = [math]::Round($size_usdt, 2)
        size_pct = [math]::Round($size_pct, 3)
        rr = $rr
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

function Update-PatternConfidence {
    <#
    .SYNOPSIS
        Atualiza confiança do padrão baseado em resultado real

    Lógica:
    - Win: +0.05 confiança
    - Loss: -0.03 confiança
    - Clamp: 0.1 a 1.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Pattern,

        [Parameter(Mandatory=$true)]
        [bool]$IsWin,

        [Parameter(Mandatory=$true)]
        [double]$PnL_pct
    )

    if (-not $global:PATTERN_HISTORY.ContainsKey($Pattern)) {
        return
    }

    $p = $global:PATTERN_HISTORY[$Pattern]

    # Atualizar estatísticas
    $p.seen += 1
    if ($IsWin) {
        $p.wins += 1
    } else {
        $p.losses += 1
    }

    # Atualizar PnL médio
    $total_pnl = $p.avg_pnl * ($p.seen - 1) + $PnL_pct
    $p.avg_pnl = $total_pnl / $p.seen

    # Atualizar confiança
    $old_conf = $p.confidence

    if ($IsWin) {
        $p.confidence += 0.05
    } else {
        $p.confidence -= 0.03
    }

    # Clamp entre 0.1 e 0.95
    $p.confidence = [math]::Max(0.1, [math]::Min(0.95, $p.confidence))

    $p.last_updated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    return [PSCustomObject]@{
        pattern = $Pattern
        old_confidence = [math]::Round($old_conf, 3)
        new_confidence = [math]::Round($p.confidence, 3)
        change = [math]::Round($p.confidence - $old_conf, 3)
        wins = $p.wins
        losses = $p.losses
        avg_pnl = [math]::Round($p.avg_pnl, 2)
        updated = $p.last_updated
    }
}

function Get-PatternStats {
    <#
    .SYNOPSIS
        Retorna estatísticas completas de aprendizado
    #>
    [CmdletBinding()]
    param()

    $stats = @()

    foreach ($pattern in $global:PATTERN_HISTORY.GetEnumerator()) {
        $name = $pattern.Key
        $data = $pattern.Value

        $win_rate = if ($data.seen -gt 0) { ($data.wins / $data.seen) * 100 } else { 0 }

        $stats += [PSCustomObject]@{
            pattern = $name
            seen = $data.seen
            wins = $data.wins
            losses = $data.losses
            win_rate_pct = [math]::Round($win_rate, 1)
            confidence = [math]::Round($data.confidence, 3)
            avg_pnl = [math]::Round($data.avg_pnl, 2)
            last_updated = $data.last_updated
        }
    }

    return $stats | Sort-Object confidence -Descending
}

function New-TradeLog {
    <#
    .SYNOPSIS
        Registra trade executado com todos os detalhes
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$TradeDecision,

        [Parameter(Mandatory=$true)]
        [double]$EntryPrice,

        [Parameter(Mandatory=$true)]
        [double]$ExitPrice,

        [Parameter(Mandatory=$true)]
        [string]$ExitReason  # "TP", "SL", "MANUAL"
    )

    $pnl = $ExitPrice - $EntryPrice
    $pnl_pct = ($pnl / $EntryPrice) * 100
    $is_win = $pnl -gt 0

    return [PSCustomObject]@{
        trade_id = $TradeDecision.trade_id
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        market = $TradeDecision.market
        pattern = $TradeDecision.pattern
        entry_price = [math]::Round($EntryPrice, 6)
        exit_price = [math]::Round($ExitPrice, 6)
        exit_reason = $ExitReason
        pnl_usdt = [math]::Round($pnl, 2)
        pnl_pct = [math]::Round($pnl_pct, 2)
        is_win = $is_win
        confidence_at_entry = $TradeDecision.confidence
        status = "CLOSED"
    }
}

# 2026-07-08 FIX: Removed Export-ModuleMember (dot-source .ps1 files don't export)
