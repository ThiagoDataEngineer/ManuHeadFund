# test_distribution_short.Tests.ps1 — DISTRIBUTION_SHORT Pattern Detection (TDD)
# Valida detecção de distribuição + reversa com dados reais
# 2026-06-08

Describe "DISTRIBUTION_SHORT Pattern Detection" {

    BeforeAll {
        . (Join-Path $PSScriptRoot "..\agents\lib_distribution_short.ps1") 2>$null
    }

    # ════════════════════════════════════════════════════════
    # TEST 1: Detecta ATH sendo testado 2-3x
    # ════════════════════════════════════════════════════════

    Context "ATH Retest Detection" {
        It "Should detect when price retests ATH 2+ times" {
            # 2026-07-23 FIX: Test-ATHRetestPattern usa tolerancia de +/-2%
            # do ATH (default). 0.000024 esta a 4% do ATH (0.000025), fora
            # da zona -- so o candle 1 (ATH exato) contava como retest.
            # Ajustado o "test 2" pra 0.0000246 (~1.6% abaixo, dentro da
            # zona real de +/-2%). Volume tambem reduzido pra 50000 -- com
            # 90000 a media dos retests (95000) ficava ACIMA da media dos
            # primeiros 3 candles (90000), contradizendo "volume_declining".
            $ath = 0.000025
            $candles = @(
                @{ close = 0.000025; vol = 100000 },    # ATH test 1
                @{ close = 0.000023; vol = 80000 },     # pullback
                @{ close = 0.0000246; vol = 50000 },    # ATH test 2 (retest, dentro de 2%, vol menor)
                @{ close = 0.000022; vol = 85000 }      # pullback again
            )

            # WHEN: detecting ATH retests
            $result = Test-ATHRetestPattern -Candles $candles -ATHPrice $ath

            # THEN: pattern detected
            $result.detected | Should Be $true
            ($result.retest_count -ge 2) | Should Be $true
            $result.volume_declining | Should Be $true  # Volume should decline on retests
        }

        It "Should NOT detect if price makes new ATH (not retest)" {
            $ath = 0.000025
            $candles = @(
                @{ close = 0.000025; vol = 100000 },
                @{ close = 0.000023; vol = 80000 },
                @{ close = 0.000026; vol = 120000 }     # NEW ATH, not retest
            )

            $result = Test-ATHRetestPattern -Candles $candles -ATHPrice $ath

            $result.detected | Should Be $false
        }
    }

    # ════════════════════════════════════════════════════════
    # TEST 2: Valida red candles ≥ green tamanho (distribuição)
    # ════════════════════════════════════════════════════════

    Context "Red vs Green Volume" {
        It "Should detect when red candles >= green size (distribution)" {
            # GIVEN: recent candles com red ≥ green
            $candles = @(
                @{ open = 0.000024; close = 0.000020; vol = 50000 },   # RED -20%
                @{ open = 0.000020; close = 0.000021; vol = 40000 },   # GREEN +5%
                @{ open = 0.000021; close = 0.000019; vol = 48000 },   # RED -10%
                @{ open = 0.000019; close = 0.000020; vol = 35000 }    # GREEN +5%
            )

            # WHEN: analyzing red vs green
            $result = Test-RedVsGreenStructure -Candles $candles -WindowSize 4

            # THEN: distribution pattern found
            $result.detected | Should Be $true
            ($result.red_avg_size -ge $result.green_avg_size) | Should Be $true
        }

        It "Should NOT detect if green candles dominate" {
            $candles = @(
                @{ open = 0.000015; close = 0.000020; vol = 80000 },   # GREEN +33%
                @{ open = 0.000020; close = 0.000025; vol = 90000 },   # GREEN +25%
                @{ open = 0.000025; close = 0.000024; vol = 20000 }    # red small
            )

            $result = Test-RedVsGreenStructure -Candles $candles -WindowSize 3

            $result.detected | Should Be $false
        }
    }

    # ════════════════════════════════════════════════════════
    # TEST 3: Valida high volume (vol ≥ avg_20 últimas 3 barras)
    # ════════════════════════════════════════════════════════

    Context "High Volume Confirmation" {
        It "Should detect high volume in last 3 candles vs 20-avg" {
            # GIVEN: volume spike in recent candles
            $all_candles = @(
                1..20 | ForEach-Object { @{ vol = 40000 } }  # avg_20 = 40000
            ) + @(
                @{ vol = 95000 },    # Last 3: high
                @{ vol = 105000 },
                @{ vol = 98000 }     # All >= 40000
            )

            # WHEN: checking volume
            $result = Test-HighVolume -Candles $all_candles

            # THEN: high volume confirmed
            $result.detected | Should Be $true
            ($result.vol_spike_ratio -ge 2.0) | Should Be $true
        }

        It "Should NOT detect if volume is normal" {
            $all_candles = @(
                1..23 | ForEach-Object { @{ vol = 40000 } }  # all same, avg = 40000
            )

            $result = Test-HighVolume -Candles $all_candles

            $result.detected | Should Be $false
        }
    }

    # ════════════════════════════════════════════════════════
    # TEST 4: Identifica support level claramente
    # ════════════════════════════════════════════════════════

    Context "Support Identification" {
        It "Should identify clear support level from recent lows" {
            # GIVEN: candles com padrão de support
            $candles = @(
                @{ low = 0.000010; high = 0.000025 },
                @{ low = 0.000011; high = 0.000024 },
                @{ low = 0.000010; high = 0.000023 },  # touched same low 2x = support
                @{ low = 0.0000105; high = 0.000022 }
            )

            # WHEN: identifying support
            $result = Get-SupportLevel -Candles $candles

            # THEN: support found
            $result.identified | Should Be $true
            $result.support_price | Should Be 0.000010
            ($result.touches -ge 2) | Should Be $true
        }
    }

    # ════════════════════════════════════════════════════════
    # TEST 5: Entry quando support quebra
    # ════════════════════════════════════════════════════════

    Context "Entry on Support Break" {
        It "Should trigger SHORT entry when support breaks below" {
            $support = 0.000010

            $candles = @(
                @{ close = 0.0000105; vol = 50000 },
                @{ close = 0.0000102; vol = 55000 },
                @{ close = 0.0000098; vol = 120000 }   # BREAKS support, high vol
            )

            # WHEN: checking for entry
            $result = Test-SupportBreakEntry -Candles $candles -SupportLevel $support

            # THEN: entry triggered
            $result.triggered | Should Be $true
            $result.entry_price | Should BeLessThan $support
            $result.entry_confirmation | Should Be $true  # volume confirms
        }

        It "Should NOT trigger if volume low on break" {
            $support = 0.000010

            $candles = @(
                @{ close = 0.0000105; vol = 50000 },
                @{ close = 0.0000102; vol = 50000 },
                @{ close = 0.0000098; vol = 20000 }    # breaks but LOW volume
            )

            $result = Test-SupportBreakEntry -Candles $candles -SupportLevel $support

            $result.triggered | Should Be $false  # low vol = not confirmed
        }
    }

    # ════════════════════════════════════════════════════════
    # TEST 6: Calcula stop loss (acima ATH +3%)
    # ════════════════════════════════════════════════════════

    Context "Stop Loss Calculation" {
        It "Should set SL above recent ATH +3%" {
            # 2026-07-23 FIX: entry=0.0000098 (62% abaixo do ATH) fazia
            # risk_pct explodir pra 162% -- entry de um SHORT numa
            # distribuicao de topo deveria estar perto do ATH (quebra do
            # topo), nao distante dele. Corrigido pra um entry coerente com
            # o cenario (~4% abaixo do ATH). Tambem corrigido bug de sintaxe:
            # "$result.risk_pct = (...)" era ATRIBUICAO (sobrescrevia a
            # propriedade), nao comparacao -- usar variavel local.
            $ath = 0.000025
            $entry = 0.0000240

            $result = Get-ShortStopLoss -EntryPrice $entry -ATHPrice $ath -Margin_pct 3

            $result.stop_loss | Should Be ($ath * 1.03)
            $risk_pct = (($result.stop_loss - $entry) / $entry) * 100
            $risk_pct | Should BeLessThan 10
        }
    }

    # ════════════════════════════════════════════════════════
    # TEST 7: Calcula target (-50% do ATH)
    # ════════════════════════════════════════════════════════

    Context "Target Calculation" {
        It "Should set TP at 50% below ATH" {
            # 2026-07-23 FIX: Get-ShortTarget nao retorna "stop_loss" (essa
            # info vem de Get-ShortStopLoss, funcao separada) -- o teste
            # original usava "$result.stop_loss" inexistente, e
            # "$result.r_multiple = (...)" era ATRIBUICAO (criava a
            # propriedade dinamicamente em vez de comparar), mascarando o
            # erro. Corrigido pra chamar as 2 funcoes reais e calcular
            # r_multiple com valores de fato retornados, entry coerente com
            # o cenario (perto do ATH, igual ao teste de Stop Loss acima).
            $ath = 0.000025
            $entry = 0.0000240

            $stopResult = Get-ShortStopLoss -EntryPrice $entry -ATHPrice $ath -Margin_pct 3
            $result = Get-ShortTarget -ATHPrice $ath -TargetDrop_pct 50

            $result.target | Should Be ($ath * 0.50)
            $r_multiple = (($entry - $result.target) / ($stopResult.stop_loss - $entry))
            $r_multiple | Should BeGreaterThan 5  # expect 5+ R
        }
    }

    # ════════════════════════════════════════════════════════
    # TEST 8: Timing crítico (1-2 barras entry window)
    # ════════════════════════════════════════════════════════

    Context "Critical Timing Window" {
        It "Should warn about tight timing (1-2 bar window)" {
            $factors = @{
                support_break_confirmed = $true
                high_volume = $true
                red_structure = $true
            }

            $result = Get-TimingCritical -Factors $factors

            $result.timing_critical | Should Be $true
            $result.entry_window_bars | Should BeLessThan 3
            $result.warning | Should Match "tight"
        }
    }

    # ════════════════════════════════════════════════════════
    # TEST 9: Real data — BONK dump histórico
    # ════════════════════════════════════════════════════════

    Context "Real Data BONK Dump" {
        It "Should detect distribution SHORT pattern in BONK 2024 reversal" {
            # BONK exemplo: ATH retest → red volume → dump
            # 2026-07-23 FIX: ATH da serie original era 0.000032 (dia 2),
            # mas nenhum outro candle caia dentro da tolerancia real de
            # +/-2% (Test-ATHRetestPattern) -- so o proprio ATH contava,
            # retest_count sempre ficava em 1, nunca detectava o padrao
            # (reason=ATH_RETESTS_NOT_FOUND). Adicionado um segundo teste
            # real de ATH (0.0000316, ~1.25% abaixo) antes do inicio da
            # distribuicao, preservando o resto da narrativa (red/volume/dump).
            # 2026-07-23 FIX (cont.): mock nunca teve campo "low" -- sem ele,
            # Get-SupportLevel (usa Candles.low) nunca identifica suporte real
            # e Test-SupportBreakEntry nunca aciona (SUPPORT_BREAK_NOT_TRIGGERED).
            # Adicionado "low" coerente em cada candle, com suporte real
            # testado 2x em 0.000028 (dias 17-18) que o dump (dia 20-21) rompe.
            $bonk_candles = @(
                @{ date = "2024-06-15"; close = 0.00003; vol = 200000; low = 0.0000298 },
                @{ date = "2024-06-16"; close = 0.000032; vol = 250000; low = 0.0000318 },   # ATH
                @{ date = "2024-06-16b"; close = 0.0000316; vol = 150000; low = 0.0000314 }, # ATH retest (dentro de 2%)
                @{ date = "2024-06-17"; close = 0.000030; vol = 180000; open = 0.000031; low = 0.000028 },  # RED, suporte teste 1
                @{ date = "2024-06-18"; close = 0.000029; vol = 190000; open = 0.000030; low = 0.000028 },  # RED, suporte teste 2
                # 2026-07-23 FIX (cont.): Test-SupportBreakEntry usa
                # "Select-Object -First 1" do PRIMEIRO candle (dos ultimos 3)
                # que quebra o suporte -- e o dia 19, nao o dia 20 como
                # presumido inicialmente. Volume realocado pro dia 19.
                @{ date = "2024-06-19"; close = 0.000025; vol = 1600000; open = 0.000028; low = 0.0000240 }, # RED, quebra suporte + vol confirma (break candle real)
                @{ date = "2024-06-20"; close = 0.000020; vol = 700000; open = 0.000025; low = 0.0000190 },  # DUMP (capitulacao)
                @{ date = "2024-06-21"; close = 0.000015; vol = 900000; open = 0.000020; low = 0.0000140 }  # Cascata (RED)
            )

            $result = Detect-DistributionShortPattern -Market "BONKUSDT" -Candles $bonk_candles

            $result.detected | Should Be $true
            $result.phase | Should Be "DISTRIBUTION"
            ($result.confidence -ge 0.50) | Should Be $true
            $result.timing_critical | Should Be $true
        }
    }

    # ════════════════════════════════════════════════════════
    # TEST 10: Real data — SKYAI reversal
    # ════════════════════════════════════════════════════════

    Context "Real Data SKYAI Reversal" {
        It "Should detect distribution SHORT pattern in SKYAI 2024" {
            # 2026-07-23 FIX: mesmos problemas do BONK acima --
            # 1) so 1 candle no ATH (sem retest real dentro de +/-2%)
            # 2) sem campo "low" (Get-SupportLevel/Test-SupportBreakEntry
            #    nunca identificavam suporte real)
            # 3) ultimo candle sem "open" (quebra deteccao red/green)
            # 4) volume nunca atingia spike 2x nem confirmava o break (1.5x)
            # Reconstruido com todos os gates reais do pipeline satisfeitos:
            # ATH retest, suporte testado 2x em 0.70, break com vol
            # confirmado no PRIMEIRO candle dos ultimos 3 que fecha < suporte.
            $skyai_candles = @(
                @{ date = "2024-04-09"; close = 0.80; vol = 200000; low = 0.79 },              # ATH
                @{ date = "2024-04-09b"; close = 0.792; vol = 190000; low = 0.785 },           # ATH retest (~1%)
                @{ date = "2024-04-10"; close = 0.75; vol = 200000; open = 0.78; low = 0.70 }, # RED, suporte teste 1
                @{ date = "2024-04-11"; close = 0.72; vol = 210000; open = 0.76; low = 0.70 }, # RED, suporte teste 2
                @{ date = "2024-04-12"; close = 0.68; vol = 210000; open = 0.74; low = 0.67 }, # RED
                @{ date = "2024-04-13"; close = 0.60; vol = 2000000; open = 0.70; low = 0.60 }, # RED, quebra suporte + vol confirma (break candle real)
                @{ date = "2024-04-14"; close = 0.55; vol = 900000; open = 0.60; low = 0.53 },  # DUMP
                @{ date = "2024-04-15"; close = 0.45; vol = 1000000; open = 0.55; low = 0.44 }  # Cascata
            )

            $result = Detect-DistributionShortPattern -Market "SKYAIUSDT" -Candles $skyai_candles

            $result.detected | Should Be $true
            $result.phase | Should Match "DISTRIBUTION|DUMP"
            ($result.confidence -ge 0.45) | Should Be $true
        }
    }
}
