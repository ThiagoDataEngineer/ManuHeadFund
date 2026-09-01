# lib_sizing_dynamics.ps1 -- Sizing dinamico (SPOT vs FUTURES, regime-aware)
# Capital total = Spot + Futures. Aloca % por regime. Calcula size por trade respeitando risco 1%

function Get-DynamicCapitalAllocation {
    [CmdletBinding()]
    param(
        [double]$SpotUsdt,
        [double]$FuturesUsdt,
        [string]$Regime = "BEAR_WEAK"
    )

    $total = $SpotUsdt + $FuturesUsdt
    if ($total -le 0) { return $null }

    # Regime-aware: BEAR favorece SHORT (80%), BULL favorece LONG (70%)
    $shortPct, $longPct = switch ($Regime) {
        "BEAR_WEAK"   { 0.80, 0.20 }
        "BEAR_STRONG" { 0.85, 0.15 }
        "BULL_WEAK"   { 0.30, 0.70 }
        "BULL_STRONG" { 0.20, 0.80 }
        default       { 0.50, 0.50 }
    }

    @{
        total_usdt    = $total
        short_alloc   = $total * $shortPct  # futures 20x leverage
        long_alloc    = $total * $longPct   # spot 1x
        short_pct     = $shortPct
        long_pct      = $longPct
    }
}

function Get-SizePerTrade {
    [CmdletBinding()]
    param(
        [double]$AllocatedCapital,
        [int]$MaxConcurrentTrades = 5,
        [double]$RiskTolerancePct = 0.01,  # 1% max loss total
        [double]$StopLossPct = 0.02,       # 2% stop-loss width
        # 2026-08-04: owner pediu pesar o sizing pela FORCA do sinal (score
        # 0-100 do gem, ja usado em varios gates) -- multiplicador de
        # Get-SignalStrengthWeight. Default 1.0 preserva o calculo antigo
        # (nenhum caller existente quebra sem passar este parametro).
        [double]$SignalWeight = 1.0
    )

    # Max perda tolerada = 1% do capital total
    $maxLossTotal = $AllocatedCapital * $RiskTolerancePct

    # Distribui entre trades concorrentes
    $maxLossPerTrade = $maxLossTotal / $MaxConcurrentTrades

    # Size = max_loss_per_trade / stop_width (aprox), pesado pela forca do sinal
    $sizeUsdt = ($maxLossPerTrade / $StopLossPct) * $SignalWeight

    [math]::Round($sizeUsdt, 2)
}

# 2026-08-04: owner percebeu (discutindo "como ganhar mais" nas posicoes
# reais abertas -- margem de $20-70 numa conta de $5056, so 9.65% do
# capital FUTURES alocado) que o sizing usa MaxConcurrentTrades=15 fixo
# como divisor, diluindo cada trade igualmente independente da forca do
# sinal. Get-SignalStrengthWeight decide o multiplicador (escalonado por
# faixa, nao continuo -- mais simples de auditar) a partir de $Gem.score
# (0-100, ja usado em varios gates -- scoreMin bloqueia abaixo de um piso
# ~65, scores reais de producao vao ate 90+): sinal forte ganha fatia
# maior (ate 1.5x), sinal no piso do gate ainda passa mas com menos
# conviccao (0.6x). Afeta os 2 lados igualmente (SPOT e FUTURES) --
# Get-SizePerTrade e chamada com o mesmo $Gem.score independente de qual
# alloc (short_alloc/long_alloc) foi escolhida.
function Get-SignalStrengthWeight {
    [CmdletBinding()]
    param([double]$Score = 0)

    if ($Score -ge 90) { return 1.5 }
    if ($Score -ge 75) { return 1.0 }
    return 0.6
}

function Test-SizingValidation {
    [CmdletBinding()]
    param(
        [double]$SizeUsdt,
        [double]$CapitalUsdt,
        [double]$Leverage = 1.0
    )

    $maxPctCapital = 5.0  # max 5% por trade
    $singlePct = ($SizeUsdt * $Leverage / $CapitalUsdt) * 100

    if ($singlePct -gt $maxPctCapital) {
        return @{ valid = $false; reason = "size_exceeds_5pct_capital ($singlePct%)" }
    }

    @{ valid = $true; size_pct = [math]::Round($singlePct, 2) }
}

function Resolve-StopTargetPct {
    # 2026-06-17: conserta StopPct=0 -- gems TRIGGER tem sizing sem stop_pct/target_pct
    # -> Calculate-StopTarget lancava. Aqui devolve fracoes validas com default R:R 1:5.
    #
    # 2026-09-01 FIX CRITICO: DefaultStop=0.02 era o MESMO fallback de emergencia
    # que ja tinha causado o bug real corrigido em 2026-08-25 (commit 0f60b6e,
    # GEM_STOP_TRIGGER_1H) -- aquele fix so populou stop_pct na ORIGEM (5 pontos
    # de scripts/gem_loop.ps1: TRIGGER/TORI_SHORT/TORI_LONG/TORI_*_15M), nunca
    # mudou o DEFAULT desta funcao central. Achado real (owner, extrato CoinEx):
    # ARBUSDT reabriu e stopou 4x em 6h via caminho DIFERENTE (discovery scan +
    # conviction override em gem_executor.ps1, mode=STANDARD) que tambem cai
    # aqui sem popular sizing.stop_pct -- 4 entradas confirmadas com
    # stop_pct=2.00% cravado, -$19.62 em 6h so nesse mercado. Mesma causa raiz,
    # 4o caminho nao coberto pelo fix anterior. Default agora usa a MESMA
    # constante calibrada por ATR real (GEM_STOP_TRIGGER_1H=3%, config.ps1) em
    # vez de reintroduzir 2% hardcoded -- qualquer caminho futuro que caia no
    # default (por nao popular stop_pct explicito) usa o valor ja validado, nao
    # o fallback de emergencia nunca pensado como stop de producao.
    [CmdletBinding()]
    param(
        [object] $Sizing,
        [double] $DefaultStop   = 0,   # 0 = usa $global:GEM_STOP_TRIGGER_1H se definido, senao 0.03
        [double] $DefaultTarget = 0.10   # R:R 1:5
    )

    if ($DefaultStop -le 0) {
        $DefaultStop = if ($global:GEM_STOP_TRIGGER_1H -and [double]$global:GEM_STOP_TRIGGER_1H -gt 0) {
            [double]$global:GEM_STOP_TRIGGER_1H
        } else { 0.03 }
    }

    $stop = $null; $tgt = $null
    if ($Sizing) {
        if ($Sizing.PSObject.Properties['stop_pct'])   { $stop = $Sizing.stop_pct }
        elseif ($Sizing -is [hashtable] -and $Sizing.ContainsKey('stop_pct')) { $stop = $Sizing['stop_pct'] }
        if ($Sizing.PSObject.Properties['target_pct']) { $tgt = $Sizing.target_pct }
        elseif ($Sizing -is [hashtable] -and $Sizing.ContainsKey('target_pct')) { $tgt = $Sizing['target_pct'] }
    }

    $stopD = [double]($stop)
    $tgtD  = [double]($tgt)
    if ($stopD -le 0 -or $stopD -ge 1) { $stopD = $DefaultStop }
    if ($tgtD  -le 0)                  { $tgtD  = $DefaultTarget }

    @{ stop_pct = $stopD; target_pct = $tgtD }
}

# Export-ModuleMember nao necessario em dot-source; comentado para compatibilidade Pester
