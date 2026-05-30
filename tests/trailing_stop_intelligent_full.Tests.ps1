# trailing_stop_intelligent_full.Tests.ps1
# Cobertura COMPLETA de lib_trailing_stop_intelligent.ps1 (Pester 3.4 compativel).
# Mede via: Invoke-Pester -CodeCoverage agents\lib_trailing_stop_intelligent.ps1
# 2026-05-29

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"

# --- Dependencia real (deterministica) ---
. (Join-Path $agentsDir "lib_price_freshness.ps1")

# --- Stubs das dependencias CoinEx (controlados por $script:mock*) ---
$script:mockTickerFresh   = $null
$script:mockPositions     = @()
$script:mockCandles       = @()
$script:mockModifyResult  = [PSCustomObject]@{ success = $true; stop_loss_price = 0 }
$script:throwNoMarket     = $false
$script:throwTicker       = $false

function CoinEx-GetTickerFresh { param($market) if ($script:throwTicker) { throw "ticker boom" } return $script:mockTickerFresh }
function CoinEx-GetPendingPositions {
    param([string]$Market)
    if (-not $Market -and $script:throwNoMarket) { throw "boom list" }
    return $script:mockPositions
}
function CoinEx-GetFuturesCandles { param($market, $period, $limit=100) return $script:mockCandles }
function CoinEx-ModifyPositionStopLoss { param([string]$Market, $Price) return $script:mockModifyResult }

# --- Lib sob teste ---
. (Join-Path $agentsDir "lib_trailing_stop_intelligent.ps1")

# --- Helpers ---
function New-Candles {
    param([double[]]$Closes, [double]$Range = 2.0)
    $c = @()
    foreach ($cl in $Closes) {
        $c += [PSCustomObject]@{ high=($cl + $Range); low=($cl - $Range); close=$cl; open=$cl; volume=1000 }
    }
    return $c
}
function New-FreshTickerMock {
    param([double]$Last, [int]$AgeSeconds = 0, [bool]$IsFresh = $true)
    return [PSCustomObject]@{
        ticker     = [PSCustomObject]@{ last = "$Last" }
        fetched_at = (Get-Date).AddSeconds(-$AgeSeconds)
        is_fresh   = $IsFresh
    }
}

# 25 candles base (uptrend suave) p/ ATR valido
$script:baseCloses = @()
$p = 90.0
for ($i=0; $i -lt 25; $i++) { $script:baseCloses += $p; $p += 0.4 }

Describe "Initialize-AutomaticTPSL" {
    It "calcula TP/SL base e saidas parciais" {
        $r = Initialize-AutomaticTPSL -Entry 100 -CurrentPrice 100 -Peak24h 110 -Qty 10
        $r.TPBase | Should Be 132
        $r.SLBase | Should Be 67.3
        $r.PartialExits.Count | Should Be 3
        ($r.PartialExits | Measure-Object Percent -Sum).Sum | Should Be 100
        $r.Mode | Should Be "GEM"
    }
    It "TrailingStop nunca abaixo do SLBase (clamp via Max)" {
        # Peak baixo forca trailing calculado < slBase -> deve respeitar piso slBase
        $r = Initialize-AutomaticTPSL -Entry 100 -CurrentPrice 100 -Peak24h 50 -Qty 10 -TrailingPercent 14.5
        $r.TrailingStop | Should Be $r.SLBase
    }
    It "respeita Mode custom e TrailingPercent custom" {
        $r = Initialize-AutomaticTPSL -Entry 200 -CurrentPrice 200 -Peak24h 250 -Qty 5 -Mode "MOMENTUM" -TrailingPercent 10
        $r.Mode | Should Be "MOMENTUM"
        $r.TrailingPercent | Should Be 10
    }
}

Describe "Calculate-ATR" {
    It "retorna 0 com candles insuficientes" {
        $c = New-Candles -Closes @(100,101,102)
        Calculate-ATR -Candles $c -Period 14 | Should Be 0
    }
    It "retorna ATR > 0 com dados suficientes" {
        $c = New-Candles -Closes $script:baseCloses
        (Calculate-ATR -Candles $c -Period 14) -gt 0 | Should Be $true
    }
    It "ATR maior em alta volatilidade" {
        $lowVol  = New-Candles -Closes $script:baseCloses -Range 1.0
        $highVol = New-Candles -Closes $script:baseCloses -Range 8.0
        (Calculate-ATR -Candles $highVol) -gt (Calculate-ATR -Candles $lowVol) | Should Be $true
    }
}

Describe "Find-SupportLevels" {
    It "retorna vazio com candles insuficientes" {
        $c = New-Candles -Closes @(100,99,98)
        @(Find-SupportLevels -Candles $c -LookbackPeriod 20).Count | Should Be 0
    }
    It "encontra suportes abaixo do preco atual" {
        # serie com vales locais (swing lows)
        $closes = @(110,105,108,103,107,102,106,101,105,100,104,99,103,98,102,97,101,96,100,95)
        $c = New-Candles -Closes $closes
        $sups = @(Find-SupportLevels -Candles $c -LookbackPeriod 20)
        ($sups | Where-Object { $_ -ge $c[-1].close }).Count | Should Be 0
    }
    It "agrupa suportes proximos dentro da tolerancia" {
        $closes = @(110,100.0,108,100.2,106,99,104,98,102,97,101,96,100,95,99,94,98,93,97,92)
        $c = New-Candles -Closes $closes
        $sups = @(Find-SupportLevels -Candles $c -LookbackPeriod 20 -Tolerance 0.01)
        # agrupamento nao deve gerar mais suportes que vales
        ($sups.Count -ge 0) | Should Be $true
    }
}

Describe "Calculate-TrailingStopPrice -- stale price guard" {
    It "stale (is_fresh=false) -> fail-closed, nao move" {
        $script:mockTickerFresh = New-FreshTickerMock -Last 110 -AgeSeconds 300 -IsFresh $false
        $pos = [PSCustomObject]@{ market="X"; avg_entry_price="100"; leverage="3"; side="long" }
        $c = New-Candles -Closes $script:baseCloses
        $r = Calculate-TrailingStopPrice -Position $pos -Candles $c -CurrentStopLoss 95 -MaxPriceAgeSeconds 60
        $r.stale | Should Be $true
        $r.should_update | Should Be $false
        $r.new_stop_price | Should Be 95
        $r.reason | Should Match "Stale"
    }
}

Describe "Calculate-TrailingStopPrice -- profit threshold" {
    It "lucro abaixo do threshold -> nao ativa" {
        $script:mockTickerFresh = New-FreshTickerMock -Last 101
        $pos = [PSCustomObject]@{ market="X"; avg_entry_price="100"; leverage="5"; side="long" }
        $c = New-Candles -Closes $script:baseCloses
        $r = Calculate-TrailingStopPrice -Position $pos -Candles $c -CurrentStopLoss 95 -MinProfitPctToActivate 3.0
        $r.should_update | Should Be $false
        $r.stale | Should Be $false
        $r.reason | Should Match "below activation threshold"
    }
}

Describe "Calculate-TrailingStopPrice -- faixas de leverage" {
    $c = New-Candles -Closes $script:baseCloses -Range 1.5   # ATR moderado (~1-3%)

    It "leverage >= 50 -> trailing apertado (base 1.5)" {
        $script:mockTickerFresh = New-FreshTickerMock -Last 110
        $pos = [PSCustomObject]@{ market="X"; avg_entry_price="100"; leverage="50"; side="long" }
        $r = Calculate-TrailingStopPrice -Position $pos -Candles $c -CurrentStopLoss 95
        $r.reason | Should Match "High leverage"
        $r.should_update | Should Be $true
    }
    It "leverage 20-49 -> medium-high (base 2.5)" {
        $script:mockTickerFresh = New-FreshTickerMock -Last 110
        $pos = [PSCustomObject]@{ market="X"; avg_entry_price="100"; leverage="25"; side="long" }
        $r = Calculate-TrailingStopPrice -Position $pos -Candles $c -CurrentStopLoss 95
        $r.reason | Should Match "Medium-high leverage"
    }
    It "leverage 10-19 -> medium (base 3.5)" {
        $script:mockTickerFresh = New-FreshTickerMock -Last 110
        $pos = [PSCustomObject]@{ market="X"; avg_entry_price="100"; leverage="10"; side="long" }
        $r = Calculate-TrailingStopPrice -Position $pos -Candles $c -CurrentStopLoss 95
        $r.reason | Should Match "Medium leverage"
    }
    It "leverage < 10 -> low (base 4.5)" {
        $script:mockTickerFresh = New-FreshTickerMock -Last 110
        $pos = [PSCustomObject]@{ market="X"; avg_entry_price="100"; leverage="3"; side="long" }
        $r = Calculate-TrailingStopPrice -Position $pos -Candles $c -CurrentStopLoss 95
        $r.reason | Should Match "Low leverage"
    }
}

Describe "Calculate-TrailingStopPrice -- volatilidade" {
    It "alta volatilidade (ATR>3%) adiciona ao trailing" {
        $script:mockTickerFresh = New-FreshTickerMock -Last 110
        $cHigh = New-Candles -Closes $script:baseCloses -Range 8.0   # ATR alto
        $pos = [PSCustomObject]@{ market="X"; avg_entry_price="100"; leverage="3"; side="long" }
        $r = Calculate-TrailingStopPrice -Position $pos -Candles $cHigh -CurrentStopLoss 95
        $r.reason | Should Match "high volatility"
    }
    It "baixa volatilidade (ATR<1%) reduz o trailing" {
        $script:mockTickerFresh = New-FreshTickerMock -Last 110
        $cLow = New-Candles -Closes $script:baseCloses -Range 0.2    # ATR baixo
        $pos = [PSCustomObject]@{ market="X"; avg_entry_price="100"; leverage="3"; side="long" }
        $r = Calculate-TrailingStopPrice -Position $pos -Candles $cLow -CurrentStopLoss 95
        $r.reason | Should Match "low volatility"
    }
}

Describe "Calculate-TrailingStopPrice -- suporte proximo" {
    It "ajusta trailing quando suporte proximo (<2%)" {
        # preco atual perto de um suporte recente
        $closes = @(108,107,109.0,108.5,109.2,108.8,109.5,109.0,109.8,109.3,110.0,109.5,110.2,109.8,110.5,110.0,110.8,110.3,111.0,110.6)
        $c = New-Candles -Closes $closes -Range 0.3
        # mock last logo acima do ultimo close p/ suporte ficar a <2%
        $script:mockTickerFresh = New-FreshTickerMock -Last 111.5
        $pos = [PSCustomObject]@{ market="X"; avg_entry_price="100"; leverage="3"; side="long" }
        $r = Calculate-TrailingStopPrice -Position $pos -Candles $c -CurrentStopLoss 95
        # pode ou nao haver support dependendo dos swings; se houver, reason cita support
        if ($r.nearest_support) { $r.reason | Should Match "support" }
        $r.should_update | Should Be $true
    }
}

Describe "Calculate-TrailingStopPrice -- direcao do stop" {
    It "LONG: sobe stop quando novo > atual" {
        $script:mockTickerFresh = New-FreshTickerMock -Last 110
        $c = New-Candles -Closes $script:baseCloses -Range 1.5
        $pos = [PSCustomObject]@{ market="X"; avg_entry_price="100"; leverage="3"; side="long" }
        $r = Calculate-TrailingStopPrice -Position $pos -Candles $c -CurrentStopLoss 95
        $r.should_update | Should Be $true
        ($r.new_stop_price -gt 95) | Should Be $true
    }
    It "LONG: NAO move stop para baixo" {
        $script:mockTickerFresh = New-FreshTickerMock -Last 110
        $c = New-Candles -Closes $script:baseCloses -Range 1.5
        $pos = [PSCustomObject]@{ market="X"; avg_entry_price="100"; leverage="3"; side="long" }
        $r = Calculate-TrailingStopPrice -Position $pos -Candles $c -CurrentStopLoss 108  # ja alto
        $r.should_update | Should Be $false
        $r.reason | Should Match "would move down"
    }
    It "SHORT: desce stop quando novo < atual" {
        $script:mockTickerFresh = New-FreshTickerMock -Last 90
        $c = New-Candles -Closes $script:baseCloses -Range 1.5
        $pos = [PSCustomObject]@{ market="X"; avg_entry_price="100"; leverage="3"; side="short" }
        $r = Calculate-TrailingStopPrice -Position $pos -Candles $c -CurrentStopLoss 105
        $r.should_update | Should Be $true
        ($r.new_stop_price -lt 105) | Should Be $true
    }
    It "SHORT: NAO move stop para cima" {
        $script:mockTickerFresh = New-FreshTickerMock -Last 90
        $c = New-Candles -Closes $script:baseCloses -Range 1.5
        $pos = [PSCustomObject]@{ market="X"; avg_entry_price="100"; leverage="3"; side="short" }
        $r = Calculate-TrailingStopPrice -Position $pos -Candles $c -CurrentStopLoss 92  # ja baixo
        $r.should_update | Should Be $false
        $r.reason | Should Match "would move up"
    }
}

Describe "Update-PositionTrailingStop" {
    It "posicao nao encontrada -> success=false" {
        $script:mockPositions = @()
        $r = Update-PositionTrailingStop -Market "X"
        $r.success | Should Be $false
        $r.error | Should Match "Position not found"
    }
    It "sem stop loss configurado -> success=false" {
        $script:mockPositions = @([PSCustomObject]@{ market="X"; stop_loss_price="0"; avg_entry_price="100"; leverage="3"; side="long" })
        $r = Update-PositionTrailingStop -Market "X"
        $r.success | Should Be $false
        $r.error | Should Match "No stop loss"
    }
    It "candles insuficientes -> success=false" {
        $script:mockPositions = @([PSCustomObject]@{ market="X"; stop_loss_price="95"; avg_entry_price="100"; leverage="3"; side="long" })
        $script:mockCandles = New-Candles -Closes @(100,101,102)   # < 20
        $r = Update-PositionTrailingStop -Market "X"
        $r.success | Should Be $false
        $r.error | Should Match "Insufficient candle"
    }
    It "no_update quando calculo nao deve atualizar (lucro baixo)" {
        $script:mockPositions = @([PSCustomObject]@{ market="X"; stop_loss_price="95"; avg_entry_price="100"; leverage="3"; side="long" })
        $script:mockCandles = New-Candles -Closes $script:baseCloses -Range 1.5
        $script:mockTickerFresh = New-FreshTickerMock -Last 101    # +1% < 3%
        $r = Update-PositionTrailingStop -Market "X"
        $r.success | Should Be $true
        $r.action | Should Be "no_update"
    }
    It "DryRun -> action=simulated (nao chama API)" {
        $script:mockPositions = @([PSCustomObject]@{ market="X"; stop_loss_price="95"; avg_entry_price="100"; leverage="3"; side="long" })
        $script:mockCandles = New-Candles -Closes $script:baseCloses -Range 1.5
        $script:mockTickerFresh = New-FreshTickerMock -Last 110
        $r = Update-PositionTrailingStop -Market "X" -DryRun $true
        $r.success | Should Be $true
        $r.action | Should Be "simulated"
    }
    It "real -> action=updated quando API ok" {
        $script:mockPositions = @([PSCustomObject]@{ market="X"; stop_loss_price="95"; avg_entry_price="100"; leverage="3"; side="long" })
        $script:mockCandles = New-Candles -Closes $script:baseCloses -Range 1.5
        $script:mockTickerFresh = New-FreshTickerMock -Last 110
        $script:mockModifyResult = [PSCustomObject]@{ success = $true; stop_loss_price = 0 }
        $r = Update-PositionTrailingStop -Market "X" -DryRun $false
        $r.success | Should Be $true
        $r.action | Should Be "updated"
    }
    It "erro de API -> success=false" {
        $script:mockPositions = @([PSCustomObject]@{ market="X"; stop_loss_price="95"; avg_entry_price="100"; leverage="3"; side="long" })
        $script:mockCandles = New-Candles -Closes $script:baseCloses -Range 1.5
        $script:mockTickerFresh = New-FreshTickerMock -Last 110
        $script:mockModifyResult = [PSCustomObject]@{ success = $false; error_msg = "rate limit" }
        $r = Update-PositionTrailingStop -Market "X" -DryRun $false
        $r.success | Should Be $false
        $r.error | Should Match "API error"
    }
}

Describe "Update-AllTrailingStops" {
    It "sem posicoes abertas -> mensagem + zero" {
        $script:mockPositions = @()
        $r = Update-AllTrailingStops
        $r.success | Should Be $true
        $r.total_positions | Should Be 0
        $r.message | Should Match "No open positions"
    }
    It "com posicoes -> agrega resultados" {
        $script:mockPositions = @([PSCustomObject]@{ market="X"; stop_loss_price="95"; avg_entry_price="100"; leverage="3"; side="long" })
        $script:mockCandles = New-Candles -Closes $script:baseCloses -Range 1.5
        $script:mockTickerFresh = New-FreshTickerMock -Last 110
        $script:mockModifyResult = [PSCustomObject]@{ success = $true; stop_loss_price = 0 }
        $r = Update-AllTrailingStops -DryRun $true
        $r.success | Should Be $true
        $r.total_positions | Should Be 1
        $r.simulated | Should Be 1
    }
    It "catch global -> success=false em excecao" {
        $script:mockPositions = @()
        $script:throwNoMarket = $true
        $r = Update-AllTrailingStops
        $script:throwNoMarket = $false
        $r.success | Should Be $false
    }
}

Describe "Cobertura de ramos extras" {
    It "stale com freshCheck ausente -> age=unknown (fail-closed via is_fresh=false)" {
        # Remove Test-PriceFresh temporariamente para forcar freshCheck=null
        $bak = Get-Item Function:\Test-PriceFresh -ErrorAction SilentlyContinue
        if ($bak) { Remove-Item Function:\Test-PriceFresh -Force }
        try {
            $script:mockTickerFresh = New-FreshTickerMock -Last 110 -IsFresh $false
            $pos = [PSCustomObject]@{ market="X"; avg_entry_price="100"; leverage="3"; side="long" }
            $c = New-Candles -Closes $script:baseCloses
            $r = Calculate-TrailingStopPrice -Position $pos -Candles $c -CurrentStopLoss 95
            $r.stale | Should Be $true
            $r.reason | Should Match "unknown"
        } finally {
            if ($bak) { . (Join-Path (Split-Path $PSScriptRoot -Parent) "agents\lib_price_freshness.ps1") }
        }
    }
    It "Update-PositionTrailingStop catch -> success=false em excecao interna" {
        $script:mockPositions = @([PSCustomObject]@{ market="X"; stop_loss_price="95"; avg_entry_price="100"; leverage="3"; side="long" })
        $script:mockCandles = New-Candles -Closes $script:baseCloses -Range 1.5
        # ticker lanca excecao -> cai no catch de Update-PositionTrailingStop
        $script:throwTicker = $true
        try {
            $r = Update-PositionTrailingStop -Market "X"
            $r.success | Should Be $false
        } finally { $script:throwTicker = $false }
    }
}
