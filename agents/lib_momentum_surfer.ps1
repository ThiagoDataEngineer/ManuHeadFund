# lib_momentum_surfer.ps1 — Surfa movimentos (OPERACIONAL)
# Entra no MEIO de trends já em andamento

function Get-MomentumScore {
    param([double[]]$closes, [double[]]$volumes)

    # Slope (40 pontos)
    $slope = ((($closes[-1] - $closes[0]) / $closes[0]) * 100)
    $slopeScore = [math]::Min(40, [math]::Abs($slope * 8))

    # Volume (30 pontos)
    $volRatio = if ($volumes[0] -gt 0) { $volumes[-1] / $volumes[0] } else { 1 }
    $volScore = [math]::Min(30, ($volRatio * 10))

    # Consistency (30 pontos)
    $upCount = 0
    for ($i = 1; $i -lt $closes.Count; $i++) {
        if ($closes[$i] -gt $closes[$i-1]) { $upCount++ }
    }
    $consistency = ($upCount / $closes.Count) * 30

    $slopeScore + $volScore + $consistency
}

function Test-CanSurfMomentum {
    param([double]$momentum, [double]$rr)
    ($momentum -gt 50) -and ($rr -gt 3)
}

function Get-SizeAdjustment {
    param([double]$score)
    if ($score -gt 80) { 1.0 }
    elseif ($score -gt 60) { 0.7 }
    else { 0.5 }
}

function Test-ExitSignal {
    param([double]$momentum, [double]$currentPrice, [double]$targetPrice, [double]$stopPrice)

    ($momentum -lt 40) -or
    ($currentPrice -ge $targetPrice) -or
    ($currentPrice -le $stopPrice)
}
