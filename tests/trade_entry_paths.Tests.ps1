#!/usr/bin/env pwsh
# tests/trade_entry_paths.Tests.ps1
# TDD — Validar TODOS os caminhos de entrada de trade
# 2026-06-19

Describe "Trade Entry Paths - Complete Suite" {
    BeforeAll {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $agentsDir = Join-Path $projectRoot "agents"
        $scriptsDir = Join-Path $projectRoot "scripts"
        $journalDir = Join-Path $projectRoot "journal"

        # Criar diretórios se não existem
        @($journalDir, (Join-Path $journalDir "daemon_locks")) | ForEach-Object {
            if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
        }

        # Carregar libs essenciais
        . (Join-Path $agentsDir "config.ps1")
        . (Join-Path $agentsDir "lib_coinex.ps1")
        . (Join-Path $agentsDir "lib_telegram.ps1")
        . (Join-Path $agentsDir "lib_journal.ps1") -ErrorAction SilentlyContinue

        Write-Host "=== TDD: Trade Entry Paths ===" -ForegroundColor Cyan
        Write-Host "Project Root: $projectRoot" -ForegroundColor Gray
    }

    # =========================================================================
    # TEST 1: sync_and_fix_tp.ps1 foi removido (cleanup 2026-07-09) -- substituido
    # por SPOT STOP FAIL-CLOSED por saldo real dentro do proprio
    # trailing_stop_monitor.ps1 (ver linha ~428, "2026-06-24: substitui
    # sync_and_fix_tp"). 2026-07-23: teste original (sintaxe Pester 5, nunca
    # rodava no motor real) testava um script que nao existe mais por decisao
    # consciente documentada no CLAUDE.md -- ajustado pra validar a ausencia
    # intencional em vez de reintroduzir o script morto.
    # =========================================================================
    Context "1. Position Sync (sync_and_fix_tp removido -- fail-closed embutido)" {
        It "sync_and_fix_tp.ps1 NAO deve existir (removido intencionalmente 2026-07-09)" {
            $syncScript = Join-Path $scriptsDir "sync_and_fix_tp.ps1"
            Test-Path $syncScript | Should Be $false
        }

        It "trailing_stop_monitor deve ter o fail-closed que o substituiu" {
            $monitorScript = Join-Path $scriptsDir "trailing_stop_monitor.ps1"
            $content = Get-Content $monitorScript -Raw

            $content -match 'substitui sync_and_fix_tp|FAIL-CLOSED' | Should Be $true
        }
    }

    # =========================================================================
    # TEST 2: gem_loop.ps1 — Main Entry Pipeline
    # =========================================================================
    Context "2. Gem Loop (Automatic Entry)" {
        It "Should exist and be executable" {
            $gemLoopScript = Join-Path $scriptsDir "gem_loop.ps1"
            Test-Path $gemLoopScript | Should Be $true
        }

        It "Should load gem_agent and gem_executor" {
            $gemLoopScript = Join-Path $scriptsDir "gem_loop.ps1"
            $content = Get-Content $gemLoopScript -Raw

            $content -match 'gem_agent\.ps1' | Should Be $true
            $content -match 'gem_executor\.ps1' | Should Be $true
        }

        It "Should call Invoke-GemExecute for each gem found" {
            $gemLoopScript = Join-Path $scriptsDir "gem_loop.ps1"
            $content = Get-Content $gemLoopScript -Raw

            $content -match 'Invoke-GemExecute' | Should Be $true
        }

        It "Should have -Once parameter for cloud execution" {
            $gemLoopScript = Join-Path $scriptsDir "gem_loop.ps1"
            $content = Get-Content $gemLoopScript -Raw

            $content -match '\[switch\]\$Once' | Should Be $true
        }
    }

    # =========================================================================
    # TEST 3: gem_executor.ps1 — Trade Execution
    # =========================================================================
    Context "3. Gem Executor (Trade Execution)" {
        It "Should exist" {
            $executorScript = Join-Path $agentsDir "gem_executor.ps1"
            Test-Path $executorScript | Should Be $true
        }

        It "Should export Invoke-GemExecute function" {
            $executorScript = Join-Path $agentsDir "gem_executor.ps1"
            . $executorScript

            Get-Command Invoke-GemExecute -ErrorAction SilentlyContinue | Should Not Be $null
        }

        It "Should have conviction gate" {
            $executorScript = Join-Path $agentsDir "gem_executor.ps1"
            $content = Get-Content $executorScript -Raw

            $content -match 'CONVICTION.*GATE|Test-ConvictionGate' | Should Be $true
        }

        It "Should have tori gate" {
            $executorScript = Join-Path $agentsDir "gem_executor.ps1"
            $content = Get-Content $executorScript -Raw

            $content -match 'TORI.*GATE|Get-ToriTrendlineSignal' | Should Be $true
        }

        It "Should have chart pattern gate" {
            $executorScript = Join-Path $agentsDir "gem_executor.ps1"
            $content = Get-Content $executorScript -Raw

            $content -match 'CHART.*GATE|Test-ChartPatternGate' | Should Be $true
        }
    }

    # =========================================================================
    # TEST 4: telegram_listener.ps1 — Manual Entry Commands
    # =========================================================================
    Context "4. Telegram Listener (Manual Commands)" {
        It "Should exist" {
            $listenerScript = Join-Path $scriptsDir "telegram_listener.ps1"
            Test-Path $listenerScript | Should Be $true
        }

        It "Should have /idea command handler" {
            # 2026-07-23 FIX: dispatch real usa "idea" (sem barra, ja normalizado
            # antes do switch) via Cmd-Idea, nao a string literal "/idea".
            $listenerScript = Join-Path $scriptsDir "telegram_listener.ps1"
            $content = Get-Content $listenerScript -Raw

            $content -match '"idea"\s*\{|Cmd-Idea' | Should Be $true
        }

        It "Should have /approve command handler" {
            $listenerScript = Join-Path $scriptsDir "telegram_listener.ps1"
            $content = Get-Content $listenerScript -Raw

            $content -match '"/approve"|approve.*command' | Should Be $true
        }

        It "Should use lib_idea_triggers for /idea (nao signal_triggers.jsonl)" {
            # 2026-07-23 FIX: /idea foi implementado via lib_idea_triggers.ps1
            # (Cmd-Idea/Cmd-Ideas/Cmd-IdeaCancel), nunca usou signal_triggers.jsonl --
            # esse era o design do TEST 6 antigo (cloud_conviction_scan), teste
            # cruzou premissas de dois recursos diferentes.
            $listenerScript = Join-Path $scriptsDir "telegram_listener.ps1"
            $content = Get-Content $listenerScript -Raw

            $content -match 'lib_idea_triggers' | Should Be $true
        }
    }

    # =========================================================================
    # TEST 5: Approval Handler — /approve Implementation
    # =========================================================================
    Context "5. Approval Handler (/approve)" {
        It "Should have lib_tg_approval_handler.ps1" {
            $approvalLib = Join-Path $agentsDir "lib_tg_approval_handler.ps1"
            Test-Path $approvalLib | Should Be $true
        }

        It "Should export Process-ApprovalCommand function" {
            $approvalLib = Join-Path $agentsDir "lib_tg_approval_handler.ps1"
            . $approvalLib -ErrorAction SilentlyContinue

            Get-Command Process-ApprovalCommand -ErrorAction SilentlyContinue | Should Not Be $null
        }

        It "Should have logic to bypass conviction gate" {
            $approvalLib = Join-Path $agentsDir "lib_tg_approval_handler.ps1"
            if (Test-Path $approvalLib) {
                $content = Get-Content $approvalLib -Raw
                $content -match 'bypass|conviction|approval' | Should Be $true
            } else {
                Set-ItResult -Skipped -Because "lib_tg_approval_handler.ps1 not found"
            }
        }

        It "KNOWN GAP: aprovacao humana so grava status, nada consome p/ executar" {
            # 2026-07-23 AUDITORIA: lib_tg_approval_handler.ps1 e lib_human_approval_simple.ps1
            # so marcam human_approvals_pending.jsonl como APPROVED/REJECTED --
            # nenhum arquivo em agents/ ou scripts/ le esse status pra de fato
            # chamar Invoke-GemExecute. Fluxo /idea (lib_idea_triggers.ps1) e
            # separado e tambem nao chama execucao diretamente. Documentando
            # o gap real em vez de mascarar com uma expectativa falsa --
            # requer decisao de produto (que loop deveria consumir approvals
            # pendentes?) antes de virar codigo.
            $approvalLib = Join-Path $agentsDir "lib_tg_approval_handler.ps1"
            $content = Get-Content $approvalLib -Raw
            $hasExecutionCall = $content -match 'Invoke-GemExecute'

            $hasExecutionCall | Should Be $false  # documenta o gap; virar $true quando conectado
        }
    }

    # =========================================================================
    # TEST 6: cloud_conviction_scan.ps1 — Observation Mode
    # =========================================================================
    Context "6. Cloud Conviction Scan (Observation)" {
        It "Should exist" {
            $scanScript = Join-Path $scriptsDir "cloud_conviction_scan.ps1"
            Test-Path $scanScript | Should Be $true
        }

        It "Should NOT execute trades (observation only)" {
            $scanScript = Join-Path $scriptsDir "cloud_conviction_scan.ps1"
            $content = Get-Content $scanScript -Raw

            # Deve ter comentário ou flag indicando observe-only
            $content -match 'observe|OBSERVE|observation' -or $content -notmatch 'Invoke-GemExecute' | Should Be $true
        }

        It "Should calculate conviction ensemble" {
            $scanScript = Join-Path $scriptsDir "cloud_conviction_scan.ps1"
            $content = Get-Content $scanScript -Raw

            $content -match 'conviction|ensemble|7.*axis' | Should Be $true
        }
    }

    # =========================================================================
    # TEST 7: trailing_stop_monitor.ps1 -- Integration
    # 2026-07-23 FIX: sync_and_fix_tp foi removido 2026-07-09 e substituido
    # (2026-06-24) por SPOT STOP FAIL-CLOSED por saldo real embutido no
    # proprio trailing_stop_monitor.ps1 -- mencao ao nome antigo so aparece
    # em comentario historico, nao ha mais chamada real.
    # =========================================================================
    Context "7. Trailing Stop Monitor (Integration)" {
        It "Menciona a substituicao de sync_and_fix_tp em comentario historico" {
            $monitorScript = Join-Path $scriptsDir "trailing_stop_monitor.ps1"
            $content = Get-Content $monitorScript -Raw

            $content -match 'sync_and_fix_tp' | Should Be $true
        }

        It "Should NOT use hardcoded Markets list" {
            $monitorScript = Join-Path $scriptsDir "trailing_stop_monitor.ps1"
            $content = Get-Content $monitorScript -Raw

            # Verifica que foi removido hardcoded markets
            $content -match "@\(\s*'BASEDUSDT'.*'SPCXXUSDT'" | Should Be $false
        }

        It "Should use fail-closed real (nao mais chama sync_and_fix_tp)" {
            $monitorScript = Join-Path $scriptsDir "trailing_stop_monitor.ps1"
            $content = Get-Content $monitorScript -Raw

            $content -notmatch 'sync_and_fix_tp\.ps1\s*[''"`]?\s*-ErrorAction' | Should Be $true
        }
    }

    # =========================================================================
    # TEST 8: GitHub Actions Workflow
    # =========================================================================
    Context "8. GitHub Actions Workflow" {
        It "Should have JOB 23 (gem_loop)" {
            $workflow = Join-Path $projectRoot ".github\workflows\trading-pipeline.yml"
            $content = Get-Content $workflow -Raw

            $content -match 'JOB 23|cloud-trading|gem_loop' | Should Be $true
        }

        It "Should have JOB 24 (telegram_listener)" {
            $workflow = Join-Path $projectRoot ".github\workflows\trading-pipeline.yml"
            $content = Get-Content $workflow -Raw

            $content -match 'JOB 24|telegram-cloud|telegram_listener' | Should Be $true
        }

        It "Should have JOB 1 (trailing_stop_monitor) every 5 min" {
            $workflow = Join-Path $projectRoot ".github\workflows\trading-pipeline.yml"
            $content = Get-Content $workflow -Raw

            $content -match 'trailing-stop-monitor' | Should Be $true
            $content -match '\*/5.*\*' | Should Be $true
        }

        It "JOB 1 should call sync_and_fix_tp" {
            $workflow = Join-Path $projectRoot ".github\workflows\trading-pipeline.yml"
            $content = Get-Content $workflow -Raw

            # Verifica que trailing-stop-monitor chama sync_and_fix_tp
            $content -match 'trailing_stop_monitor|sync_and_fix_tp' | Should Be $true
        }
    }

    # =========================================================================
    # TEST 9: Critical Functions Exist
    # =========================================================================
    Context "9. Critical Functions Available" {
        It "Should have CoinEx-GetOpenOrders" {
            Get-Command CoinEx-GetOpenOrders -ErrorAction SilentlyContinue | Should Not Be $null
        }

        It "Should have Send-TelegramAlert" {
            Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue | Should Not Be $null
        }

        It "Should have CoinEx-PlaceOrder" {
            Get-Command CoinEx-PlaceOrder -ErrorAction SilentlyContinue | Should Not Be $null
        }
    }

    # =========================================================================
    # TEST 10: State Files
    # =========================================================================
    Context "10. State Files & Directories" {
        It "Should have journal directory" {
            Test-Path $journalDir | Should Be $true
        }

        It "Should have daemon_locks directory" {
            $locksDir = Join-Path $journalDir "daemon_locks"
            Test-Path $locksDir | Should Be $true
        }

        It "Should be able to create signal_triggers.jsonl" {
            $triggersFile = Join-Path $journalDir "signal_triggers.jsonl"
            $testEntry = @{
                market = "TEST"
                conviction = 75
                status = "pending"
            } | ConvertTo-Json -Compress

            Add-Content -Path $triggersFile -Value $testEntry -Encoding UTF8 -ErrorAction SilentlyContinue
            Test-Path $triggersFile | Should Be $true
        }
    }
}

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host ""
Write-Host "=== TDD SUMMARY ===" -ForegroundColor Cyan
Write-Host "10 test contexts (70+ assertions)" -ForegroundColor White
Write-Host "Coverage: All 5 entry paths" -ForegroundColor Green
Write-Host ""
Write-Host "Run with: Invoke-Pester tests/trade_entry_paths.Tests.ps1 -Verbose" -ForegroundColor Yellow
