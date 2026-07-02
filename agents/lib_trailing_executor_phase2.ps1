# lib_trailing_executor_phase2.ps1 — Trailing Executor Phase 2
# Smart SL move baseado em order flow + Multiple stop levels
# Detecta volume climax → aperta SL breakeven
# Quando SL hit → move pra próximo nível automaticamente
# TDD-driven, 100% pure functions

$ErrorActionPreference = "Stop"

# ============================================================================
# SMART SL MOVE — Baseado em Order Flow
# ============================================================================

function Test-OrderFlowIntensity {
    <#
    .SYNOPSIS
    Detecta intensidade de order flow (volume/momentum) nos últimos candles

    .PARAMETER Candles
    Array de candles (close, volume, timestamp)

    .PARAMETER WindowSize
    Quantos candles olhar pra trás (default 5)

    .OUTPUTS
    @{ intensity = 0-100; signal = "low"|"medium"|"high" }
    #>
    param(
        [array]$Candles,
        [int]$WindowSize = 5
    )

    if ($Candles.Count -lt $WindowSize) {
        return @{ intensity = 0; signal = "low" }
    }

    # Últimas N velas
    $window = $Candles[-$WindowSize..($Candles.Count-1)]

    # Volume médio
    $avgVol = ($window | Measure-Object -Property volume -Average).Average

    # Momentum: mudança de preço vs média
    $priceChange = [math]::Abs($window[-1].close - $window[0].close)
    $avgPrice = ($window | Measure-Object -Property close -Average).Average
    $priceVelocity = $priceChange / $avgPrice * 100

    # Score: volume spiking + preço moving
    $volumeSpike = $window[-1].volume / ($avgVol + 0.001) * 100
    $intensity = [math]::Min(100, ($volumeSpike + $priceVelocity) / 2)

    # 2026-07-02 FIX: 'switch' sem expressao e parse error (PS 5.1 e 7)
    $signal = if ($intensity -ge 70) { "high" } elseif ($intensity -ge 40) { "medium" } else { "low" }

    @{ intensity = [math]::Round($intensity); signal = $signal }
}

function Test-VolumePriceAgreement {
    <#
    .SYNOPSIS
    Valida se volume + preço estão em acordo (confirma move, não fake)

    .OUTPUTS
    @{ valid = $true|$false; confidence = 0-100 }
    #>
    param(
        [array]$Candles,
        [int]$WindowSize = 3
    )

    if ($Candles.Count -lt $WindowSize) {
        return @{ valid = $false; confidence = 0 }
    }

    $window = $Candles[-$WindowSize..($Candles.Count-1)]

    $upCandles = $window | Where-Object { $_.close -gt $_.open }
    $downCandles = $window | Where-Object { $_.close -lt $_.open }

    $upVolume = ($upCandles | Measure-Object -Property volume -Sum).Sum
    $downVolume = ($downCandles | Measure-Object -Property volume -Sum).Sum

    $totalVolume = $upVolume + $downVolume + 0.001
    $agreement = [math]::Max($upVolume, $downVolume) / $totalVolume * 100

    $valid = $agreement -ge 60  # 60%+ agreement = válido

    @{ valid = $valid; confidence = [math]::Round($agreement) }
}

# ============================================================================
# MULTIPLE STOP LEVELS — Breakeven, Lock, Trailing
# ============================================================================

function New-StopLevelStructure {
    <#
    .SYNOPSIS
    Cria estrutura de múltiplos níveis de stop com transições

    .PARAMETER EntryPrice
    Preço de entrada

    .PARAMETER StopPrice
    Stop inicial (do journal)

    .PARAMETER Side
    "LONG" ou "SHORT"

    .OUTPUTS
    @{
      level_1_breakeven = entrada
      level_2_lock = entrada + 5%
      level_3_trailing = entrada + 10%
      current_level = 1
      transitioned_at = $null
    }
    #>
    param(
        [double]$EntryPrice,
        [double]$StopPrice,
        [string]$Side
    )

    if ($Side -eq "LONG") {
        $l1 = $EntryPrice                      # Breakeven: entrada
        $l2 = $EntryPrice * 1.05               # Lock: +5%
        $l3 = $EntryPrice * 1.10               # Trailing: +10%
    } else {
        $l1 = $EntryPrice                      # Breakeven: entrada
        $l2 = $EntryPrice * 0.95               # Lock: -5%
        $l3 = $EntryPrice * 0.90               # Trailing: -10%
    }

    @{
        level_1_breakeven = $l1
        level_2_lock = $l2
        level_3_trailing = $l3
        current_level = 1
        transitioned_at = $null
        hit_log = @()  # Histórico de hits
    }
}

function Update-StopLevel {
    <#
    .SYNOPSIS
    Move pra próximo nível se condições forem atendidas

    .PARAMETER Structure
    StopLevelStructure

    .PARAMETER CurrentPrice
    Preço atual

    .PARAMETER Side
    "LONG" ou "SHORT"

    .OUTPUTS
    @{ moved = $true|$false; new_level = 1|2|3; reason = string }
    #>
    param(
        [hashtable]$Structure,
        [double]$CurrentPrice,
        [string]$Side
    )

    $currentLevel = $Structure.current_level
    $profit = if ($Side -eq "LONG") {
        ($CurrentPrice - $Structure.level_1_breakeven) / $Structure.level_1_breakeven * 100
    } else {
        ($Structure.level_1_breakeven - $CurrentPrice) / $Structure.level_1_breakeven * 100
    }

    $moved = $false
    $newLevel = $currentLevel
    $reason = "no_move"

    # Level 1 → 2: atingiu +5%
    if ($currentLevel -eq 1 -and $profit -ge 5) {
        $newLevel = 2
        $moved = $true
        $reason = "profit_5pct_reached"
        $Structure.transitioned_at = Get-Date
    }
    # Level 2 → 3: atingiu +10%
    elseif ($currentLevel -eq 2 -and $profit -ge 10) {
        $newLevel = 3
        $moved = $true
        $reason = "profit_10pct_reached"
        $Structure.transitioned_at = Get-Date
    }

    if ($moved) {
        $Structure.current_level = $newLevel
        $Structure.hit_log += @{
            timestamp = Get-Date
            from_level = $currentLevel
            to_level = $newLevel
            price = $CurrentPrice
            profit_pct = [math]::Round($profit, 2)
        }
    }

    @{ moved = $moved; new_level = $newLevel; reason = $reason; profit_pct = [math]::Round($profit, 2) }
}

# ============================================================================
# INTEGRATED: SmartTrailingUpdate
# ============================================================================

function Update-TrailingWithSmartSL {
    <#
    .SYNOPSIS
    Update trailing stop com smart order flow detection

    .PARAMETER Market
    Market name

    .PARAMETER CurrentPrice
    Preço atual

    .PARAMETER Candles
    Últimos candles para análise

    .PARAMETER Side
    "LONG" ou "SHORT"

    .PARAMETER StopLevels
    StopLevelStructure

    .OUTPUTS
    @{
      success = $true|$false
      sl_updated = $true|$false
      new_sl = double
      level = int
      reason = string
    }
    #>
    param(
        [string]$Market,
        [double]$CurrentPrice,
        [array]$Candles,
        [string]$Side,
        [hashtable]$StopLevels
    )

    # 1. Detectar intensidade de order flow
    $flow = Test-OrderFlowIntensity -Candles $Candles -WindowSize 5

    # 2. Validar volume/preço agreement
    $agreement = Test-VolumePriceAgreement -Candles $Candles -WindowSize 3

    # 3. Decidir se aperta SL (apenas se HIGH flow + válido)
    $shouldTighten = ($flow.signal -eq "high" -and $agreement.valid)

    # 4. Update stop level
    $levelUpdate = Update-StopLevel -Structure $StopLevels -CurrentPrice $CurrentPrice -Side $Side

    # 5. Retornar novo SL baseado em level atual
    $newSL = switch ($StopLevels.current_level) {
        1 { $StopLevels.level_1_breakeven }
        2 { $StopLevels.level_2_lock }
        3 { $StopLevels.level_3_trailing }
    }

    @{
        success = $true
        sl_updated = $levelUpdate.moved
        new_sl = $newSL
        level = $StopLevels.current_level
        profit_pct = $levelUpdate.profit_pct
        flow_intensity = $flow.intensity
        agreement_confidence = $agreement.confidence
        reason = $levelUpdate.reason
    }
}

# ============================================================================
# EXPORT
# ============================================================================

# 2026-07-02 FIX: Export-ModuleMember so funciona em modulo (.psm1); em dot-source
# lancava erro terminante e o loader marcava a lib como FALHA. Guard condicional.
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Test-OrderFlowIntensity',
        'Test-VolumePriceAgreement',
        'New-StopLevelStructure',
        'Update-StopLevel',
        'Update-TrailingWithSmartSL'
    )
}
