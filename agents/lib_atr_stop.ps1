# lib_atr_stop.ps1 -- ATR stop obrigatorio (Soros guardrail).
#
# Filosofia: stop calculado ANTES da emocao.
#   "Nao me incomoda estar errado, me incomoda ficar errado." -- Soros
#
# ATR stop = Entry +- (ATR * Multiplier)
#   LONG:  stop = Entry - (ATR * Multiplier)
#   SHORT: stop = Entry + (ATR * Multiplier)
#
# Multiplier default 2.0: pega volatilidade normal, mata trades que sairam fora.
#
# Get-AtrFromHighLow: simplificacao TR = High - Low (sem gap).
# Suficiente pra daily candles onde gap eh raro.
#
# PS 5.1. UTF-8 BOM.


function Get-AtrStop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $Entry,
        [Parameter(Mandatory)] [double] $Atr,
        [Parameter(Mandatory)] [ValidateSet("long","short")] [string] $Direction,
        [double] $Multiplier = 2.0
    )
    if ($Atr -le 0) { return $Entry }
    $offset = $Atr * $Multiplier
    if ($Direction -eq "long") {
        return $Entry - $offset
    } else {
        return $Entry + $offset
    }
}


function Get-AtrFromHighLow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double[]] $Highs,
        [Parameter(Mandatory)] [double[]] $Lows,
        [int] $Period = 14
    )
    $n = $Highs.Length
    if ($n -lt $Period) { return 0 }
    $tr_sum = 0.0
    $start = $n - $Period
    for ($i = $start; $i -lt $n; $i++) {
        $tr_sum += ($Highs[$i] - $Lows[$i])
    }
    return [Math]::Round($tr_sum / $Period, 4)
}
