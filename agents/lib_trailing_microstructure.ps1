# lib_trailing_microstructure.ps1
# Camada 4: Microstructure Detection (Open Interest, Funding Rate)
# 
# Detecta sinais do mercado de derivativos que indicam movimento iminente.
# Filosofia: divergencia OI/funding = smart money mudando de lado.
#
# 2026-05-25 - TDD implementacao

# ============================================================================
# 4.1 - Test-OiDivergence
# OI cai enquanto preco sobe = falta de convicção
# ============================================================================

function Test-OiDivergence {
    <#
    .SYNOPSIS
    Detecta divergencia entre preco e Open Interest.
    
    .DESCRIPTION
    LONG: preco subindo + OI caindo = falta de novos compradores (warning)
    SHORT: preco caindo + OI caindo = falta de novos vendedores (warning)
    
    Indica que o movimento atual nao tem convicção do smart money.
    
    .PARAMETER PriceHistory
    Array de precos cronologico (mais antigo primeiro), >= 3 pontos
    
    .PARAMETER OiHistory
    Array de OI cronologico (mesmo tamanho do PriceHistory)
    
    .PARAMETER Side
    LONG ou SHORT (afeta interpretacao)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array] $PriceHistory,
        [Parameter(Mandatory)] [array] $OiHistory,
        [Parameter(Mandatory)] [ValidateSet("LONG","SHORT")] [string] $Side
    )
    if ($PriceHistory.Count -lt 3 -or $OiHistory.Count -lt 3) {
        return $false
    }
    if ($PriceHistory.Count -ne $OiHistory.Count) {
        return $false
    }
    
    $priceFirst = [double]$PriceHistory[0]
    $priceLast = [double]$PriceHistory[-1]
    $oiFirst = [double]$OiHistory[0]
    $oiLast = [double]$OiHistory[-1]
    
    $priceUp = $priceLast -gt $priceFirst
    $priceDown = $priceLast -lt $priceFirst
    $oiUp = $oiLast -gt $oiFirst
    $oiDown = $oiLast -lt $oiFirst
    
    if ($Side -eq "LONG") {
        # LONG warning: preco subiu mas OI caiu
        return ($priceUp -and $oiDown)
    } else {
        # SHORT warning: preco caiu mas OI caiu (sem novos vendedores)
        return ($priceDown -and $oiDown)
    }
}

# ============================================================================
# 4.2 - Test-FundingFlip
# Funding rate mudando de direcao indica forca contraria
# ============================================================================

function Test-FundingFlip {
    <#
    .SYNOPSIS
    Detecta mudanca de sinal no funding rate.
    
    .DESCRIPTION
    LONG warning: funding positivo->negativo (vendedores ficaram agressivos)
    SHORT warning: funding negativo->positivo (compradores ficaram agressivos)
    
    Funding rate flip indica mudanca de domínio entre longs e shorts.
    
    .PARAMETER FundingHistory
    Array de funding rates cronologico (mais antigo primeiro), >= 4 pontos
    
    .PARAMETER Side
    LONG ou SHORT
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array] $FundingHistory,
        [Parameter(Mandatory)] [ValidateSet("LONG","SHORT")] [string] $Side
    )
    if ($FundingHistory.Count -lt 4) {
        return $false
    }
    
    # Comparar primeira metade (avg) vs segunda metade (avg)
    $half = [int]($FundingHistory.Count / 2)
    $firstHalf = $FundingHistory[0..($half - 1)] | ForEach-Object { [double]$_ }
    $secondHalf = $FundingHistory[$half..($FundingHistory.Count - 1)] | ForEach-Object { [double]$_ }
    
    $avgFirst = ($firstHalf | Measure-Object -Average).Average
    $avgSecond = ($secondHalf | Measure-Object -Average).Average
    
    if ($Side -eq "LONG") {
        # LONG warning: funding era positivo, virou negativo
        return ($avgFirst -gt 0 -and $avgSecond -lt 0)
    } else {
        # SHORT warning: funding era negativo, virou positivo
        return ($avgFirst -lt 0 -and $avgSecond -gt 0)
    }
}

# ============================================================================
# 4.3 - Get-MicrostructureScore
# Score combinado dos detectores (0-100)
# ============================================================================

function Get-MicrostructureScore {
    <#
    .SYNOPSIS
    Score combinado de microstructure (0-100).
    
    .DESCRIPTION
    Cada sinal contribui:
    - OI divergence: 50 pts
    - Funding flip: 50 pts
    
    Score total reflete pressao do mercado de derivativos contra a posicao.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array] $PriceHistory,
        [Parameter(Mandatory)] [array] $OiHistory,
        [Parameter(Mandatory)] [array] $FundingHistory,
        [Parameter(Mandatory)] [ValidateSet("LONG","SHORT")] [string] $Side
    )
    $score = 0
    
    if (Test-OiDivergence -PriceHistory $PriceHistory -OiHistory $OiHistory -Side $Side) {
        $score += 50
    }
    
    if (Test-FundingFlip -FundingHistory $FundingHistory -Side $Side) {
        $score += 50
    }
    
    return [math]::Min(100, $score)
}
