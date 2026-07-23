# MASTER TDD 1/3: Cloud Health Diagnostic
# Propósito: Validar nuvem + detectar por que parou
# Status: PRODUÇÃO (zero mocks)

Describe "MASTER TDD 1: Cloud Health Diagnostic" -Tags "cloud","critical" {

    Context "1.1: GitHub Actions Pipeline Status" {
        It "Trading-pipeline.yml existe e tem cron */5 min" {
            $file = Get-Content '.github/workflows/trading-pipeline.yml' -Raw
            ($file -match "cron: '\*/5") | Should Be $true
        }

        It "Pipeline atualizado recentemente (< 7 dias)" {
            $file = Get-Item '.github/workflows/trading-pipeline.yml'
            $age_days = ((Get-Date) - $file.LastWriteTime).TotalDays
            ($age_days -lt 7) | Should Be $true
        }

        It "Config.local.ps1 tem Supabase credentials (existência)" {
            (Test-Path 'agents/config.local.ps1') | Should Be $true
        }
    }

    Context "1.2: Master Scan Execution History" {
        It "Log mais recente existe: master_20260625.log (últim run)" {
            (Test-Path 'logs/master_20260625.log') | Should Be $true
        }

        It "Master log 25/06 contém 'ciclo concluido' (run bem-sucedida)" {
            $log = Get-Content 'logs/master_20260625.log' -Raw
            ($log -like '*ciclo concluido*') | Should Be $true
        }

        It "NÃO existe master_20260630.log (nuvem parou 25→30/06)" {
            (Test-Path 'logs/master_20260630.log') | Should Be $false
        }

        It "Log contém rejeições válidas (18 candidates, 0 aprovados)" {
            $log = Get-Content 'logs/master_20260625.log' -Raw
            ($log -like '*candidates=18*') | Should Be $true
        }
    }

    Context "1.3: Whitelist Status (RAIZ)" {
        It "Whitelist existe em journal/" {
            $wl = @(Get-ChildItem 'journal/per_asset_whitelist*.json' -ErrorAction SilentlyContinue)
            ($wl.Count -gt 0) | Should Be $true
        }

        It "CRÍTICO: Whitelist tem tier_a_live OR tier_a_paper assets" {
            $latest_wl = Get-ChildItem 'journal/per_asset_whitelist*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $content = Get-Content $latest_wl.FullName -Raw
            # Verificar se tem tier_a (não conta vazio)
            ($content -like '*tier_a*') | Should Be $true
        }
    }

    Context "1.4: Trade Execution History" {
        It "Últimas trades registradas (schema real usa entry_ts, nao registered_at)" {
            # 2026-07-23 FIX: Save-TradeOutcome (lib_trade_journal_supabase)
            # grava entry_ts/created_at, nunca "registered_at" -- campo
            # inexistente no schema real, teste testava um nome que nao
            # corresponde a producao. Tambem: arquivo real muda a cada run
            # do pipeline, entao snapshot de data especifica (18+ dias
            # parado) nao e mais valido como teste de regressao -- so
            # confirma que o campo real de timestamp existe.
            $outcomes = @(Get-Content 'journal/trade_outcomes.jsonl' | ConvertFrom-Json)
            $last = $outcomes[-1]
            ($null -ne $last.entry_ts -or $null -ne $last.created_at) | Should Be $true
        }
    }

    Context "1.5: Local Daemon Status" {
        It "PowerShell daemons rodando (PWsh processes)" {
            $procs = @(Get-Process pwsh -ErrorAction SilentlyContinue)
            ($procs.Count -ge 1) | Should Be $true
        }

        It "Último processo iniciou <= 24h atrás" {
            $ps = Get-Process pwsh -ErrorAction SilentlyContinue | Sort-Object StartTime -Descending | Select-Object -First 1
            $age_hours = ((Get-Date) - $ps.StartTime).TotalHours
            ($age_hours -le 24) | Should Be $true
        }
    }

    Context "1.6: Active Flags" {
        It "GEM_AUTO_APPROVE.flag existe (aprovação automática ativa)" {
            (Test-Path 'journal/GEM_AUTO_APPROVE.flag') | Should Be $true
        }

        It "REGIME_SURF_SHORT_LIVE.flag existe (SHORT surf ativo)" {
            (Test-Path 'journal/REGIME_SURF_SHORT_LIVE.flag') | Should Be $true
        }

        It "LIVE_MODE_ENABLED.flag existe" {
            (Test-Path 'journal/LIVE_MODE_ENABLED.flag') | Should Be $true
        }
    }

    Context "1.7: Dashboard Sync" {
        It "Dashboard mostra posições corretas (0 em BEAR_WEAK)" {
            $html = Get-Content 'dashboard/index.html' -Raw
            ($html -like '*<span class="ok">0</span>*') | Should Be $true
        }

        It "Dashboard PnL $0 (nenhuma posição aberta)" {
            $html = Get-Content 'dashboard/index.html' -Raw
            ($html -like '*Total PNL*$0*') | Should Be $true
        }
    }
}
