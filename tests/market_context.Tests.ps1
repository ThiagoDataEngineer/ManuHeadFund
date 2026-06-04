# market_context.Tests.ps1 -- TDD halving phase + context panel
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_telegram.ps1")
. (Join-Path $agentsDir "lib_market_context_engine.ps1")
. (Join-Path $agentsDir "lib_market_context.ps1")

Describe "Get-HalvingPhase" {

    It "PRE_HALVING quando data antes 2024-04-19" {
        $r = Get-HalvingPhase -DateBrt ([DateTime]"2024-01-01")
        $r | Should Be "pre_halving"
    }

    It "ACUMULACAO em mes 3 pos-halving" {
        $r = Get-HalvingPhase -DateBrt ([DateTime]"2024-07-19")  # ~3 meses
        $r | Should Be "phase_1_bull"
    }

    It "MID_BULL em mes 13 (atual)" {
        $r = Get-HalvingPhase -DateBrt ([DateTime]"2025-05-18")  # ~13 meses
        $r | Should Be "phase_2_top"
    }

    It "BEAR em mes 19 (fase 3)" {
        $r = Get-HalvingPhase -DateBrt ([DateTime]"2025-11-19")  # ~19 meses
        $r | Should Be "phase_3_bear"
    }

    It "BEAR_TERRITORY em mes 26" {
        $r = Get-HalvingPhase -DateBrt ([DateTime]"2026-06-19")  # ~26 meses
        $r | Should Be "phase_3_bear"
    }

    It "verdict nunca vazio" {
        $r = Get-HalvingPhase -DateBrt (Get-Date)
        $r.Length | Should BeGreaterThan 5
    }

    It "atual (2026-05-18) deve estar BEAR_TERRITORY (mes ~25)" {
        $r = Get-HalvingPhase -DateBrt ([DateTime]"2026-05-18")
        ($r -eq "phase_3_bear" -or $r -eq "phase_4_recovery") | Should Be $true
    }
}

Describe "Get-MiningCostContext" {

    It "ratio < 0.91 -> CAPITULATION_BOTTOM_LIKELY" {
        $r = Get-MiningCostContext -BtcPriceUsd 30000 -MiningCostGlobal 55000
        $r.status | Should Be "CAPITULATION_BOTTOM_LIKELY"
        $r.ratio | Should Be 0.55
    }

    It "ratio entre 1.0 e 1.1 -> EARLY WARNING" {
        $r = Get-MiningCostContext -BtcPriceUsd 58000 -MiningCostGlobal 55000
        $r.status | Should Be "CAPITULATION_RISK_EARLY_WARNING"
    }

    It "ratio 2.0x -> MUITO_LUCRATIVO" {
        $r = Get-MiningCostContext -BtcPriceUsd 110000 -MiningCostGlobal 55000
        $r.status | Should Be "MUITO_LUCRATIVO"
    }

    It "verdict nunca vazio" {
        $r = Get-MiningCostContext -BtcPriceUsd 108000
        $r.verdict.Length | Should BeGreaterThan 5
    }
}

Describe "Get-IntradayWindowContext" {
    # UTC datetime explicito (evita timezone conversion bug em PS DateTime parse)
    It "2h UTC = ASIA_OPEN" {
        $dt = [DateTime]::new(2026, 5, 18, 2, 0, 0, [DateTimeKind]::Utc)
        $r = Get-IntradayWindowContext -AsOf $dt
        $r.window | Should Be "ASIA_OPEN"
    }
    It "10h UTC = EU_OPEN" {
        $dt = [DateTime]::new(2026, 5, 18, 10, 0, 0, [DateTimeKind]::Utc)
        $r = Get-IntradayWindowContext -AsOf $dt
        $r.window | Should Be "EU_OPEN"
    }
    It "14h UTC = EU_US_OVERLAP (volume max)" {
        $dt = [DateTime]::new(2026, 5, 18, 14, 0, 0, [DateTimeKind]::Utc)
        $r = Get-IntradayWindowContext -AsOf $dt
        $r.window | Should Be "EU_US_OVERLAP"
        $r.volume_tier | Should Match "MAX"
    }
    It "18h UTC = US_OPEN" {
        $dt = [DateTime]::new(2026, 5, 18, 18, 0, 0, [DateTimeKind]::Utc)
        $r = Get-IntradayWindowContext -AsOf $dt
        $r.window | Should Be "US_OPEN"
    }
    It "22h UTC = LATE_NIGHT (volume minimo)" {
        $dt = [DateTime]::new(2026, 5, 18, 22, 0, 0, [DateTimeKind]::Utc)
        $r = Get-IntradayWindowContext -AsOf $dt
        $r.window | Should Be "LATE_NIGHT"
        $r.volume_tier | Should Match "MINIMO"
    }
    It "edge_factor=1.0 (Versao A info-only)" {
        $r = Get-IntradayWindowContext
        $r.edge_factor | Should Be 1.0
    }
}

Describe "Get-AllocationContext" {
    It "MINIMAL quando CoinEx balance < `$100" {
        $r = Get-AllocationContext -CoinexBalanceUsd 50
        $r.status | Should Be "MINIMAL"
    }
    It "LOW em balance `$300" {
        $r = Get-AllocationContext -CoinexBalanceUsd 300
        $r.status | Should Be "LOW"
    }
    It "OPERATIONAL em balance `$1500" {
        $r = Get-AllocationContext -CoinexBalanceUsd 1500
        $r.status | Should Be "OPERATIONAL"
    }
    It "HIGH_CAPITAL em balance `$10000" {
        $r = Get-AllocationContext -CoinexBalanceUsd 10000
        $r.status | Should Be "HIGH_CAPITAL"
    }
    It "sizing_headroom calculado" {
        $r = Get-AllocationContext -CoinexBalanceUsd 1000
        # $1000 / $100 max_size = 10x headroom
        $r.sizing_headroom | Should Be 10
    }
}

Describe "Get-WhaleAccumulationContext" {
    It "tenta blockchain.info ou retorna unavailable" {
        $r = Get-WhaleAccumulationContext
        # Versao B (2026-05-18): pode estar available=true via blockchain.info
        # ou false se fetch falhar. Ambos validos.
        ($r.PSObject.Properties.Name -contains "available") | Should Be $true
    }
    It "tem url_manual" {
        $r = Get-WhaleAccumulationContext
        $r.url_manual.Length | Should BeGreaterThan 10
    }
}

Describe "Format-MarketContextPanel" {

    It "contem CONTEXTO MACRO header" {
        $msg = Format-MarketContextPanel
        $msg | Should Match "CONTEXTO MACRO"
    }

    It "contem Halving" {
        $msg = Format-MarketContextPanel
        $msg | Should Match "Halving"
    }

    It "contem Mining cost ratio" {
        $msg = Format-MarketContextPanel
        $msg | Should Match "Mining"
    }

    It "contem ETF" {
        $msg = Format-MarketContextPanel
        $msg | Should Match "ETF"
    }

    It "contem Whales OU OnChain (blockchain.info active)" {
        $msg = Format-MarketContextPanel
        # Versao B (2026-05-18): label muda conforme source disponivel
        ($msg -match "Whales|OnChain") | Should Be $true
    }

    It "contem Janela intraday" {
        $msg = Format-MarketContextPanel
        $msg | Should Match "Janela"
    }

    It "contem CoinEx info quando AllocationContext disponivel" {
        # mock CoinEx-GetTotalCapitalUSDT pra retornar valor previsivel
        function CoinEx-GetTotalCapitalUSDT { return 1500.0 }
        $msg = Format-MarketContextPanel
        ($msg -match "CoinEx|Balance") | Should Be $true
    }
}
