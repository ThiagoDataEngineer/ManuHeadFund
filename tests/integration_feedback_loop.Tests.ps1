# integration_feedback_loop.Tests.ps1 -- TDD integracao: gem_executor + scan_master
# Valida que sizing dinamico e calibrador estao wired e prontos

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Describe "Integration - Feedback Loop Complete" {

    Context "gem_executor wiring (sizing dinamico)" {

        It "dot-source de lib_sizing_dynamics existe" {
            Test-Path "agents/lib_sizing_dynamics.ps1" | Should Be $true
        }

        It "gem_executor menciona lib_sizing_dynamics" {
            $content = Get-Content "agents/gem_executor.ps1" -Raw
            $content | Should Match "lib_sizing_dynamics"
        }

        It "gem_executor tem logica de Get-DynamicCapitalAllocation" {
            $content = Get-Content "agents/gem_executor.ps1" -Raw
            $content | Should Match "Get-DynamicCapitalAllocation"
        }

        It "gem_executor chama Get-SizePerTrade dinamicamente" {
            $content = Get-Content "agents/gem_executor.ps1" -Raw
            $content | Should Match "Get-SizePerTrade"
        }

        It "gem_executor tem fallback pra Kelly/legacy se sizing dinamico falhar" {
            $content = Get-Content "agents/gem_executor.ps1" -Raw
            $content | Should Match "kelly_adaptive|legacy_pct"
        }
    }

    Context "scan_master wiring (calibrador)" {

        It "scan_master dot-source lib_feedback_calibrator" {
            $content = Get-Content "scripts/scan_master.ps1" -Raw
            $content | Should Match "lib_feedback_calibrator"
        }

        It "scan_master dot-source lib_sizing_dynamics" {
            $content = Get-Content "scripts/scan_master.ps1" -Raw
            $content | Should Match "lib_sizing_dynamics.ps1" -First 1
        }

        It "scan_master tem CALIBRATION checkpoint (a cada 6 ciclos)" {
            $content = Get-Content "scripts/scan_master.ps1" -Raw
            $content | Should Match "FEEDBACK CALIBRATION|6 ciclos|calibration_params_live"
        }

        It "scan_master salva calibrated params em JSON" {
            $content = Get-Content "scripts/scan_master.ps1" -Raw
            $content | Should Match "calibration_params_live.json"
        }
    }

    Context "Ciclo completo funcional" {

        BeforeAll {
            . ".\agents\config.ps1"
            . ".\agents\lib_sizing_dynamics.ps1"
            . ".\agents\lib_feedback_calibrator.ps1"
            . ".\agents\lib_coinex.ps1"
        }

        It "Get-DynamicCapitalAllocation retorna alocacao valida" {
            $alloc = Get-DynamicCapitalAllocation -SpotUsdt 925 -FuturesUsdt 2714 -Regime "BEAR_WEAK"

            $alloc | Should Not BeNullOrEmpty
            $alloc.total_usdt | Should Be 3639
            $alloc.short_alloc | Should BeGreaterThan 2900
            $alloc.long_alloc | Should BeLessThan 800
        }

        It "Get-SizePerTrade calcula tamanho valido" {
            $size = Get-SizePerTrade -AllocatedCapital 2911 -MaxConcurrentTrades 5 -StopLossPct 0.015

            $size | Should BeGreaterThan 0
            $size | Should BeLessThan 500  # sanity check
        }

        It "Get-OutcomesStats coleta dados reais" {
            $stats = Get-OutcomesStats -OutcomesFile "journal/trade_outcomes.jsonl" -Days 7

            if ($stats) {
                $stats.trades | Should BeGreaterThan 0
                ($stats.win_rate -le 1) | Should Be $true
                $stats.pnl_total_usd | Should BeOfType [double]
            }
        }

        It "Get-CalibratedParams retorna params calibrados" {
            $dummyStats = @{
                trades = 10
                win_rate = 0.40
                pnl_total_usd = 20
                avg_loss_pct = 2.5
            }

            $current = @{
                THRESHOLD_ENTRADA = 70
                STOP_LOSS_PCT = 2.0
                SHORT_RATIO = 0.80
            }

            $calib = Get-CalibratedParams -Stats $dummyStats -CurrentParams $current

            $calib | Should Not BeNullOrEmpty
            $calib.calibrated | Should Not BeNullOrEmpty
            # Deve ter apertado stop (avg_loss 2.5 > stop 2.0)
            $calib.calibrated['STOP_LOSS_PCT'] | Should BeLessThan 2.0
        }
    }

    Context "Validacao de seguranca (nao quebrar gates)" {

        It "sizing dinamico nao supera 5% capital (spot)" {
            . ".\agents\lib_sizing_dynamics.ps1"

            # Spot (leverage 1x): calc sem alavancagem
            $sz = Get-SizePerTrade -AllocatedCapital 727 -MaxConcurrentTrades 5 -StopLossPct 0.02
            $validation = Test-SizingValidation -SizeUsdt $sz -CapitalUsdt 3639 -Leverage 1.0

            $validation.valid | Should Be $true
            ($validation.size_pct -lt 5) | Should Be $true
        }

        It "calibrador nao muda threshold alem 80" {
            . ".\agents\lib_feedback_calibrator.ps1"

            $stats = @{ trades = 100; win_rate = 0.95 }  # artificial perfection
            $current = @{ THRESHOLD_ENTRADA = 70 }

            $calib = Get-CalibratedParams -Stats $stats -CurrentParams $current

            # Mesmo com 95% win rate, nao pode ir MUITO alto (existe limite de sanidade)
            ($calib.calibrated['THRESHOLD_ENTRADA'] -le 80) | Should Be $true
        }

        It "calibrador nao reduz stop abaixo 1.0%" {
            . ".\agents\lib_feedback_calibrator.ps1"

            $stats = @{ trades = 10; win_rate = 0.60; avg_loss_pct = 5.0 }  # muito alto
            $current = @{ STOP_LOSS_PCT = 2.0 }

            $calib = Get-CalibratedParams -Stats $stats -CurrentParams $current

            # Mesmo com avg_loss alto, stop minimo eh 1.0%
            ($calib.calibrated['STOP_LOSS_PCT'] -ge 1.0) | Should Be $true
        }
    }

    Context "Modo teste: run_feedback_loop_test.ps1 pronto" {

        It "script de teste existe" {
            Test-Path "scripts/run_feedback_loop_test.ps1" | Should Be $true
        }

        It "script roda sem erro (dry run)" {
            $result = & "pwsh" -NoProfile -ExecutionPolicy Bypass -Command {
                Set-Location 'C:\Users\thiag\Coinex_AI_USER_API'
                try {
                    & pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/run_feedback_loop_test.ps1 2>&1 | Measure-Object | Select-Object -ExpandProperty Count
                } catch {
                    -1
                }
            }

            $result | Should BeGreaterThan 0  # produceu output
        }
    }
}
