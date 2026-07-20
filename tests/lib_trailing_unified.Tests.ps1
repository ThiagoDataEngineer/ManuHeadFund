# lib_trailing_unified.Tests.ps1 -- TDD do motor unico de trailing
# 2026-07-18: RED phase. Resolve-TrailingDecision substitui a logica
# espalhada em Get-TrailingNewStopAdaptive / Calculate-TrailingStopPrice /
# Get-SmartStopPrice -- um so core, resolvendo por origem do trade
# (asset_class SPOT|FUTURES, trade_style SCALP|SWING).
#
# Reaproveita (nao reescreve): Calculate-ATR (lib_trailing_stop_intelligent),
# Find-SupportLevels (idem), Get-ExhaustionScore (lib_trailing_exhaustion,
# ja testado, nunca ligado), Get-TrendDirection (lib_multiframe_analysis, ja
# usado por lib_trailing_policy_live). Pure function -- sem I/O, sem chamada
# de API, testavel sem mock de rede.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$agentsDir = Join-Path $projectRoot "agents"

. (Join-Path $agentsDir "lib_trailing_exhaustion.ps1")
. (Join-Path $agentsDir "lib_multiframe_analysis.ps1")
. (Join-Path $agentsDir "lib_trailing_stop_intelligent.ps1")
. (Join-Path $agentsDir "lib_trailing_unified.ps1")

function New-Candle {
    param([double]$Open, [double]$High, [double]$Low, [double]$Close, [double]$Volume = 1000)
    [PSCustomObject]@{ open=$Open; high=$High; low=$Low; close=$Close; volume=$Volume }
}

# Gera N candles em uptrend saudavel (sem exhaustion), preco subindo devagar.
function New-HealthyUptrendCandles {
    param([int]$Count = 30, [double]$StartPrice = 100.0, [double]$StepPct = 0.5)
    $candles = @()
    $price = $StartPrice
    for ($i = 0; $i -lt $Count; $i++) {
        $candles += New-Candle -Open $price -High ($price * 1.01) -Low ($price * 0.998) -Close ($price * 1.008) -Volume 1000
        $price = $price * (1 + $StepPct / 100)
    }
    return $candles
}

# Gera candles com exhaustion no topo: sobe, depois ultimo candle e doji+wick+vol seco.
function New-ExhaustedTopCandles {
    param([int]$Count = 30, [double]$StartPrice = 100.0)
    $candles = @(New-HealthyUptrendCandles -Count ($Count - 1) -StartPrice $StartPrice)
    $lastClose = [double]$candles[-1].close
    # doji com wick top grande e volume secando
    $candles += New-Candle -Open $lastClose -High ($lastClose * 1.05) -Low ($lastClose * 0.998) -Close ($lastClose * 1.001) -Volume 200
    return $candles
}

Describe "Resolve-TrailingDecision -- assinatura e fail-safes" {

    It "posicao com origin ausente falha explicito (nao adivinha origem)" {
        # Should Throw esta quebrado neste ambiente Pester 3.4.0 (falha mesmo
        # em "{ throw 'x' } | Should Throw" puro) -- try/catch manual, mesmo
        # padrao ja usado em outros testes do projeto pos essa descoberta.
        $pos = [PSCustomObject]@{
            market="TESTUSDT"; side="LONG"; entry=100.0; stopCurrent=95.0
        }
        $threw = $false
        try {
            Resolve-TrailingDecision -Position $pos -CurrentPrice 105.0 -Candles @(New-HealthyUptrendCandles) | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }

    It "menos de candles minimos -> HOLD (fail-safe, nunca decide as cegas)" {
        $pos = [PSCustomObject]@{
            market="TESTUSDT"; side="LONG"; entry=100.0; stopCurrent=95.0
            origin = @{ asset_class="SPOT"; trade_style="SWING" }
        }
        $r = Resolve-TrailingDecision -Position $pos -CurrentPrice 105.0 -Candles @(New-Candle -Open 100 -High 101 -Low 99 -Close 100)
        $r.action | Should Be "HOLD"
        $r.reason | Should Be "candles_insuficientes"
    }

    It "stop NUNCA recua (LONG: novo >= atual)" {
        $pos = [PSCustomObject]@{
            market="TESTUSDT"; side="LONG"; entry=100.0; stopCurrent=99.0
            origin = @{ asset_class="SPOT"; trade_style="SWING" }
        }
        $candles = New-HealthyUptrendCandles -Count 30 -StartPrice 100 -StepPct 0.1
        $r = Resolve-TrailingDecision -Position $pos -CurrentPrice 101.0 -Candles $candles
        ($r.new_stop -ge 99.0) | Should Be $true
    }

    It "stop NUNCA recua (SHORT: novo <= atual)" {
        $pos = [PSCustomObject]@{
            market="TESTUSDT"; side="SHORT"; entry=100.0; stopCurrent=101.0
            origin = @{ asset_class="FUTURES"; trade_style="SWING" }
        }
        $candles = New-HealthyUptrendCandles -Count 30 -StartPrice 100 -StepPct -0.1
        $r = Resolve-TrailingDecision -Position $pos -CurrentPrice 99.0 -Candles $candles
        ($r.new_stop -le 101.0) | Should Be $true
    }
}

Describe "Resolve-TrailingDecision -- resolver por trade_style" {

    It "SCALP usa ATR curto (period 7) -- reage mais rapido que SWING" {
        $pos = [PSCustomObject]@{
            market="SCALPUSDT"; side="LONG"; entry=100.0; stopCurrent=98.0
            origin = @{ asset_class="SPOT"; trade_style="SCALP" }
        }
        $candles = New-HealthyUptrendCandles -Count 30 -StartPrice 100 -StepPct 0.3
        $r = Resolve-TrailingDecision -Position $pos -CurrentPrice ([double]$candles[-1].close) -Candles $candles
        $r.atr_period | Should Be 7
    }

    It "SWING usa ATR longo (period 14) -- padrao mais estavel" {
        $pos = [PSCustomObject]@{
            market="SWINGUSDT"; side="LONG"; entry=100.0; stopCurrent=98.0
            origin = @{ asset_class="SPOT"; trade_style="SWING" }
        }
        $candles = New-HealthyUptrendCandles -Count 30 -StartPrice 100 -StepPct 0.3
        $r = Resolve-TrailingDecision -Position $pos -CurrentPrice ([double]$candles[-1].close) -Candles $candles
        $r.atr_period | Should Be 14
    }

    It "trade_style desconhecido -> HOLD explicito (fail-safe, nao assume SWING)" {
        $pos = [PSCustomObject]@{
            market="TESTUSDT"; side="LONG"; entry=100.0; stopCurrent=98.0
            origin = @{ asset_class="SPOT"; trade_style="BANANA" }
        }
        $candles = New-HealthyUptrendCandles -Count 30
        $r = Resolve-TrailingDecision -Position $pos -CurrentPrice 105.0 -Candles $candles
        $r.action | Should Be "HOLD"
        $r.reason | Should Be "trade_style_desconhecido"
    }
}

Describe "Resolve-TrailingDecision -- resolver por asset_class (leverage)" {

    It "FUTURES com leverage alto aperta trailing_pct vs FUTURES leverage baixo" {
        $candles = New-HealthyUptrendCandles -Count 30 -StartPrice 100 -StepPct 0.3
        $price = [double]$candles[-1].close

        $posHighLev = [PSCustomObject]@{
            market="HLUSDT"; side="LONG"; entry=100.0; stopCurrent=98.0; leverage=50
            origin = @{ asset_class="FUTURES"; trade_style="SWING" }
        }
        $posLowLev = [PSCustomObject]@{
            market="LLUSDT"; side="LONG"; entry=100.0; stopCurrent=98.0; leverage=3
            origin = @{ asset_class="FUTURES"; trade_style="SWING" }
        }

        $rHigh = Resolve-TrailingDecision -Position $posHighLev -CurrentPrice $price -Candles $candles
        $rLow  = Resolve-TrailingDecision -Position $posLowLev  -CurrentPrice $price -Candles $candles

        ($rHigh.trailing_pct -lt $rLow.trailing_pct) | Should Be $true
    }

    It "SPOT ignora leverage (nao aplica ajuste, mesmo se campo presente por engano)" {
        $candles = New-HealthyUptrendCandles -Count 30 -StartPrice 100 -StepPct 0.3
        $price = [double]$candles[-1].close
        $pos = [PSCustomObject]@{
            market="SPOTUSDT"; side="LONG"; entry=100.0; stopCurrent=98.0; leverage=50
            origin = @{ asset_class="SPOT"; trade_style="SWING" }
        }
        $r = Resolve-TrailingDecision -Position $pos -CurrentPrice $price -Candles $candles
        $r.leverage_applied | Should Be $false
    }
}

Describe "Resolve-TrailingDecision -- exhaustion aperta o stop" {

    It "exhaustion alto (doji+wick+vol seco no topo) aperta stop MAIS que uptrend saudavel" {
        $healthyCandles = New-HealthyUptrendCandles -Count 30 -StartPrice 100 -StepPct 0.5
        $exhaustedCandles = New-ExhaustedTopCandles -Count 30 -StartPrice 100

        $posHealthy = [PSCustomObject]@{
            market="HEALTHUSDT"; side="LONG"; entry=100.0; stopCurrent=98.0
            origin = @{ asset_class="SPOT"; trade_style="SWING" }
        }
        $posExhausted = [PSCustomObject]@{
            market="EXHAUSTUSDT"; side="LONG"; entry=100.0; stopCurrent=98.0
            origin = @{ asset_class="SPOT"; trade_style="SWING" }
        }

        $priceHealthy = [double]$healthyCandles[-1].close
        $priceExhausted = [double]$exhaustedCandles[-1].close

        $rHealthy = Resolve-TrailingDecision -Position $posHealthy -CurrentPrice $priceHealthy -Candles $healthyCandles
        $rExhausted = Resolve-TrailingDecision -Position $posExhausted -CurrentPrice $priceExhausted -Candles $exhaustedCandles

        $rExhausted.exhaustion_score | Should BeGreaterThan $rHealthy.exhaustion_score
        # distancia relativa do stop ao preco atual: exhausted deve ser MENOR (mais apertado)
        $distHealthy = ($priceHealthy - $rHealthy.new_stop) / $priceHealthy
        $distExhausted = ($priceExhausted - $rExhausted.new_stop) / $priceExhausted
        ($distExhausted -lt $distHealthy) | Should Be $true
    }

    It "SHORT: exhaustion no fundo (wick bottom) tambem aperta" {
        # Downtrend saudavel pra SHORT, depois candle de exaustao no fundo
        $candles = @()
        $price = 100.0
        for ($i = 0; $i -lt 29; $i++) {
            $candles += New-Candle -Open $price -High ($price * 1.002) -Low ($price * 0.99) -Close ($price * 0.992) -Volume 1000
            $price = $price * 0.995
        }
        $lastClose = $price
        # wick bottom grande (rejeicao de queda) + vol seco
        $candles += New-Candle -Open $lastClose -High ($lastClose * 1.001) -Low ($lastClose * 0.95) -Close ($lastClose * 0.999) -Volume 200

        $pos = [PSCustomObject]@{
            market="SHORTUSDT"; side="SHORT"; entry=100.0; stopCurrent=102.0
            origin = @{ asset_class="FUTURES"; trade_style="SWING" }
        }
        $r = Resolve-TrailingDecision -Position $pos -CurrentPrice $lastClose -Candles $candles
        $r.exhaustion_score | Should BeGreaterThan 0
    }
}

Describe "Resolve-TrailingDecision -- output shape (contrato estavel p/ downstream)" {

    It "retorna todos os campos esperados por Sync-TrailingToExchange" {
        $candles = New-HealthyUptrendCandles -Count 30
        $pos = [PSCustomObject]@{
            market="SHAPEUSDT"; side="LONG"; entry=100.0; stopCurrent=98.0
            origin = @{ asset_class="SPOT"; trade_style="SWING" }
        }
        $r = Resolve-TrailingDecision -Position $pos -CurrentPrice 105.0 -Candles $candles

        # Should Contain (Pester 3.4.0) trata o operando como PATH DE ARQUIVO,
        # nao membro de array -- comportamento surpreendente da versao antiga.
        # -contains (operador nativo PowerShell) e o jeito correto de checar
        # pertinencia em array aqui.
        $names = @($r.PSObject.Properties.Name)
        ($names -contains "action")           | Should Be $true
        ($names -contains "new_stop")         | Should Be $true
        ($names -contains "reason")           | Should Be $true
        ($names -contains "exhaustion_score") | Should Be $true
        ($names -contains "atr_period")       | Should Be $true
        ($names -contains "trailing_pct")     | Should Be $true
        ($names -contains "leverage_applied") | Should Be $true
    }

    It "action=HOLD quando calculo nao melhora o stop existente" {
        # preco mal se moveu -- stop calculado deve ficar igual ou pior que o atual
        $pos = [PSCustomObject]@{
            market="FLATUSDT"; side="LONG"; entry=100.0; stopCurrent=99.5
            origin = @{ asset_class="SPOT"; trade_style="SWING" }
        }
        $flatCandles = 1..30 | ForEach-Object { New-Candle -Open 100 -High 100.1 -Low 99.9 -Close 100 -Volume 1000 }
        $r = Resolve-TrailingDecision -Position $pos -CurrentPrice 100.0 -Candles $flatCandles
        $r.action | Should Be "HOLD"
    }
}
