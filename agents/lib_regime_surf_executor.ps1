# lib_regime_surf_executor.ps1 -- wiring do surf SHORT (decisao -> ordem futures real).
# 2026-06-30: liga o cerebro PURO (Resolve-RegimeSurfDecision) a execucao real.
#
# SEGURANCA (shadow-first, padrao do projeto tipo CLOUD_DRY_RUN):
#   - SEM journal/REGIME_SURF_SHORT_LIVE.flag -> SHADOW: loga o SHORT pretendido em
#     journal/regime_surf_shadow.jsonl + TG, NAO coloca ordem. Prova a decisao em dado
#     vivo sem risco. Vira live flipando 1 flag.
#   - COM a flag -> LIVE: CoinEx-PlaceOrder futures sell + stop OBRIGATORIO + registro.
#   - Sizing micro por default (RiskPct 0.3% = ~$15 risco em $5k) ate provar edge.
#   - Stop SEMPRE da decisao (fail-closed): sem stop = sem ordem.

. (Join-Path $PSScriptRoot "lib_regime_surf.ps1")
. (Join-Path $PSScriptRoot "lib_market_type_detector.ps1")  # 2026-06-30: deteccao automatica FUTURES vs SPOT

function Invoke-RegimeSurfShort {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory=$true)][string]$Market,
        [Parameter(Mandatory=$true)][double]$Price,
        [Parameter(Mandatory=$true)]$Scenario,
        [double]$Momentum30dPct = 0,
        [double]$ShortConviction = 0,
        [double]$Capital = 0,
        [double]$RiskPct = 0.3,        # micro ate provar edge
        [double]$StopPct = 8,
        [double]$RR = 1.5,
        [string]$JournalDir = "journal",
        [switch]$ForceDryRun
    )

    # ── 1. Decisao PURA ──
    $d = Resolve-RegimeSurfDecision -Market $Market -Scenario $Scenario -Price $Price `
        -Momentum30dPct $Momentum30dPct -ShortConviction $ShortConviction -Capital $Capital `
        -RiskPct $RiskPct -StopPct $StopPct -RR $RR

    if (-not $d.act -or $d.direction -ne "SHORT") {
        return [pscustomobject]@{ executed=$false; dry_run=$false; market=$Market; reason="no_short:$($d.reason)"; decision=$d }
    }

    # ── Deteccao automatica: FUTURES ou SPOT? ──
    # 2026-06-30: Detecta automaticamente se mercado tem contrato de futures.
    # Se SIM → SHORT em futures (fail-closed, stop na corretora).
    # Se NAO → pula SHORT (SPOT margin/borrow e mais risco, deixa pra provar edge depois).
    $marketType = if (Get-Command Get-MarketType -ErrorAction SilentlyContinue) {
        Get-MarketType -Market $Market
    } else {
        "SPOT"  # fallback conservador
    }
    if ($marketType -ne "FUTURES") {
        return [pscustomobject]@{ executed=$false; dry_run=$false; market=$Market; reason="market_type_$marketType (nao futures)"; decision=$d }
    }

    # ── 2. Dedup: ja short nesse mercado? (best-effort) ──
    if (Get-Command Test-CoinExposureCap -ErrorAction SilentlyContinue) {
        try {
            $cap = Test-CoinExposureCap -HeldUsd 0 -TradeUsd $d.size_usd -PortfolioUsd $Capital
            if ($cap -and -not $cap.allowed) {
                return [pscustomobject]@{ executed=$false; dry_run=$false; market=$Market; reason="exposure_cap:$($cap.reason)"; decision=$d }
            }
        } catch {}
    }

    # ── 3. Gate live vs shadow ──
    $liveFlag = Join-Path $JournalDir "REGIME_SURF_SHORT_LIVE.flag"
    $live = (Test-Path $liveFlag) -and (-not $ForceDryRun)

    $amount = if ($Price -gt 0) { [math]::Round($d.size_usd / $Price, 6) } else { 0 }

    # ── 4. SHADOW: loga sem executar ──
    if (-not $live) {
        $shadow = [pscustomobject]@{
            ts=(Get-Date -Format "o"); mode="SHADOW"; market=$Market; direction="SHORT";
            entry=$d.entry; stop=$d.stop; target=$d.target; size_usd=$d.size_usd;
            risk_usd=$d.risk_usd; amount=$amount; scenario=$d.scenario; reason=$d.reason
        }
        try {
            New-Item -ItemType Directory -Path $JournalDir -Force -ErrorAction SilentlyContinue | Out-Null
            $shadow | ConvertTo-Json -Compress | Add-Content (Join-Path $JournalDir "regime_surf_shadow.jsonl")
        } catch {}
        if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
            try { Send-TelegramAlert -Message "SHADOW SHORT $Market @ $($d.entry) | stop $($d.stop) | alvo $($d.target) | risco `$$($d.risk_usd) | $($d.scenario)" | Out-Null } catch {}
        }
        return [pscustomobject]@{ executed=$false; dry_run=$true; market=$Market; reason="shadow_logged"; decision=$d; amount=$amount }
    }

    # ── 5. LIVE: ordem futures sell + stop obrigatorio + registro ──
    if ($amount -le 0) {
        return [pscustomobject]@{ executed=$false; dry_run=$false; market=$Market; reason="amount_zero"; decision=$d }
    }
    try {
        $order = CoinEx-PlaceOrder $Market "sell" "market" $amount $null $d.stop $d.target
        $orderId = if ($order -and $order.data -and $order.data.order_id) { [string]$order.data.order_id } else { "" }

        if (Get-Command Register-PositionTrailing -ErrorAction SilentlyContinue) {
            try {
                Register-PositionTrailing -Market $Market -Side "SHORT" -Entry $d.entry `
                    -Stop $d.stop -Target $d.target -OrderId $orderId -Source "regime_surf" | Out-Null
            } catch {}
        }
        if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
            try { Send-TelegramAlert -Message "LIVE SHORT $Market @ $($d.entry) | stop $($d.stop) | alvo $($d.target) | risco `$$($d.risk_usd) | order $orderId" | Out-Null } catch {}
        }
        return [pscustomobject]@{ executed=$true; dry_run=$false; market=$Market; reason="short_placed"; order_id=$orderId; decision=$d; amount=$amount }
    } catch {
        return [pscustomobject]@{ executed=$false; dry_run=$false; market=$Market; reason="order_failed:$_"; decision=$d }
    }
}
