# lib_trailing_smart.ps1
# Trailing Stop Inteligente - Camadas 2-5 (volatilidade adaptativa, exhaustion, micro, macro)
# 2026-05-25 - Implementacao TDD
#
# Camadas:
#   Camada 1: Reativo (lib_trailing.ps1 - phases 0-3)
#   Camada 2: ATR Adaptativo (este arquivo)
#   Camada 3: Exhaustion Detection (lib_trailing_exhaustion.ps1)
#   Camada 4: Microstructure (futuro - Fase 2)
#   Camada 5: Macro (futuro - Fase 3)

$ErrorActionPreference = "Continue"

# ============================================================================
# CAMADA 2: ATR ADAPTATIVO
# ============================================================================

function Get-VolatilityClass {
    <#
    .SYNOPSIS
    Classifica volatilidade baseada em ATR como % do preço.
    
    .DESCRIPTION
    Range:
      < 2%   = LOW_VOL    (par estavel tipo BTC, ETH)
      2-4%   = MEDIUM_VOL (padrao - alts populares)
      4-6%   = HIGH_VOL   (alts mais volateis)
      > 6%   = EXTREME_VOL (memes, micro-caps)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $AtrPct
    )
    if ($AtrPct -lt 2.0)  { return "LOW_VOL" }
    if ($AtrPct -lt 4.0)  { return "MEDIUM_VOL" }
    if ($AtrPct -lt 6.0)  { return "HIGH_VOL" }
    return "EXTREME_VOL"
}

function Get-AtrStopMultiple {
    <#
    .SYNOPSIS
    Retorna multiplo de ATR para stop baseado em volatilidade.
    
    .DESCRIPTION
    Filosofia: pares estaveis podem ter stop mais largo (2.5 ATR) sem
    risco de whipsaw. Pares voláteis precisam stop mais perto (1.2-1.5 ATR)
    para evitar drawdown excessivo - mas largo o suficiente para nao ser
    cortado por noise normal.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $AtrPct
    )
    $class = Get-VolatilityClass -AtrPct $AtrPct
    switch ($class) {
        "LOW_VOL"     { return 2.5 }
        "MEDIUM_VOL"  { return 2.0 }
        "HIGH_VOL"    { return 1.5 }
        "EXTREME_VOL" { return 1.2 }
        default       { return 2.0 }
    }
}

function Calculate-AdaptiveStopPrice {
    <#
    .SYNOPSIS
    Calcula preco de stop baseado em ATR e multiplo.
    
    .DESCRIPTION
    LONG:  stop = entry - (ATR * multiple)
    SHORT: stop = entry + (ATR * multiple)
    
    Usa decimal para preservar precisao em pares sub-dollar.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet("LONG","SHORT")] [string] $Side,
        [Parameter(Mandatory)] [double] $Entry,
        [Parameter(Mandatory)] [double] $AtrAbs,
        [Parameter(Mandatory)] [double] $AtrMultiple,
        [int] $Precision = 4
    )
    $entryD = [decimal]$Entry
    $atrD = [decimal]$AtrAbs
    $multD = [decimal]$AtrMultiple
    $offset = $atrD * $multD
    
    $stopD = if ($Side -eq "LONG") { $entryD - $offset } else { $entryD + $offset }
    return [math]::Round([double]$stopD, $Precision)
}

function Calculate-AtrFromCandles {
    <#
    .SYNOPSIS
    Calcula ATR (Average True Range) a partir de array de candles.
    
    .DESCRIPTION
    True Range = max de:
      1. high - low
      2. abs(high - prev_close)
      3. abs(low - prev_close)
    
    ATR = média dos últimos N true ranges (N = Period, padrão 14).
    Retorna 0 se menos candles que Period (insuficiente).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array] $Candles,
        [int] $Period = 14
    )
    if ($null -eq $Candles -or $Candles.Count -lt $Period) {
        return 0
    }
    
    $trueRanges = @()
    for ($i = 1; $i -lt $Candles.Count; $i++) {
        $high = [double]$Candles[$i].high
        $low = [double]$Candles[$i].low
        $prevClose = [double]$Candles[$i-1].close
        
        $tr1 = $high - $low
        $tr2 = [math]::Abs($high - $prevClose)
        $tr3 = [math]::Abs($low - $prevClose)
        
        $trueRanges += [math]::Max($tr1, [math]::Max($tr2, $tr3))
    }
    
    # ATR = média dos últimos Period true ranges
    $recentTr = $trueRanges | Select-Object -Last $Period
    $atr = ($recentTr | Measure-Object -Average).Average
    return [double]$atr
}


# ============================================================================
# INTEGRADOR: Get-SmartStopPrice
# Combina Camada 2 (ATR) + Camada 3 (Exhaustion) para sugerir stop final
# ============================================================================

# Dot-source dependencias (se nao carregadas)
if (-not (Get-Command "Get-ExhaustionScore" -ErrorAction SilentlyContinue)) {
    $exhaustionLib = Join-Path $PSScriptRoot "lib_trailing_exhaustion.ps1"
    if (Test-Path $exhaustionLib) { . $exhaustionLib }
}

function Get-SmartStopPrice {
    <#
    .SYNOPSIS
    Calcula stop sugerido combinando todas as camadas.
    
    .DESCRIPTION
    Algoritmo:
    1. Calcula ATR e classe de volatilidade
    2. Calcula stop baseado em ATR (Camada 2)
    3. Detecta exhaustion (Camada 3)
    4. Aplica tightening factor se exhaustion alto
    5. Garante que stop nunca recua (LONG: monotonic up)
    
    .PARAMETER Side
    LONG ou SHORT
    
    .PARAMETER Entry
    Preco de entrada
    
    .PARAMETER CurrentPrice
    Preco atual do mercado
    
    .PARAMETER CurrentStop
    Stop atual da posicao
    
    .PARAMETER Candles
    Array de candles 1h (>=24 para ATR/exhaustion)
    
    .OUTPUTS
    PSCustomObject com:
      - atr_pct: volatilidade atual em %
      - vol_class: classe LOW/MEDIUM/HIGH/EXTREME_VOL
      - atr_stop: stop sugerido por ATR
      - exhaustion_score: score 0-100
      - tightening_factor: 0.5-1.0
      - suggested_stop: stop final sugerido
      - current_stop: stop atual (referencia)
      - action: tipo de ajuste recomendado
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet("LONG","SHORT")] [string] $Side,
        [Parameter(Mandatory)] [double] $Entry,
        [Parameter(Mandatory)] [double] $CurrentPrice,
        [Parameter(Mandatory)] [double] $CurrentStop,
        [Parameter(Mandatory)] [array] $Candles
    )
    
    # 1. Calcular ATR
    $atrAbs = Calculate-AtrFromCandles -Candles $Candles -Period 14
    $atrPct = if ($CurrentPrice -gt 0) { ($atrAbs / $CurrentPrice) * 100 } else { 0 }
    $volClass = Get-VolatilityClass -AtrPct $atrPct
    
    # 2. Stop por ATR (Camada 2)
    $atrMultiple = Get-AtrStopMultiple -AtrPct $atrPct
    $atrStop = if ($atrAbs -gt 0) {
        Calculate-AdaptiveStopPrice -Side $Side -Entry $CurrentPrice -AtrAbs $atrAbs -AtrMultiple $atrMultiple
    } else { $CurrentStop }
    
    # 3. Exhaustion score (Camada 3)
    $exhaustionScore = Get-ExhaustionScore -Candles $Candles -Side $Side
    
    # 4. Tightening factor
    $tighteningFactor = Get-StopTighteningFactor -ExhaustionScore $exhaustionScore
    
    # 5. Stop sugerido = ATR stop ajustado por exhaustion
    # Logica: se exhaustion alto, mover stop em direcao ao preco
    $suggestedStop = $atrStop
    if ($exhaustionScore -ge 33) {
        $delta = $CurrentPrice - $atrStop
        $tightenAmount = $delta * (1 - $tighteningFactor)
        if ($Side -eq "LONG") {
            $suggestedStop = $atrStop + $tightenAmount
        } else {
            $suggestedStop = $atrStop - $tightenAmount
        }
    }
    
    # 6. NUNCA recua o stop (LONG: novo >= atual; SHORT: novo <= atual)
    if ($Side -eq "LONG") {
        $suggestedStop = [math]::Max($suggestedStop, $CurrentStop)
    } else {
        $suggestedStop = [math]::Min($suggestedStop, $CurrentStop)
    }
    
    # 7. Action recomendada
    $action = if ($suggestedStop -eq $CurrentStop) { "no_change" }
              elseif ($exhaustionScore -ge 66) { "tighten_aggressive" }
              elseif ($exhaustionScore -ge 33) { "tighten_moderate" }
              else { "trail_normal" }
    
    return [PSCustomObject]@{
        atr_pct = [math]::Round($atrPct, 2)
        vol_class = $volClass
        atr_multiple = $atrMultiple
        atr_stop = [math]::Round($atrStop, 4)
        exhaustion_score = $exhaustionScore
        tightening_factor = $tighteningFactor
        suggested_stop = [math]::Round($suggestedStop, 4)
        current_stop = $CurrentStop
        action = $action
    }
}
