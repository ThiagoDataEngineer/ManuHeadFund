# lib_pump_scalper.ps1 — PUMP SCALP automático LIVE (sempre executa, não shadow).
# 2026-06-30: Detecta early pump (2-5% início) + sai em +5% = $275 por $5.5k
# Target: 4 pumps/dia = $1100/dia

. (Join-Path $PSScriptRoot "lib_leverage_cap.ps1")  # 2026-07-19: Oracle Bug #15 -- cap 5x antes de ordem futures real
. (Join-Path $PSScriptRoot "lib_coinex_position_management.ps1")

function Detect-EarlyPump {
    <#
    .SYNOPSIS
    Detecta se um mercado está em PUMP EARLY (primeiros 2-5% do movimento).

    .PARAMETER Market
    Símbolo (ex: AIUSDT)

    .PARAMETER ChangePercent24h
    Mudança 24h atual (ex: 0.92 para +92%)

    .PARAMETER VolumeRatio
    Volume agora vs mediana 24h (ex: 2.5 = 2.5x)

    .PARAMETER RSI
    RSI atual (0-100)

    .OUTPUTS
    @{
      is_pump = $true | $false
      pump_stage = "early" | "mid" | "late" | "none"
      confidence = 0-100
      entry_price = X
      target_price = X (entry * 1.05)
      stop_price = X (entry * 0.97)
    }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)][string]$Market,
        [double]$ChangePercent24h = 0,
        [double]$VolumeRatio = 1.0,
        [double]$RSI = 50,
        [double]$CurrentPrice = 0
    )

    # ── PUMP EARLY detection ──
    # Sinais combinados: volume spike + momentum + RSI em transicao
    $isPump = $false
    $confidence = 0
    $pumpStage = "none"

    # Signal 1: Volume 2x+ mediana
    if ($VolumeRatio -ge 2.0) { $confidence += 25 }

    # Signal 2: Gainer top 1-2% (qualquer % acima é pump)
    if ($ChangePercent24h -gt 0.02) { $confidence += 25 }

    # Signal 3: RSI transitioning (30-70, não extremo)
    if ($RSI -gt 30 -and $RSI -lt 70) { $confidence += 20 }

    # Signal 4: Breakout (está quebrando resistência)
    # Heurístico: if volume spike + price up = provavelmente em movimento
    if ($VolumeRatio -gt 1.5 -and $ChangePercent24h -gt 0.01) { $confidence += 30 }

    # ── Classify pump stage ──
    if ($confidence -ge 70) {
        $isPump = $true
        # Early: < 10% movimento total
        # Mid: 10-50% movimento total
        # Late: > 50% movimento total
        if ($ChangePercent24h -lt 0.10) { $pumpStage = "early" }
        elseif ($ChangePercent24h -lt 0.50) { $pumpStage = "mid" }
        else { $pumpStage = "late" }
    }

    # ── Entry/target/stop ──
    $entry = $CurrentPrice
    $target = $entry * 1.05      # +5% target (escopo realista)
    $stop = $entry * 0.97        # -3% stop (tight risco)

    return [PSCustomObject]@{
        market = $Market
        is_pump = $isPump
        pump_stage = $pumpStage
        confidence = [math]::Min(100, $confidence)
        entry_price = [math]::Round($entry, 8)
        target_price = [math]::Round($target, 8)
        stop_price = [math]::Round($stop, 8)
        entry_target_pct = 5.0
        stop_loss_pct = -3.0
        reason = if ($isPump) { "pump_$pumpStage confidence=$confidence" } else { "not_pump confidence=$confidence" }
    }
}

function Invoke-PumpScalp {
    <#
    .SYNOPSIS
    Executa SCALP automático em pump detectado. SEMPRE LIVE (não shadow).

    .PARAMETER Market
    Símbolo (ex: AIUSDT)

    .PARAMETER EntryPrice
    Preço de entrada (agora)

    .PARAMETER TargetPrice
    Target +5%

    .PARAMETER StopPrice
    Stop -3%

    .PARAMETER RiskUsd
    Risco em $ (ex: $55 = 1% de $5500 capital)

    .OUTPUTS
    @{
      executed = $true | $false
      order_id = "xxx"
      entry = X
      target = X
      stop = X
      size_usd = X
      timestamp = now
      status = "live_waiting_exit" | "hit_target" | "hit_stop" | "timeout" | "failed"
    }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)][string]$Market,
        [Parameter(Mandatory=$true)][double]$EntryPrice,
        [Parameter(Mandatory=$true)][double]$TargetPrice,
        [Parameter(Mandatory=$true)][double]$StopPrice,
        [double]$RiskUsd = 55,
        [int]$TimeoutMinutes = 120,  # 2h timeout
        [string]$JournalDir = "journal"
    )

    # ── 1. Size calculation (risk-based) ──
    if ($EntryPrice -le 0 -or $StopPrice -le 0 -or $EntryPrice -eq $StopPrice) {
        return [PSCustomObject]@{
            executed = $false
            market = $Market
            reason = "invalid_sizing (entry=$EntryPrice stop=$StopPrice)"
            entry = $EntryPrice
            target = $TargetPrice
            stop = $StopPrice
        }
    }

    $stopDist = ($EntryPrice - $StopPrice) / $EntryPrice
    if ($stopDist -le 0 -or [double]::IsInfinity($stopDist)) {
        return [PSCustomObject]@{
            executed = $false
            market = $Market
            reason = "invalid_sizing (entry=$EntryPrice stop=$StopPrice)"
            entry = $EntryPrice
            target = $TargetPrice
            stop = $StopPrice
        }
    }

    $notional = $RiskUsd / $stopDist

    # ── 2. Place order LIVE (não mock) ──
    $orderId = ""
    $orderResult = $null

    # Leverage cap (Oracle Bug #15): CoinEx-PlaceOrder abre FUTURES sempre
    # (market_type hard-coded); POST /futures/order NAO carrega leverage no
    # payload -- corretora usa o que ja estiver na conta. Fail-closed: se o
    # ajuste falhar, bloqueia a ordem em vez de herdar leverage desconhecida.
    $__safeLeverage = if (Get-Command Get-SafeLeverage -ErrorAction SilentlyContinue) {
        [int](Get-SafeLeverage -Mode "PUMP_RIDE")
    } else { 2 }
    $__levResult = if (Get-Command CoinEx-AdjustPositionLeverage -ErrorAction SilentlyContinue) {
        CoinEx-AdjustPositionLeverage -Market $Market -Leverage $__safeLeverage -MarginMode "isolated"
    } else { [PSCustomObject]@{ success = $false; error_msg = "CoinEx-AdjustPositionLeverage indisponivel" } }
    if (-not $__levResult.success) {
        return [PSCustomObject]@{
            executed = $false
            market = $Market
            reason = "leverage_adjust_failed:$($__levResult.error_msg)"
            entry = $EntryPrice
            target = $TargetPrice
            stop = $StopPrice
        }
    }

    try {
        if (Get-Command CoinEx-PlaceOrder -ErrorAction SilentlyContinue) {
            $orderResult = CoinEx-PlaceOrder $Market "buy" "market" $notional $null $StopPrice $TargetPrice
            if ($orderResult -and $orderResult.data -and $orderResult.data.order_id) {
                $orderId = [string]$orderResult.data.order_id
            }
        }
    } catch {
        Write-Host "[PUMP SCALP] Order failed: $_" -ForegroundColor Red
        return [PSCustomObject]@{
            executed = $false
            market = $Market
            reason = "order_failed: $_"
            entry = $EntryPrice
            target = $TargetPrice
            stop = $StopPrice
        }
    }

    # ── 3. Log to journal + Telegram ──
    $scalp = [PSCustomObject]@{
        ts = (Get-Date -Format "o")
        market = $Market
        entry = [math]::Round($EntryPrice, 8)
        target = [math]::Round($TargetPrice, 8)
        stop = [math]::Round($StopPrice, 8)
        size_usd = [math]::Round($notional, 2)
        risk_usd = [math]::Round($RiskUsd, 2)
        order_id = $orderId
        status = "live_waiting"
        timeout_minutes = $TimeoutMinutes
    }

    try {
        New-Item -ItemType Directory -Path $JournalDir -Force -ErrorAction SilentlyContinue | Out-Null
        $scalp | ConvertTo-Json -Compress | Add-Content (Join-Path $JournalDir "pump_scalps_live.jsonl")
    } catch {}

    # Telegram alert
    if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
        try {
            $msg = if (Get-Command Format-TelegramTradeAlert -ErrorAction SilentlyContinue) {
                Format-TelegramTradeAlert -Market $Market -Direction "LONG" -Entry $EntryPrice -Stop $StopPrice -Target $TargetPrice -SizeUsd $notional -RiskUsd $RiskUsd -OrderId $orderId -Type "pump"
            } else {
                "🚀 PUMP SCALP LIVE [$Market] Entry: $EntryPrice | Target: +5% = $TargetPrice | Stop: -3% = $StopPrice | Size: $([math]::Round($notional,2)) USD | Order: $orderId"
            }
            Send-TelegramAlert -Message $msg | Out-Null
        } catch {}
    }

    return [PSCustomObject]@{
        executed = $true
        market = $Market
        order_id = $orderId
        entry = [math]::Round($EntryPrice, 8)
        target = [math]::Round($TargetPrice, 8)
        stop = [math]::Round($StopPrice, 8)
        size_usd = [math]::Round($notional, 2)
        risk_usd = [math]::Round($RiskUsd, 2)
        timestamp = (Get-Date -Format "o")
        status = "live_waiting_exit"
        reason = "pump_scalp_live"
    }
}

# SEMPRE LIVE (nao tem shadow flag)
