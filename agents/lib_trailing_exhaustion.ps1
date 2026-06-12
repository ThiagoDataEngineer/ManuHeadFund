# lib_trailing_exhaustion.ps1
# Camada 3: Detectores de Exhaustion (proativo)
# 
# Detecta sinais de fraqueza ANTES da reversao.
# Filosofia: trader pro tighten stop quando ve doji no topo + vol secando.
# Bot deve ter o mesmo "olho clinico".
#
# 2026-05-25 - TDD implementacao

# ============================================================================
# 3.1 - Test-DojiCandle
# Detecta candle doji (indecisao no topo)
# ============================================================================

function Test-DojiCandle {
    <#
    .SYNOPSIS
    Identifica se candle e doji (body pequeno vs range).
    
    .DESCRIPTION
    Doji = corpo do candle (|close-open|) e <= 30% do range total (high-low).
    Indica indecisao - frequentemente precede reversao em topos/fundos.
    
    .PARAMETER Candle
    PSCustomObject com open, high, low, close
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Candle
    )
    $body = [math]::Abs([double]$Candle.close - [double]$Candle.open)
    $range = [double]$Candle.high - [double]$Candle.low
    
    if ($range -le 0) { return $false }
    
    $bodyRatio = $body / $range
    return ($bodyRatio -le 0.3)
}

# ============================================================================
# 3.2 - Test-WickTop
# Detecta rejeicao no topo (LONG): wick superior >> body
# ============================================================================

function Test-WickTop {
    <#
    .SYNOPSIS
    Detecta wick top (rejeicao em topo de movimento).
    
    .DESCRIPTION
    Wick superior = high - max(open, close)
    Body = |close - open|
    
    Se wick superior > 2x body = grande rejeicao em LONG.
    Sinal classico de smart money vendendo no topo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Candle
    )
    $high = [double]$Candle.high
    $low = [double]$Candle.low
    $open = [double]$Candle.open
    $close = [double]$Candle.close
    
    $bodyTop = [math]::Max($open, $close)
    $bodyBot = [math]::Min($open, $close)
    
    $upperWick = $high - $bodyTop
    $body = $bodyTop - $bodyBot
    
    # Evitar divisao por zero - se body=0 e wick>0, e doji top
    if ($body -le 0) { return ($upperWick -gt 0) }
    
    return ($upperWick -ge 2 * $body)
}

# ============================================================================
# 3.3 - Test-VolumeDrying
# Detecta volume secando (ultimas 3 candles vs media 24h)
# ============================================================================

function Test-VolumeDrying {
    <#
    .SYNOPSIS
    Detecta volume drying (interesse desaparecendo).
    
    .DESCRIPTION
    Compara volume medio das ultimas 3 candles vs media de 24 candles.
    Se ultimas 3h < 50% media 24h = volume secando.
    
    Indica falta de continuacao no movimento - sinal proativo de reversal.
    Requer pelo menos 24 candles para calculo confiavel.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array] $Candles
    )
    if ($null -eq $Candles -or $Candles.Count -lt 24) {
        return $false
    }
    
    $vols = $Candles | ForEach-Object { [double]$_.volume }
    $avg24 = ($vols | Select-Object -Last 24 | Measure-Object -Average).Average
    $avgLast3 = ($vols | Select-Object -Last 3 | Measure-Object -Average).Average
    
    if ($avg24 -le 0) { return $false }
    
    return ($avgLast3 -lt $avg24 * 0.5)
}

# ============================================================================
# 3.4 - Get-ExhaustionScore
# Score combinado dos 3 detectores (0-100)
# ============================================================================

function Get-ExhaustionScore {
    <#
    .SYNOPSIS
    Score combinado de exhaustion baseado em multiplos sinais.
    
    .DESCRIPTION
    Cada sinal contribui ate 33 pontos:
    - Doji no ultimo candle: 33pts
    - Wick top no ultimo candle: 33pts
    - Volume drying: 34pts
    
    Score total 0-100. Quanto maior, mais sinais de fraqueza.
    
    .PARAMETER Candles
    Array de candles com open/high/low/close/volume (>= 24 para volume drying)
    
    .PARAMETER Side
    LONG ou SHORT (afeta interpretacao - wick top so para LONG, wick bottom para SHORT)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array] $Candles,
        [Parameter(Mandatory)] [ValidateSet("LONG","SHORT")] [string] $Side
    )
    if ($null -eq $Candles -or $Candles.Count -lt 1) { return 0 }
    
    $score = 0
    $lastCandle = $Candles[-1]
    
    # 1. Doji no topo/fundo
    if (Test-DojiCandle -Candle $lastCandle) {
        $score += 33
    }
    
    # 2. Wick top (LONG) ou wick bottom (SHORT)
    if ($Side -eq "LONG") {
        if (Test-WickTop -Candle $lastCandle) { $score += 33 }
    } else {
        # SHORT: invert - lower wick rejection
        $h = [double]$lastCandle.high
        $l = [double]$lastCandle.low
        $o = [double]$lastCandle.open
        $c = [double]$lastCandle.close
        $bodyBot = [math]::Min($o, $c)
        $bodyTop = [math]::Max($o, $c)
        $lowerWick = $bodyBot - $l
        $body = $bodyTop - $bodyBot
        if ($body -le 0) { 
            if ($lowerWick -gt 0) { $score += 33 }
        } elseif ($lowerWick -ge 2 * $body) {
            $score += 33
        }
    }
    
    # 3. Volume drying
    if (Test-VolumeDrying -Candles $Candles) {
        $score += 34
    }
    
    return [math]::Min(100, $score)
}

# ============================================================================
# 3.5 - Get-StopTighteningFactor
# Quanto apertar stop baseado em score (0-100)
# ============================================================================

function Get-StopTighteningFactor {
    <#
    .SYNOPSIS
    Retorna fator de aproximacao do stop ao preco atual baseado em exhaustion.
    
    .DESCRIPTION
    Score 0   = factor 1.0 (sem aperto - mantem stop atual)
    Score 50  = factor 0.75 (aperta 25%)
    Score 100 = factor 0.5 (aperta 50%)
    
    Uso: novo_stop = current_stop + (price - current_stop) * (1 - factor)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [int] $ExhaustionScore
    )
    if ($ExhaustionScore -le 0) { return 1.0 }
    if ($ExhaustionScore -ge 100) { return 0.5 }
    
    # Linear: 0 -> 1.0, 100 -> 0.5
    return 1.0 - ($ExhaustionScore / 200.0)
}
