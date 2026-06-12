# lib_faro_momentum.ps1 — RSI + MACD
function Calculate-RSI {
    param([array] $Closes, [int] $Period = 14)
    if ($Closes.Count -lt $Period + 1) { return 50 }
    $gains = 0; $losses = 0
    for ($i = $Closes.Count - $Period; $i -lt $Closes.Count; $i++) {
        $change = $Closes[$i] - $Closes[$i - 1]
        if ($change -gt 0) { $gains += $change } else { $losses += -$change }
    }
    $avgGain = $gains / $Period
    $avgLoss = $losses / $Period
    if ($avgLoss -eq 0) { return 100 }
    $rs = $avgGain / $avgLoss
    return 100 - (100 / (1 + $rs))
}
function Get-Momentum {
    param([array] $Closes, [decimal] $RSI = 0, [decimal] $MACD = 0, [decimal] $SignalLine = 0)
    if (-not $Closes -or $Closes.Count -lt 14) { return 0 }
    $score = 0
    if ($RSI -eq 0) { $RSI = Calculate-RSI -Closes $Closes -Period 14 }
    if ($RSI -ge 30 -and $RSI -le 60) { $score += 15 }
    elseif ($RSI -gt 60 -and $RSI -le 70) { $score += 8 }
    if ($MACD -ne 0 -and $SignalLine -ne 0) {
        if ($MACD -gt $SignalLine) { $score += 10 }
    }
    return [Math]::Min($score, 25)
}
