# lib_dashboard_metrics.ps1 — Metricas REAIS pro dashboard (2026-06-12)
# Motivo: update_dashboard_json.ps1 hardcodava win_rate=0/sharpe=0 sem ler
# journal/trade_outcomes.jsonl. Funcoes PURAS (zero API/IO) — TDD via Pester.
#
# 1. Get-TradePerformanceMetrics  — win rate / profit factor / PnL real
# 2. Get-PnlCurvePoints           — serie acumulada por dia (grafico SVG)
# 3. Get-WhaleActivitySummary     — trades grandes nos deals da CoinEx
#                                   (on-chain proxy gratis: tape reading)

# ── 1. Performance real a partir de trade_outcomes ───────────────────────────
# $Outcomes: objetos com pnl_usd, win, exit_date (schema trade_outcomes.jsonl)
function Get-TradePerformanceMetrics {
    param([object[]] $Outcomes = @())

    $valid = @($Outcomes | Where-Object { $null -ne $_ -and $null -ne $_.pnl_usd })
    if ($valid.Count -eq 0) {
        return [PSCustomObject]@{
            trades = 0; wins = 0; losses = 0; win_rate = 0
            total_pnl_usd = 0; profit_factor = 0
            avg_win_usd = 0; avg_loss_usd = 0; best_usd = 0; worst_usd = 0
        }
    }

    $wins   = @($valid | Where-Object { [double]$_.pnl_usd -gt 0 })
    $losses = @($valid | Where-Object { [double]$_.pnl_usd -le 0 })
    $grossWin  = ($wins   | ForEach-Object { [double]$_.pnl_usd } | Measure-Object -Sum).Sum
    $grossLoss = ($losses | ForEach-Object { [math]::Abs([double]$_.pnl_usd) } | Measure-Object -Sum).Sum
    if ($null -eq $grossWin)  { $grossWin = 0.0 }
    if ($null -eq $grossLoss) { $grossLoss = 0.0 }

    $allPnl = @($valid | ForEach-Object { [double]$_.pnl_usd })
    # profit factor: cap 999 quando nao ha perdas (divisao por zero)
    $pf = if ($grossLoss -gt 0) { [math]::Round($grossWin / $grossLoss, 2) }
          elseif ($grossWin -gt 0) { 999 } else { 0 }

    return [PSCustomObject]@{
        trades        = $valid.Count
        wins          = $wins.Count
        losses        = $losses.Count
        win_rate      = [math]::Round($wins.Count / $valid.Count * 100, 1)
        total_pnl_usd = [math]::Round(($allPnl | Measure-Object -Sum).Sum, 2)
        profit_factor = $pf
        avg_win_usd   = if ($wins.Count -gt 0)   { [math]::Round($grossWin / $wins.Count, 2) } else { 0 }
        avg_loss_usd  = if ($losses.Count -gt 0) { [math]::Round(-$grossLoss / $losses.Count, 2) } else { 0 }
        best_usd      = [math]::Round(($allPnl | Measure-Object -Maximum).Maximum, 2)
        worst_usd     = [math]::Round(($allPnl | Measure-Object -Minimum).Minimum, 2)
    }
}

# ── 2. Curva de PnL acumulado por dia ────────────────────────────────────────
# Agrupa por exit_date (yyyy-MM-dd) e acumula. Retorna pontos ordenados.
function Get-PnlCurvePoints {
    param([object[]] $Outcomes = @())

    $valid = @($Outcomes | Where-Object { $null -ne $_ -and $null -ne $_.pnl_usd -and $_.exit_date })
    if ($valid.Count -eq 0) { return @() }

    $byDay = $valid | Group-Object { "$($_.exit_date)".Substring(0, 10) } | Sort-Object Name
    $points = @()
    $cum = 0.0
    foreach ($g in $byDay) {
        $daily = (@($g.Group | ForEach-Object { [double]$_.pnl_usd }) | Measure-Object -Sum).Sum
        $cum += $daily
        $points += [PSCustomObject]@{
            date      = $g.Name
            daily_pnl = [math]::Round($daily, 2)
            cum_pnl   = [math]::Round($cum, 2)
            trades    = $g.Count
        }
    }
    return $points
}

# ── 3. Whale activity via deals (tape reading) ───────────────────────────────
# $Deals: objetos do CoinEx /v2/spot/deals ou /v2/futures/deals
#         (price, amount, side "buy"|"sell"). Trade >= WhaleUsdMin = whale print.
# WhaleUsdMin <= 0 => ADAPTATIVO: whale = print >= 8x a mediana do tape
#   (threshold fixo e cego entre BTC e micro-caps; outlier relativo escala).
# signal: ACCUMULATION (net whale buy forte) | DISTRIBUTION (net sell) | NEUTRAL
function Get-WhaleActivitySummary {
    param(
        [object[]] $Deals = @(),
        [double] $WhaleUsdMin = 0
    )

    $sizes = @()
    foreach ($d in $Deals) {
        if ($null -eq $d -or $null -eq $d.price -or $null -eq $d.amount) { continue }
        $sizes += [double]$d.price * [double]$d.amount
    }
    $threshold = $WhaleUsdMin
    if ($threshold -le 0 -and $sizes.Count -gt 0) {
        $sorted = @($sizes | Sort-Object)
        $median = $sorted[[math]::Floor($sorted.Count / 2)]
        $threshold = [math]::Max($median * 8, 50.0)  # floor $50 contra dust
    }

    $whaleBuys = 0; $whaleSells = 0
    $buyUsd = 0.0; $sellUsd = 0.0
    $largestUsd = 0.0; $largestSide = ""

    foreach ($d in $Deals) {
        if ($null -eq $d -or $null -eq $d.price -or $null -eq $d.amount) { continue }
        $usd = [double]$d.price * [double]$d.amount
        if ($usd -lt $threshold) { continue }
        $side = "$($d.side)".ToLower()
        if ($side -eq "buy") { $whaleBuys++; $buyUsd += $usd } else { $whaleSells++; $sellUsd += $usd }
        if ($usd -gt $largestUsd) { $largestUsd = $usd; $largestSide = $side }
    }

    $net = $buyUsd - $sellUsd
    # sinal exige dominancia 2:1 no volume whale (evita ruido de fluxo equilibrado)
    $signal = if ($buyUsd -gt 0 -and $buyUsd -ge $sellUsd * 2 -and $whaleBuys -ge 2) { "ACCUMULATION" }
              elseif ($sellUsd -gt 0 -and $sellUsd -ge $buyUsd * 2 -and $whaleSells -ge 2) { "DISTRIBUTION" }
              else { "NEUTRAL" }

    return [PSCustomObject]@{
        whale_buys    = $whaleBuys
        whale_sells   = $whaleSells
        buy_usd       = [math]::Round($buyUsd, 0)
        sell_usd      = [math]::Round($sellUsd, 0)
        net_usd       = [math]::Round($net, 0)
        largest_usd   = [math]::Round($largestUsd, 0)
        largest_side  = $largestSide
        threshold_usd = [math]::Round($threshold, 0)
        signal        = $signal
    }
}
