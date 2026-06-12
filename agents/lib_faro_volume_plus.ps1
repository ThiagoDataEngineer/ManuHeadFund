# lib_faro_volume_plus.ps1 — Volume spike with wash-trade filter
function Get-VolumeSpikePro {
    param([string] $Market, [decimal] $CurrentVol, [decimal] $Avg3dVol, [decimal] $BuySideVol = 0, [decimal] $SellSideVol = 0, [decimal] $VolumeMomentum = 1.0)
    if (-not $CurrentVol -or -not $Avg3dVol -or $Avg3dVol -eq 0) { return 0 }
    $ratio = $CurrentVol / $Avg3dVol
    if ($ratio -lt 2.0) { return 0 }
    if ($BuySideVol -gt 0 -and $SellSideVol -gt 0 -and ($BuySideVol / $SellSideVol) -lt 1.2) { return 0 }
    if ($VolumeMomentum -lt 0.8) { return 0 }
    $score = switch ($ratio) {
        {$_ -lt 2.5} { [int](10 + ($ratio - 2.0) * 16); break }
        {$_ -lt 3.5} { [int](18 + ($ratio - 2.5) * 7); break }
        default { 25 }
    }
    return $score
}
