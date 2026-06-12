# lib_bidirectional_gates.ps1 — LONG/SHORT simultâneos (OPERACIONAL)

function Test-LongGate {
    param([double]$score, [double]$pctAboveMin)
    ($score -ge 60) -and ($pctAboveMin -le 5)
}

function Test-ShortGate {
    param([double]$score, [double]$pctBelowMax)
    ($score -ge 60) -and ($pctBelowMax -le 5)
}

function Test-CanHaveBoth {
    param([string]$market1, [string]$market2)
    $market1 -ne $market2  # Pares DIFERENTES
}

function Get-LongStopTarget {
    param([double]$entry)
    @{
        stop   = $entry * 0.95   # -5%
        target = $entry * 1.25   # +25% (5R com -5% stop)
    }
}

function Get-ShortStopTarget {
    param([double]$entry)
    @{
        stop   = $entry * 1.05   # +5%
        target = $entry * 0.75   # -25% (5R com +5% stop)
    }
}

function Test-DailyLossOk {
    param([double]$dailyLoss)
    $dailyLoss -gt -0.02  # Respeita cap -2%
}

function Get-Priority {
    param([double]$pctAboveMin, [double]$pctBelowMax)
    if ($pctAboveMin -lt $pctBelowMax) { "LONG" } else { "SHORT" }
}
