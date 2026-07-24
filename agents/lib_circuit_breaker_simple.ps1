# lib_circuit_breaker_simple.ps1 — Circuit breaker -2% daily (SIMPLIFICADO)
#
# 2026-07-16 FIX (auditoria agent a395f05e): Get-DailyPnL lia SO
# journal/trade_outcomes.jsonl LOCAL. journal/*.jsonl e gitignored e cada job
# GitHub Actions roda em runner efemero (checkout limpo) -- o arquivo nasce
# vazio a cada execucao, entao Test-CircuitBreakerTriggered SEMPRE via
# dailyPnL=0 no inicio do ciclo, mesmo que o dia real ja tenha perdido -10%.
# Fail-open silencioso: parecia ter protecao (log, mensagem configurada) mas
# na pratica o gate quase nunca disparava em producao cloud. Mesma classe de
# bug ja documentada/corrigida em outras partes do projeto (trailing_state,
# capital_context) mas nao nesta lib. Fix: consulta Supabase primeiro via
# Get-StateRecords (mesmo padrao ja usado por lib_trade_journal_supabase.ps1),
# cai pro arquivo local so como ultimo recurso -- e loga quando isso acontece
# (degradacao visivel, nao mais silenciosa).

function Get-DailyPnL {
    param([string]$JournalDir = $global:JOURNAL_DIR)
    if (-not $JournalDir) { $JournalDir = (Join-Path (Split-Path $PSScriptRoot) "journal") }

    $today = (Get-Date).Date
    $pnl = 0.0

    # === Fonte primaria: Supabase trade_outcomes (persiste entre jobs efemeros) ===
    if (Get-Command Get-StateRecords -ErrorAction SilentlyContinue) {
        try {
            $records = @(Get-StateRecords -Table "trade_outcomes" -Filter @{ status = "closed" } -ErrorAction Stop)
            if ($records.Count -gt 0) {
                foreach ($obj in $records) {
                    $exitRaw = if ($obj.exit_date) { $obj.exit_date } elseif ($obj.updated_at) { $obj.updated_at } else { $null }
                    if (-not $exitRaw) { continue }
                    try {
                        # 2026-07-23 FIX: Invoke-RestMethod (usado por
                        # _Supabase-Get) tambem auto-promove strings ISO
                        # 8601 pra [datetime] (mesmo parser JSON do
                        # ConvertFrom-Json) -- [string]$exitRaw coagia de
                        # volta usando o formato do locale, sem timezone,
                        # quebrando o Parse. Ver lib_tori_proximity.ps1.
                        $exitDate = if ($exitRaw -is [datetime]) { $exitRaw.Date } else { ([datetime]::Parse([string]$exitRaw)).Date }
                        if ($exitDate -eq $today) {
                            $pnlField = if ($null -ne $obj.pnl_realized) { $obj.pnl_realized } else { $obj.pnl_usd }
                            $pnl += [double]$pnlField
                        }
                    } catch { }
                }
                return $pnl
            }
        } catch {
            Write-Host "[circuit_breaker] AVISO: Supabase trade_outcomes indisponivel ($($_.Exception.Message)) -- caindo pro arquivo local (pode subestimar perdas em runner efemero)" -ForegroundColor Yellow
        }
    }

    # === Fallback: arquivo local (so confiavel dentro do MESMO processo/job) ===
    $outcomeFile = Join-Path $JournalDir "trade_outcomes.jsonl"
    if (-not (Test-Path $outcomeFile)) { return 0.0 }

    Get-Content $outcomeFile | Where-Object { $_ -match '^\{' } | ForEach-Object {
        try {
            $obj = ConvertFrom-Json $_
            $exitDate = [datetime]::ParseExact($obj.exit_date, "yyyy-MM-dd", $null).Date
            if ($exitDate -eq $today) {
                $pnl += [double]$obj.pnl_usd
            }
        } catch { }
    }
    return $pnl
}

function Test-CircuitBreakerTriggered {
    param([double]$Capital = 3645.0, [double]$DailyLossThreshold = -0.02)
    $dailyPnL = Get-DailyPnL
    $threshold = $Capital * $DailyLossThreshold
    return ($dailyPnL -lt $threshold)
}

function Reset-CircuitBreaker {
    $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }
    $flagPath = Join-Path $journalDir "CIRCUIT_BREAKER_PAUSED.flag"
    Remove-Item $flagPath -ErrorAction SilentlyContinue
}

function Set-CircuitBreakerPause {
    $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }
    if (-not (Test-Path $journalDir)) { mkdir $journalDir | Out-Null }
    $flagPath = Join-Path $journalDir "CIRCUIT_BREAKER_PAUSED.flag"
    Add-Content -Path $flagPath -Value "paused $(Get-Date)" -Encoding UTF8
}
