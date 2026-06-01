# trailing_stop_manager.ps1 — Logica pura de stop progressivo em 3 fases
# Sem I/O, sem API — testavel diretamente via Pester.
#
# Fase 1: Stop fixo         (price < entry + 1R)
# Fase 2: Break-even        (price >= entry + 1R  → stop = entry)
# Fase 3: Trailing ativo    (price >= entry + 2R  → stop segue peak)
#   STANDARD: stop = peak - ATR*2.0  (adaptativo a volatilidade)
#   GEM:      stop = peak * 0.80     (largo — micro-caps sao volateis)
#
# Moon bag (modo GEM apenas):
#   Quando price >= target → PARTIAL_EXIT 50%, restante continua com trailing

function Get-TrailingStopState {
    param(
        [double]$EntryPrice,
        [double]$InitialStop,
        [double]$CurrentPrice,
        [double]$PeakPrice,
        [double]$TargetPrice  = 0,
        [string]$Mode         = "STANDARD",   # STANDARD | GEM
        [double]$ATR          = 0,
        [double]$ATRMultiplier = 2.0,
        [double]$GemTrailPct  = 0.20
    )

    $riskR = [math]::Abs($EntryPrice - $InitialStop)

    # Evitar divisao por zero
    if ($riskR -eq 0) { $riskR = $EntryPrice * 0.01 }

    $result = [PSCustomObject]@{
        phase       = 1
        stop_price  = $InitialStop
        action      = "HOLD"
        partial_pct = 0
        message     = ""
    }

    # ── Moon bag (GEM): exit parcial ao atingir target ────────────────────────
    if ($Mode -eq "GEM" -and $TargetPrice -gt 0 -and $CurrentPrice -ge $TargetPrice) {
        $trailStop = [math]::Max($PeakPrice * (1 - $GemTrailPct), $EntryPrice)
        $result.phase       = 3
        $result.stop_price  = [math]::Round($trailStop, 8)
        $result.action      = "PARTIAL_EXIT"
        $result.partial_pct = 50
        $result.message     = "Target atingido - sair 50%, moon bag com trailing $([int]($GemTrailPct*100))%"
        return $result
    }

    # ── Fase 3: Trailing ativo (price >= entry + 2R) ──────────────────────────
    if ($PeakPrice -ge ($EntryPrice + 2 * $riskR)) {
        $trailStop = if ($Mode -eq "GEM") {
            [math]::Max($PeakPrice * (1 - $GemTrailPct), $EntryPrice)
        } elseif ($ATR -gt 0) {
            $PeakPrice - ($ATR * $ATRMultiplier)
        } else {
            $PeakPrice * 0.97   # fallback 3%
        }
        $trailStop = [math]::Max($trailStop, $EntryPrice)  # nunca abaixo de entry

        $result.phase      = 3
        $result.stop_price = [math]::Round($trailStop, 8)
        $result.action     = if ($CurrentPrice -le $trailStop) { "STOP_HIT" } else { "MOVE_STOP" }
        $result.message    = "Trailing ativo - peak=$PeakPrice stop=$([math]::Round($trailStop,4))"
        return $result
    }

    # ── Fase 2: Break-even (price >= entry + 1R) ─────────────────────────────
    if ($PeakPrice -ge ($EntryPrice + $riskR)) {
        $result.phase      = 2
        $result.stop_price = $EntryPrice
        $result.action     = if ($CurrentPrice -le $EntryPrice) { "STOP_HIT" } else { "MOVE_STOP" }
        $result.message    = "Break-even ativado - stop movido para entry=$EntryPrice"
        return $result
    }

    # ── Fase 1: Stop fixo ─────────────────────────────────────────────────────
    $result.phase      = 1
    $result.stop_price = $InitialStop
    $result.action     = if ($CurrentPrice -le $InitialStop) { "STOP_HIT" } else { "HOLD" }
    $result.message    = "Fase 1 - stop fixo em $InitialStop"
    return $result
}

# ─────────────────────────────────────────────────────────────────────────────
# Record-GemTradeClosed
# Helper a ser chamado por callers de Get-TrailingStopState quando uma posicao
# GEM efetivamente fecha. Mapeia exit_reason -> WIN|LOSS|STOP|EXPIRED e
# delega para Add-GemTradeResult (lib_gem_safety.ps1).
# ─────────────────────────────────────────────────────────────────────────────
function Record-GemTradeClosed {
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $PnlUsdt,
        [Parameter(Mandatory)] [string] $ExitReason  # STOP_LOSS | TIMEOUT | TARGET | MANUAL
    )

    $libPath = Join-Path $PSScriptRoot "lib_gem_safety.ps1"
    if (-not (Test-Path $libPath)) { return }
    . $libPath

    $result = if     ($PnlUsdt -gt 0)              { "WIN" }
              elseif ($ExitReason -eq "STOP_LOSS") { "STOP" }
              elseif ($ExitReason -eq "TIMEOUT")   { "EXPIRED" }
              else                                 { "LOSS" }

    Add-GemTradeResult -Market $Market -Result $result -PnlUsdt $PnlUsdt
}
