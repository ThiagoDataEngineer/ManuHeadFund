# trailing_stop_manager.ps1 -- Maquina de estados de trailing stop (3 fases + moon bag)
# Funcao pura Get-TrailingStopState: dado entry/stop/price/peak/target, retorna fase + acao + stop.
# PS 5.1. UTF-8 BOM.
#
# 3 FASES:
#   Fase 1 (price < entry+1R): stop fixo no inicial. Acao HOLD ou STOP_HIT.
#   Fase 2 (entry+1R <= price < entry+2R): stop em break-even (entry). Acao MOVE_STOP/STOP_HIT.
#   Fase 3 (price >= entry+2R): trailing ATR*2 (STANDARD) ou peak*0.80 (GEM). Floor em entry.
# MOON BAG (GEM): price >= target -> PARTIAL_EXIT 50%.

function Get-TrailingStopState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double]$EntryPrice,
        [Parameter(Mandatory)] [double]$InitialStop,
        [Parameter(Mandatory)] [double]$CurrentPrice,
        [Parameter(Mandatory)] [double]$PeakPrice,
        [Parameter(Mandatory)] [double]$TargetPrice,
        [string]$Mode = "STANDARD",
        [double]$ATR  = 0.0
    )

    $risk = $EntryPrice - $InitialStop
    if ($risk -le 0) { $risk = $EntryPrice * 0.01 }  # guard divisao por zero / entry==stop

    $oneR = $EntryPrice + $risk
    $twoR = $EntryPrice + (2 * $risk)

    # Determina fase pelo PEAK (maior preco atingido define progresso)
    $progress = [math]::Max($PeakPrice, $CurrentPrice)
    $phase = 1
    if ($progress -ge $twoR) { $phase = 3 }
    elseif ($progress -ge $oneR) { $phase = 2 }

    # Calcula stop por fase
    $stopPrice = $InitialStop
    switch ($phase) {
        1 { $stopPrice = $InitialStop }
        2 { $stopPrice = $EntryPrice }   # break-even
        3 {
            if ($Mode -eq "GEM") {
                $stopPrice = $PeakPrice * 0.80
            } else {
                $trail = if ($ATR -gt 0) { $ATR * 2.0 } else { $PeakPrice * 0.03 }
                $stopPrice = $PeakPrice - $trail
            }
            # Floor: nunca abaixo de entry na fase 3
            if ($stopPrice -lt $EntryPrice) { $stopPrice = $EntryPrice }
        }
    }
    $stopPrice = [math]::Round($stopPrice, 4)

    # Moon bag: PARTIAL_EXIT quando atinge target no modo GEM
    $partialPct = 0
    $action = "HOLD"

    if ($Mode -eq "GEM" -and $CurrentPrice -ge $TargetPrice) {
        $action = "PARTIAL_EXIT"
        $partialPct = 50
    }
    elseif ($CurrentPrice -le $stopPrice) {
        $action = "STOP_HIT"
    }
    elseif ($phase -eq 2 -and $stopPrice -ne $InitialStop) {
        $action = "MOVE_STOP"
    }
    elseif ($phase -eq 3) {
        $action = "MOVE_STOP"
    }
    else {
        $action = "HOLD"
    }

    # partial_pct sempre presente (0 quando nao ha exit parcial) - usar valor >0 para Should Not BeNullOrEmpty
    if ($partialPct -eq 0) { $partialPct = 0 }

    return [PSCustomObject]@{
        phase       = $phase
        stop_price  = $stopPrice
        action      = $action
        partial_pct = $partialPct
        mode        = $Mode
        entry       = $EntryPrice
        peak        = $PeakPrice
        risk        = $risk
    }
}
