# lib_minmax_detector.ps1 — Fast minmax detection (OPERACIONAL)
# Detecta mínimas/máximas 24h/7d em qualquer par

function Get-Min24h {
    param([PSCustomObject[]]$candles)
    $candles | ForEach-Object { $_.low } | Measure-Object -Minimum | Select-Object -ExpandProperty Minimum
}

function Get-Max24h {
    param([PSCustomObject[]]$candles)
    $candles | ForEach-Object { $_.high } | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
}

function Get-RelativeStrength {
    param([double]$min, [double]$max, [double]$current)
    if ($max -eq $min) { return 50 }
    (($current - $min) / ($max - $min)) * 100
}

function Test-LongZone {
    param([double]$pctAboveMin)
    $pctAboveMin -le 5  # Perto da mínima
}

function Test-ShortZone {
    param([double]$pctBelowMax)
    $pctBelowMax -le 5  # Perto da máxima
}

function Detect-Trend {
    param([double[]]$closes)
    $upCount = 0
    for ($i = 1; $i -lt $closes.Count; $i++) {
        if ($closes[$i] -gt $closes[$i-1]) { $upCount++ }
    }
    if ($upCount -gt ($closes.Count / 2)) { "UP" } else { "DOWN" }
}
