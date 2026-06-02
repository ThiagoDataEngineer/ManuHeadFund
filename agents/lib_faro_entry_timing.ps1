# lib_faro_entry_timing.ps1 — Golden hour + 1min rejection
function Get-EntryTiming {
    param([array] $Candles1min, [decimal] $MA5, [decimal] $CurrentHourUTC)
    $score = 0
    if ($Candles1min -and $Candles1min.Count -gt 0) {
        $latest = $Candles1min[-1]
        if (-not $MA5) { $MA5 = ($Candles1min | Measure-Object close -Average).Average }
        $highAboveMA = ($latest.high / $MA5 - 1) * 100
        $closeVsMA = ($latest.close / $MA5 - 1) * 100
        if ($highAboveMA -gt 1.5 -and $closeVsMA -lt 0) { $score += 12 }
        elseif ($highAboveMA -gt 1.0 -and $closeVsMA -lt -0.5) { $score += 7 }
    }
    if ($CurrentHourUTC -ge 13 -and $CurrentHourUTC -le 16) { $score += 5 }
    return [Math]::Min($score, 20)
}
