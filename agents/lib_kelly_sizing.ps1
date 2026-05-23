# lib_kelly_sizing.ps1 -- Kelly fracionario com cap pra position sizing dinamico.
#
# Filosofia (Simons/Berlekamp 1989):
#   - Flat 1% sizing ignora variacao de edge entre trades.
#   - Kelly: f = (p*b - q) / b
#       p = WinRate
#       q = 1 - p
#       b = WinLossRatio (avg_win / avg_loss)
#   - Edge negativo (f<0) -> nao opera (0).
#   - Cap pratico em CapPct (default 1%): evita ruina por estimativa errada de p.
#
# Refs: knowledge/SIMONS_RENTECH.md, knowledge/LOPEZ_DE_PRADO.md (sigmoid bet sizing)
#
# PS 5.1. UTF-8 BOM.


function Get-KellyFraction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $WinRate,
        [Parameter(Mandatory)] [double] $WinLossRatio,
        [double] $CapPct = 0.01
    )
    if ($WinLossRatio -le 0) { return 0 }
    $p = $WinRate
    $q = 1.0 - $p
    $b = $WinLossRatio
    $f = (($p * $b) - $q) / $b
    if ($f -lt 0) { return 0 }
    if ($f -gt $CapPct) { return $CapPct }
    return $f
}


function Get-KellySize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $Capital,
        [Parameter(Mandatory)] [double] $WinRate,
        [Parameter(Mandatory)] [double] $WinLossRatio,
        [double] $CapPct = 0.01
    )
    $f = Get-KellyFraction -WinRate $WinRate -WinLossRatio $WinLossRatio -CapPct $CapPct
    return [Math]::Round($Capital * $f, 2)
}
