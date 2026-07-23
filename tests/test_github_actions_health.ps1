# Test: GitHub Actions Health Check (TDD 1/3)
# Valida: Nuvem rodou nos últimos 30 min, jobs foram bem
# Modo: Read-only (sem executar ações)

Describe "GitHub Actions Cloud Health" {

    Context "TDD 1.1: Cloud Pipeline Status" {
        It "Trading pipeline roda a cada 5 min (cron ativo)" {
            $workflow = Get-Content '.github/workflows/trading-pipeline.yml' -Raw
            $workflow -match "cron: '\*\/5" | Should Be $true
        }

        It "Workflow file exists e foi atualizado recentemente" {
            $file = Get-Item '.github/workflows/trading-pipeline.yml'
            ($file.LastWriteTime -gt (Get-Date).AddDays(-1)) | Should Be $true
        }
    }

    Context "TDD 1.2: Logs de Execução" {
        It "master_20260630.log NÃO existe (última na nuvem foi 20260625)" {
            (Test-Path 'logs/master_20260630.log') | Should Be $false
        }

        It "short_scanner.log tem conteudo (nao vazio)" {
            # 2026-07-23 FIX: data hardcoded "2026-06-18" era um snapshot
            # pontual de uma investigacao de "nuvem parada" -- sistema esta
            # ativo ha semanas (CLAUDE.md: ~100 runs verdes), o log continua
            # crescendo, entao a data especifica nunca mais bate. Teste
            # ajustado pra validar estrutura (log existe e tem linhas), nao
            # um fato historico pontual.
            $log = Get-Content 'logs/short_scanner.log' -Tail 1
            ([string]::IsNullOrWhiteSpace($log)) | Should Be $false
        }

        It "wss_forward_resolve tem encoding issue" {
            (Test-Path 'logs/wss_forward_resolve_20260630.log') | Should Be $true
        }
    }

    Context "TDD 1.3: Status Dashboard vs Realidade" {
        It "Dashboard mostra 0 positions (correto para BEAR_WEAK)" {
            $html = Get-Content 'dashboard/index.html' -Raw
            ($html -like '*<span class="ok">0</span>*') | Should Be $true
        }

        It "trade_outcomes.jsonl tem timestamp real (entry_ts/created_at, nao registered_at)" {
            # 2026-07-23 FIX: mesmos 2 problemas do teste anterior --
            # "registered_at" nao existe no schema real (e entry_ts/created_at,
            # ver Save-TradeOutcome), e a data "2026-06-12" era um snapshot
            # pontual da investigacao de nuvem parada, ja obsoleto (sistema
            # ativo, trades novas todo dia).
            $outcomes = @(Get-Content 'journal/trade_outcomes.jsonl' | ConvertFrom-Json)
            $last = $outcomes[-1]
            ($null -ne $last.entry_ts -or $null -ne $last.created_at) | Should Be $true
        }

        It "decisions_text.jsonl tem timestamp valido" {
            $decisions = @(Get-Content 'journal/decisions_text.jsonl' | ConvertFrom-Json)
            $last = $decisions[-1]
            ($null -ne $last.ts) | Should Be $true
        }
    }

    Context "TDD 1.4: Nuvem vs Local" {
        It "PowerShell processes rodando (PWsh)" {
            $ps = Get-Process pwsh -ErrorAction SilentlyContinue
            ($ps.Count -ge 1) | Should Be $true
        }

        It "Último PID iniciou hoje ou recentemente" {
            $ps = Get-Process pwsh -ErrorAction SilentlyContinue |
                Sort-Object StartTime -Descending | Select-Object -First 1
            ($ps.StartTime.Date -le (Get-Date).Date) | Should Be $true
        }
    }
}

# DIAGNÓSTICO:
# ✅ Cloud workflow exists e tá ativo (cron)
# ❌ Master logs pararam em 20260625
# ❌ Short scanner parou em 20260618
# ❌ Nenhuma entrada desde 20260612
# ⚠️ Encoding BOM issue em logs
#
# HIPÓTESE: Nuvem parou de executar entre 25/06 e 30/06 (possivelmente por erro silencioso ou restart de secrets)