# Tests para lib_early_warning_engine.ps1 (Pester v3.4.0 compatible)
# TDD: Valida multi-signal scoring e detecção de setup ripening

Describe "Resolve-EarlyWarningSignal (Early Warning Core)" {
    BeforeAll {
        $root = Get-Location
        . (Join-Path $root "agents\lib_early_warning_engine.ps1")
    }

    Context "Whale Accumulation Signal" {
        It "SCORE 45+ quando accumulation_days >= 3" {
            $whale = @{ accumulation_days = 3 }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -WhaleData $whale
            ($result.whale_score -ge 45) | Should Be $true
        }

        It "SCORE 0 sem whale data" {
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT"
            $result.whale_score | Should Be 0
        }

        It "Signal whale_accumulation adicionado" {
            $whale = @{ accumulation_days = 5 }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -WhaleData $whale
            ($result.signals -contains "whale_accumulation") | Should Be $true
        }
    }

    Context "Tori Setup Ripening" {
        It "SCORE 90 quando proximity < 1.5%" {
            $tori = @{ setup_ripening = $true; proximity_pct = 1.0 }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -ToriData $tori
            $result.tori_score | Should Be 90
        }

        It "SCORE 70 quando setup_ripening=true mas proximity > 1.5%" {
            $tori = @{ setup_ripening = $true; proximity_pct = 2.5 }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -ToriData $tori
            $result.tori_score | Should Be 70
        }

        It "SCORE 0 quando setup_ripening=false" {
            $tori = @{ setup_ripening = $false; proximity_pct = 5.0 }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -ToriData $tori
            $result.tori_score | Should Be 0
        }

        It "Signal tori_ripening adicionado" {
            $tori = @{ setup_ripening = $true; proximity_pct = 0.8 }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -ToriData $tori
            ($result.signals -contains "tori_ripening") | Should Be $true
        }
    }

    Context "Narrativa Quente" {
        It "SCORE 40+ quando FQS >= 5" {
            $narr = @{ fqs_score = 5; keywords_trending = 0; catalyst_days = 30 }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -NarrativeData $narr
            ($result.narrative_score -ge 40) | Should Be $true
        }

        It "SCORE boost com keywords trending" {
            $narr = @{ fqs_score = 6; keywords_trending = 2; catalyst_days = 30 }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -NarrativeData $narr
            ($result.narrative_score -ge 70) | Should Be $true
        }

        It "SCORE boost com catalyst proximo" {
            $narr = @{ fqs_score = 6; keywords_trending = 0; catalyst_days = 3 }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -NarrativeData $narr
            ($result.narrative_score -ge 70) | Should Be $true
        }

        It "Full score 100 com todos factores" {
            $narr = @{ fqs_score = 7; keywords_trending = 3; catalyst_days = 1 }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -NarrativeData $narr
            $result.narrative_score | Should Be 100
        }

        It "Signal narrative_catalyst adicionado" {
            $narr = @{ fqs_score = 5; keywords_trending = 0; catalyst_days = 30 }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -NarrativeData $narr
            ($result.signals -contains "narrative_catalyst") | Should Be $true
        }
    }

    Context "Volume Preparation" {
        It "SCORE 50+ quando vol_spike_3d >= 1.5" {
            $vol = @{ vol_spike_3d = 1.5; orderbook_imbalance = 1.0 }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -VolumeData $vol
            ($result.volume_score -ge 50) | Should Be $true
        }

        It "SCORE bonus com orderbook imbalance comprador" {
            $vol = @{ vol_spike_3d = 1.6; orderbook_imbalance = 2.0 }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -VolumeData $vol
            ($result.volume_score -ge 80) | Should Be $true
        }

        It "SCORE 0 quando vol_spike < 1.5" {
            $vol = @{ vol_spike_3d = 1.2; orderbook_imbalance = 1.5 }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -VolumeData $vol
            $result.volume_score | Should Be 0
        }

        It "Signal volume_preparation adicionado" {
            $vol = @{ vol_spike_3d = 1.7; orderbook_imbalance = 1.5 }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -VolumeData $vol
            ($result.signals -contains "volume_preparation") | Should Be $true
        }
    }

    Context "Macro Alignment" {
        It "Signal macro_bullish em regime BULL_WEAK" {
            $macro = @{ regime = "BULL_WEAK" }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -MacroData $macro
            $result.macro_score | Should Be 40
            ($result.signals -contains "macro_bullish") | Should Be $true
        }

        It "Signal macro_bullish em regime BULL_STRONG" {
            $macro = @{ regime = "BULL_STRONG" }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -MacroData $macro
            ($result.signals -contains "macro_bullish") | Should Be $true
        }

        It "Signal macro_bearish em regime BEAR_WEAK" {
            $macro = @{ regime = "BEAR_WEAK" }
            $result = Resolve-EarlyWarningSignal -Market "PEARLUSDT" -MacroData $macro
            $result.macro_score | Should Be 40
            ($result.signals -contains "macro_bearish") | Should Be $true
        }

        It "SCORE 0 em regime NEUTRAL" {
            $macro = @{ regime = "NEUTRAL" }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -MacroData $macro
            $result.macro_score | Should Be 0
        }
    }

    Context "Multi-Signal Composition" {
        It "2 sinais = score > 50" {
            $whale = @{ accumulation_days = 3 }
            $tori = @{ setup_ripening = $true; proximity_pct = 1.2 }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -WhaleData $whale -ToriData $tori
            $result.signal_count | Should Be 2
            ($result.early_warning_score -gt 50) | Should Be $true
        }

        It "3+ sinais = HIGH confidence" {
            $whale = @{ accumulation_days = 4 }
            $tori = @{ setup_ripening = $true; proximity_pct = 0.9 }
            $narr = @{ fqs_score = 6; keywords_trending = 1; catalyst_days = 2 }
            $vol = @{ vol_spike_3d = 1.6; orderbook_imbalance = 1.9 }
            $macro = @{ regime = "BULL_STRONG" }

            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" `
              -WhaleData $whale -ToriData $tori -NarrativeData $narr `
              -VolumeData $vol -MacroData $macro

            ($result.signal_count -ge 3) | Should Be $true
            $result.confidence | Should Be "HIGH"
        }
    }

    Context "Direction & Action" {
        It "Direction=LONG com 2+ bullish signals" {
            $whale = @{ accumulation_days = 3 }
            $macro = @{ regime = "BULL_STRONG" }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -WhaleData $whale -MacroData $macro
            $result.direction | Should Be "LONG"
        }

        It "Direction=SHORT com 2+ bearish signals" {
            $tori = @{ setup_ripening = $true; proximity_pct = 1.5 }
            $macro = @{ regime = "BEAR_WEAK" }
            $result = Resolve-EarlyWarningSignal -Market "PEARLUSDT" -ToriData $tori -MacroData $macro
            $result.direction | Should Be "SHORT"
        }

        It "Direction=NEUTRAL sem sinais" {
            $result = Resolve-EarlyWarningSignal -Market "UNKNOWNUSDT"
            $result.direction | Should Be "NEUTRAL"
        }
    }

    Context "Edge Cases" {
        It "Output valido com zero sinais" {
            $result = Resolve-EarlyWarningSignal -Market "UNKNOWNUSDT"
            $result.market | Should Be "UNKNOWNUSDT"
            $result.signal_count | Should Be 0
            $result.direction | Should Be "NEUTRAL"
            $result.early_warning_score | Should Be 0
        }

        It "Score nunca excede 100" {
            $whale = @{ accumulation_days = 100 }
            $tori = @{ setup_ripening = $true; proximity_pct = 0.1 }
            $result = Resolve-EarlyWarningSignal -Market "GENSYNUSDT" -WhaleData $whale -ToriData $tori
            ($result.early_warning_score -le 100) | Should Be $true
        }

        It "Market name preservado exato" {
            $result = Resolve-EarlyWarningSignal -Market "GenSynUSDAT"
            $result.market | Should Be "GenSynUSDAT"
        }
    }
}

Describe "Get-EarlyWarningCandidates (Scan Orchestrator)" {
    BeforeAll {
        $root = Get-Location
        . (Join-Path $root "agents\lib_early_warning_engine.ps1")
    }

    It "Retorna array (mesmo vazio) com mercados sem sinais" {
        # Stub atual: Resolve sem dados => score 0 => filtrado (>50)
        $result = @(Get-EarlyWarningCandidates -Markets @("BTCUSDT","ETHUSDT"))
        $result.Count | Should Be 0
    }

    It "Filtra candidatos com score <= 50 (stub retorna vazio)" {
        $result = @(Get-EarlyWarningCandidates -Markets @("SOLUSDT"))
        ($result | Where-Object { $_.early_warning_score -le 50 }).Count | Should Be 0
    }

    It "Usa universo default quando Markets vazio (nao quebra)" {
        # Nao deve lancar excecao mesmo sem mercados explicitos
        { Get-EarlyWarningCandidates } | Should Not Throw
    }

    It "Aceita Regime parametro sem erro" {
        { Get-EarlyWarningCandidates -Markets @("BTCUSDT") -Regime "BULL_STRONG" } | Should Not Throw
    }

    It "Output ordenavel por early_warning_score (contrato de campo)" {
        # Garante que o campo de ordenacao existe no shape do Resolve
        $sample = Resolve-EarlyWarningSignal -Market "BTCUSDT"
        ($sample.PSObject.Properties.Name -contains "early_warning_score") | Should Be $true
    }
}

# Summary: 33 TDD — Resolve (multi-signal) + Get-EarlyWarningCandidates (scan orchestrator)
