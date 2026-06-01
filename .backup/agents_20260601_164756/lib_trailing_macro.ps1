# lib_trailing_macro.ps1
# Camada 5: Macro Pressure (BTC correlation, eventos macro)
# 
# Detecta pressao macro que afeta TODAS as posicoes (ex: BTC dump, FOMC).
# Filosofia: smart trader reduz risco antes de eventos conhecidos.
#
# 2026-05-25 - TDD implementacao

# ============================================================================
# 5.1 - Get-BtcCorrelationPressure
# Pressao em alts baseada em movimento BTC
# ============================================================================

function Get-BtcCorrelationPressure {
    <#
    .SYNOPSIS
    Calcula pressao macro de BTC nas alts.
    
    .DESCRIPTION
    Em crypto, BTC eh master. Quando BTC move, alts seguem (com beta variavel).
    
    LONG em alt + BTC dump = pressao alta para tighten stop
    SHORT em alt + BTC pump = pressao alta para tighten stop
    
    Score 0-100 baseado em magnitude do movimento BTC contra a posicao.
    
    .PARAMETER BtcChange1hPct
    Variacao % do BTC na ultima 1h
    
    .PARAMETER Side
    LONG ou SHORT da posicao
    
    .PARAMETER IsBtc
    Se a posicao em si eh BTC, nao auto-correlacionar
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $BtcChange1hPct,
        [Parameter(Mandatory)] [ValidateSet("LONG","SHORT")] [string] $Side,
        [bool] $IsBtc = $false
    )
    if ($IsBtc) { return 0 }
    
    # Pressao positiva quando movimento BTC esta CONTRA a posicao
    $pressureRaw = if ($Side -eq "LONG") {
        # LONG sofre quando BTC cai
        if ($BtcChange1hPct -ge 0) { 0 } else { [math]::Abs($BtcChange1hPct) }
    } else {
        # SHORT sofre quando BTC sobe
        if ($BtcChange1hPct -le 0) { 0 } else { $BtcChange1hPct }
    }
    
    # Mapear: -3% (BTC) -> ~75 score, -5% -> 100, 0 -> 0
    # Linear: 1% movimento contrario = 25 pts (max 100 em 4%)
    $score = [math]::Min(100, [int]([math]::Round($pressureRaw * 25)))
    return $score
}

# ============================================================================
# 5.2 - Test-MacroEventWindow
# Detecta proximidade de eventos macro importantes
# ============================================================================

function Test-MacroEventWindow {
    <#
    .SYNOPSIS
    Verifica se estamos em janela de evento macro (FOMC, CPI, NFP).
    
    .DESCRIPTION
    Retorna true se CurrentTime esta dentro de [EventTime - PreHours, EventTime + PostHours].
    Default: 1h antes e 4h depois do evento.
    
    Use cases:
    - FOMC: volatilidade alta -1h a +4h
    - CPI: -1h a +2h
    - NFP: -1h a +2h
    - BTC halving: muito mais amplo
    
    .PARAMETER EventTime
    Datetime do evento
    
    .PARAMETER CurrentTime
    Datetime atual (default: agora)
    
    .PARAMETER PreHours
    Horas antes do evento que ja conta como janela (default 1)
    
    .PARAMETER PostHours
    Horas depois do evento que ainda conta como janela (default 4)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [DateTime] $EventTime,
        [DateTime] $CurrentTime = (Get-Date),
        [int] $PreHours = 1,
        [int] $PostHours = 4
    )
    $windowStart = $EventTime.AddHours(-$PreHours)
    $windowEnd = $EventTime.AddHours($PostHours)
    
    return ($CurrentTime -ge $windowStart -and $CurrentTime -le $windowEnd)
}

# ============================================================================
# 5.3 - Get-MacroPressureScore
# Score combinado dos detectores macro (0-100)
# ============================================================================

function Get-MacroPressureScore {
    <#
    .SYNOPSIS
    Score combinado de pressao macro.
    
    .DESCRIPTION
    Combina:
    - BTC correlation (peso 0.7)
    - Janela de evento macro (peso 0.3, contribui +30 se ativo)
    
    Score total 0-100. >= 60 = pressao critica, tighten agressivo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $BtcChange1hPct,
        [Parameter(Mandatory)] [ValidateSet("LONG","SHORT")] [string] $Side,
        [DateTime] $EventTime = $null,
        [DateTime] $CurrentTime = (Get-Date),
        [bool] $IsBtc = $false,
        [int] $EventPreHours = 1,
        [int] $EventPostHours = 4
    )
    
    # Component 1: BTC correlation (max 70 pts)
    $btcPressure = Get-BtcCorrelationPressure -BtcChange1hPct $BtcChange1hPct -Side $Side -IsBtc $IsBtc
    $btcWeighted = [math]::Round($btcPressure * 0.7)
    
    # Component 2: Event window (max 30 pts)
    $eventPressure = 0
    if ($EventTime) {
        if (Test-MacroEventWindow -EventTime $EventTime -CurrentTime $CurrentTime `
                -PreHours $EventPreHours -PostHours $EventPostHours) {
            $eventPressure = 30
        }
    }
    
    return [math]::Min(100, [int]($btcWeighted + $eventPressure))
}
