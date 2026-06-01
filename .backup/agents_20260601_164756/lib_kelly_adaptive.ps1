# lib_kelly_adaptive.ps1 -- Kelly-fractional adaptive sizing.
#
# Substitui sizing fixo 1% por f* = (p*W - q*L) / (W*L) ajustado por
# fractional Kelly (default quarter = 0.25, conservative crypto).
# Cap absoluto por mode (BLUE_CHIP 2%, TIER_A 1%, GEM 0.5%).
#
# Lopez de Prado AFML cap.13: full Kelly maximiza log capital but assume
# distribution conhecida (irreal). Quarter Kelly reduz vol sem perder muito.
#
# 2026-05-19 PM. TDD: tests/lib_kelly_adaptive.Tests.ps1


$script:MODE_CAPS = @{
    "BLUE_CHIP" = 0.02
    "TIER_A"    = 0.01
    "STANDARD"  = 0.01
    "GEM"       = 0.005
    "PAPER"     = 0.01
}

$script:DEFAULT_FRACTION = 0.25   # quarter Kelly
$script:MIN_TRADES_FOR_HISTORICAL = 10


function Get-KellyFraction {
    # Pure math: f* = (p*W - q*L) / (W*L)
    # Returns: Kelly optimal fraction (0..1). Negative -> 0 (no bet).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $WinProb,    # 0..1
        [Parameter(Mandatory)] [double] $WinAmount,  # avg R-multiple win
        [Parameter(Mandatory)] [double] $LossAmount  # avg R-multiple loss (positive)
    )
    if ($LossAmount -le 0 -or $WinAmount -le 0) { return 0.0 }
    $q = 1 - $WinProb
    $num = $WinProb * $WinAmount - $q * $LossAmount
    $denom = $WinAmount * $LossAmount
    if ($denom -le 0) { return 0.0 }
    $f = $num / $denom
    if ($f -lt 0) { return 0.0 }
    return [Math]::Round($f, 4)
}


function Get-AdaptiveSize {
    # Aplica Kelly-fractional + cap por mode + capital -> size USD.
    # Retorna PSCustomObject com breakdown completo.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $WinProb,
        [Parameter(Mandatory)] [double] $WinAmount,
        [Parameter(Mandatory)] [double] $LossAmount,
        [Parameter(Mandatory)] [string] $Mode,
        [Parameter(Mandatory)] [double] $Capital,
        [double] $Fraction = $script:DEFAULT_FRACTION
    )
    $fKelly = Get-KellyFraction -WinProb $WinProb -WinAmount $WinAmount -LossAmount $LossAmount
    $cap = if ($script:MODE_CAPS.ContainsKey($Mode)) { $script:MODE_CAPS[$Mode] } else { 0.01 }

    $fAdjusted = $fKelly * $Fraction
    $fUsed = [Math]::Min($fAdjusted, $cap)
    $fUsed = [Math]::Round($fUsed, 4)
    $sizeUsd = [Math]::Round($Capital * $fUsed, 2)

    return [PSCustomObject]@{
        f_kelly    = $fKelly
        f_adjusted = [Math]::Round($fAdjusted, 4)
        cap        = $cap
        f_used     = $fUsed
        size_usd   = $sizeUsd
        mode       = $Mode
        capital    = $Capital
        fraction   = $Fraction
    }
}


function Get-AdaptiveSizeFromTrades {
    # Computa win_prob + avg_win/avg_loss de array de trades (R-multiples)
    # e delega pra Get-AdaptiveSize. Trades positivos = wins, negativos = losses.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double[]] $Trades,
        [Parameter(Mandatory)] [string] $Mode,
        [Parameter(Mandatory)] [double] $Capital,
        [int] $MinTrades = $script:MIN_TRADES_FOR_HISTORICAL,
        [double] $Fraction = $script:DEFAULT_FRACTION
    )
    if ($Trades.Count -lt $MinTrades) {
        # Fallback fixed 1% (anterior comportamento)
        $sizeUsd = [Math]::Round($Capital * 0.01, 2)
        return [PSCustomObject]@{
            fallback   = $true
            reason     = "insufficient_trades_$($Trades.Count)_lt_$MinTrades"
            size_usd   = $sizeUsd
            f_used     = 0.01
            mode       = $Mode
            capital    = $Capital
        }
    }

    $wins = @($Trades | Where-Object { $_ -gt 0 })
    $losses = @($Trades | Where-Object { $_ -lt 0 })
    if ($losses.Count -eq 0) {
        # Sem losses: edge "infinito" mas pode ser sample bias. Cap manual + flag.
        $sizeUsd = [Math]::Round($Capital * $script:MODE_CAPS[$Mode], 2)
        return [PSCustomObject]@{
            warning    = "no_losses_in_sample"
            size_usd   = $sizeUsd
            f_used     = $script:MODE_CAPS[$Mode]
            mode       = $Mode
            capital    = $Capital
        }
    }
    if ($wins.Count -eq 0) {
        return [PSCustomObject]@{
            f_kelly  = 0; f_used = 0; size_usd = 0
            mode = $Mode; capital = $Capital
            reason = "no_wins"
        }
    }

    $winProb = $wins.Count / [double]$Trades.Count
    $avgWin = ($wins | Measure-Object -Average).Average
    $avgLoss = [Math]::Abs(($losses | Measure-Object -Average).Average)

    $sz = Get-AdaptiveSize -WinProb $winProb -WinAmount $avgWin -LossAmount $avgLoss `
                           -Mode $Mode -Capital $Capital -Fraction $Fraction
    # Anexa stats historicas + schema consistente (fallback explicit false)
    Add-Member -InputObject $sz -MemberType NoteProperty -Name fallback -Value $false -Force
    Add-Member -InputObject $sz -MemberType NoteProperty -Name win_prob -Value ([Math]::Round($winProb, 3)) -Force
    Add-Member -InputObject $sz -MemberType NoteProperty -Name avg_win -Value ([Math]::Round($avgWin, 3)) -Force
    Add-Member -InputObject $sz -MemberType NoteProperty -Name avg_loss -Value ([Math]::Round($avgLoss, 3)) -Force
    Add-Member -InputObject $sz -MemberType NoteProperty -Name n_trades -Value $Trades.Count -Force
    return $sz
}
