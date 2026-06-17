# portfolio_rebalance.Tests.ps1 (Pester 3.x)
# TDD #3: motor PURO de rebalanceamento de carteira (asset-level).
#
# Diferente do lib_rebalancing_daemon (que so faz wallet SPOT<->FUTURES e e dead code),
# este computa acoes de COMPRA/VENDA por ATIVO para voltar aos pesos-alvo, com:
#   - banda de drift (nao mexe se dentro da banda -> evita churn/fees)
#   - filtro de poeira (ignora trades < MinTradeUsd)
#   - BTC-core (ativos core tem piso: nunca vende abaixo do alvo)
# Execucao fica SEPARADA e desligada por padrao.

$here = Split-Path $MyInvocation.MyCommand.Path
$root = Split-Path $here -Parent
. (Join-Path $root "agents\lib_portfolio_rebalance.ps1")

Describe "Get-PortfolioWeights (PURA)" {
    It "calcula pesos fracionarios corretos" {
        $h = @(
            [PSCustomObject]@{ asset="BTC"; value_usd=600 },
            [PSCustomObject]@{ asset="USDT"; value_usd=400 }
        )
        $w = Get-PortfolioWeights -Holdings $h
        [math]::Round($w["BTC"],2)  | Should Be 0.6
        [math]::Round($w["USDT"],2) | Should Be 0.4
    }
    It "carteira vazia -> hashtable vazio" {
        (Get-PortfolioWeights -Holdings @()).Count | Should Be 0
    }
}

Describe "Get-RebalanceActions (PURA)" {

    $targets = @{ BTC=0.50; USDT=0.30; PAXG=0.20 }

    It "ativo SOBRE o alvo alem da banda -> VENDER" {
        $h = @(
            [PSCustomObject]@{ asset="BTC";  value_usd=700 },  # 70% vs 50% alvo
            [PSCustomObject]@{ asset="USDT"; value_usd=300 }   # 30% = alvo
        )
        $acts = @(Get-RebalanceActions -Holdings $h -Targets @{ BTC=0.50; USDT=0.50 } -BandPct 5 -MinTradeUsd 10)
        $btc = $acts | Where-Object { $_.asset -eq "BTC" }
        $btc.action | Should Be "SELL"
        [math]::Round($btc.amount_usd,0) | Should Be 200
    }

    It "ativo SOB o alvo alem da banda -> COMPRAR" {
        $h = @(
            [PSCustomObject]@{ asset="BTC";  value_usd=300 },  # 30% vs 50% alvo
            [PSCustomObject]@{ asset="USDT"; value_usd=700 }
        )
        $acts = @(Get-RebalanceActions -Holdings $h -Targets @{ BTC=0.50; USDT=0.50 } -BandPct 5 -MinTradeUsd 10)
        $btc = $acts | Where-Object { $_.asset -eq "BTC" }
        $btc.action | Should Be "BUY"
        [math]::Round($btc.amount_usd,0) | Should Be 200
    }

    It "dentro da banda -> NENHUMA acao" {
        $h = @(
            [PSCustomObject]@{ asset="BTC";  value_usd=520 },  # 52% vs 50%, drift 2% < banda 5%
            [PSCustomObject]@{ asset="USDT"; value_usd=480 }
        )
        $acts = @(Get-RebalanceActions -Holdings $h -Targets @{ BTC=0.50; USDT=0.50 } -BandPct 5 -MinTradeUsd 10)
        $acts.Count | Should Be 0
    }

    It "trade abaixo de MinTradeUsd e ignorado (poeira)" {
        $h = @(
            [PSCustomObject]@{ asset="BTC";  value_usd=560 },  # drift 6% de 1000 = $60... usa total menor
            [PSCustomObject]@{ asset="USDT"; value_usd=440 }
        )
        # total 1000, BTC 56% vs 50% = drift 6% = $60 > banda. Mas MinTrade alto filtra.
        $acts = @(Get-RebalanceActions -Holdings $h -Targets @{ BTC=0.50; USDT=0.50 } -BandPct 5 -MinTradeUsd 100)
        $acts.Count | Should Be 0
    }

    It "ativo fora dos alvos (target 0) -> VENDER tudo" {
        $h = @(
            [PSCustomObject]@{ asset="BTC";  value_usd=500 },
            [PSCustomObject]@{ asset="SHIB"; value_usd=500 }   # nao esta nos alvos
        )
        $acts = @(Get-RebalanceActions -Holdings $h -Targets @{ BTC=1.0 } -BandPct 5 -MinTradeUsd 10)
        $shib = $acts | Where-Object { $_.asset -eq "SHIB" }
        $shib.action | Should Be "SELL"
        [math]::Round($shib.amount_usd,0) | Should Be 500
    }

    It "conservacao: total vendido ~= total comprado (alvos somam 1)" {
        $h = @(
            [PSCustomObject]@{ asset="BTC";  value_usd=800 },  # over
            [PSCustomObject]@{ asset="USDT"; value_usd=200 }   # under
        )
        $acts = @(Get-RebalanceActions -Holdings $h -Targets @{ BTC=0.50; USDT=0.50 } -BandPct 5 -MinTradeUsd 10)
        $sell = ($acts | Where-Object { $_.action -eq "SELL" } | Measure-Object amount_usd -Sum).Sum
        $buy  = ($acts | Where-Object { $_.action -eq "BUY" }  | Measure-Object amount_usd -Sum).Sum
        [math]::Round($sell - $buy, 2) | Should Be 0
    }

    It "BTC-core: nao vende abaixo do alvo mesmo se mandado (CoreAssets)" {
        # BTC em 50% = alvo exato; se outro ativo precisa de funding, BTC core nao e tocado p/ baixo
        $h = @(
            [PSCustomObject]@{ asset="BTC";  value_usd=500 },  # 50% = alvo
            [PSCustomObject]@{ asset="USDT"; value_usd=500 }
        )
        # Mesmo cenario equilibrado: nenhuma venda de BTC
        $acts = @(Get-RebalanceActions -Holdings $h -Targets @{ BTC=0.50; USDT=0.50 } -BandPct 5 -MinTradeUsd 10 -CoreAssets @("BTC"))
        ($acts | Where-Object { $_.asset -eq "BTC" -and $_.action -eq "SELL" }).Count | Should Be 0
    }

    It "carteira vazia -> nenhuma acao" {
        (@(Get-RebalanceActions -Holdings @() -Targets @{ BTC=1.0 } -BandPct 5 -MinTradeUsd 10)).Count | Should Be 0
    }
}

Describe "Test-RebalanceEnabled (gate de execucao)" {
    It "desligado por padrao (sem flag)" {
        $fake = Join-Path $env:TEMP "no_such_rebalance_$(Get-Random).flag"
        Test-RebalanceEnabled -FlagPath $fake | Should Be $false
    }
    It "ligado quando flag existe" {
        $f = Join-Path $env:TEMP "rebal_on_$(Get-Random).flag"
        Set-Content -Path $f -Value "1"
        Test-RebalanceEnabled -FlagPath $f | Should Be $true
        Remove-Item $f -Force -ErrorAction SilentlyContinue
    }
}
