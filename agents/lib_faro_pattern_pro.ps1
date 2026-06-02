# lib_faro_pattern_pro.ps1 — Multi-timeframe pattern detection
function Get-PatternPro {
    param([string] $PatternType, [decimal] $Strength, [array] $Candles1min, [array] $Candles5min, [array] $Candles1d)
    if (-not $PatternType -or -not $Strength -or $Strength -lt 0 -or $Strength -gt 1) { return 0 }
    $baseScore = switch ($PatternType) {
        "consolidation" { 12 }
        "rounding_bottom" { 15 }
        "golden_cross" { 18 }
        "rejection" { 14 }
        default { 0 }
    }
    if ($baseScore -eq 0) { return 0 }
    $score = [int]($baseScore * $Strength)
    if ($Candles1min -and $Candles1min.Count -gt 5) {
        $latest = $Candles1min[-1]
        $ma5 = ($Candles1min[-5..-1] | Measure-Object close -Average).Average
        if ($latest.high -gt ($ma5 * 1.015) -and $latest.close -lt $ma5) {
            $score = [Math]::Min($score + 4, 25)
        }
    }
    if ($Candles5min -and $Candles5min.Count -gt 10) {
        $high5min = ($Candles5min[-10..-1] | Measure-Object high -Maximum).Maximum
        $low5min = ($Candles5min[-10..-1] | Measure-Object low -Minimum).Minimum
        $atr = ($high5min - $low5min) / $low5min
        if ($atr -lt 0.03) { $score = [Math]::Min($score + 3, 25) }
    }
    return [Math]::Min($score, 25)
}
Export-ModuleMember -Function "Get-PatternPro"
