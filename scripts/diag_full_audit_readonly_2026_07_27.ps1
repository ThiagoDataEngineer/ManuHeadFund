# diag_full_audit_readonly_2026_07_27.ps1 -- diagnostico ONE-SHOT, so leitura
# Owner pediu avaliacao completa: posicoes abertas/fechadas nas ultimas 24h,
# qualidade das entradas/saidas, se o sistema aplicou "smart decisions" apos
# os fixes de 2026-07-25/26 (beta real, FQS real, momentum dinamico, budget
# do Mentor). Este script consulta a CoinEx REAL (nao journal/logs, que ja
# se provaram nao confiaveis hoje) + Supabase (trade_outcomes, mentor_
# override_log, conviction_observations) pra montar o quadro real.
# NAO envia nenhuma ordem, so leitura.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

Write-Host "=== DIAG FULL AUDIT (READ-ONLY) 2026-07-27 ===" -ForegroundColor Cyan

# ── 1. Posicoes FUTURES abertas (fonte real: CoinEx) ────────────────────────
Write-Host "`n--- FUTURES: posicoes abertas (CoinEx real) ---" -ForegroundColor Yellow
try {
    $futPos = @(CoinEx-GetPendingPositions)
    Write-Host "Total: $($futPos.Count)" -ForegroundColor Green
    foreach ($p in $futPos) {
        Write-Host "  $($p.market) side=$($p.side) amount=$($p.amount) open_price=$($p.open_price) unrealized_pnl=$($p.unrealized_pnl) leverage=$($p.leverage) margin=$($p.margin)"
    }
} catch { Write-Host "ERRO futures positions: $_" -ForegroundColor Red }

# ── 2. SPOT+FUTURES consolidado (via CoinEx-GetOpenOrders) ──────────────────
Write-Host "`n--- SPOT+FUTURES consolidado (CoinEx-GetOpenOrders) ---" -ForegroundColor Yellow
try {
    $allOpen = @(CoinEx-GetOpenOrders)
    Write-Host "Total: $($allOpen.Count)" -ForegroundColor Green
    foreach ($o in $allOpen) {
        Write-Host "  $($o.market) type=$($o.type) entry=$($o.entry) stop=$($o.stop_price) target=$($o.take_profit_price)"
    }
} catch { Write-Host "ERRO open orders: $_" -ForegroundColor Red }

# ── 3. trade_outcomes (Supabase) -- fechamentos reais recentes ──────────────
Write-Host "`n--- trade_outcomes recentes (ultimas 48h) ---" -ForegroundColor Yellow
try {
    $outcomes = @(Get-StateRecords -Table "trade_outcomes")
    $recent = @($outcomes | Where-Object {
        try { ([datetime]$_.ts) -gt (Get-Date).ToUniversalTime().AddHours(-48) } catch { $false }
    } | Sort-Object { try { [datetime]$_.ts } catch { [datetime]::MinValue } })
    Write-Host "Total ultimas 48h: $($recent.Count) (total historico: $($outcomes.Count))" -ForegroundColor Green
    foreach ($t in $recent) {
        Write-Host "  ts=$($t.ts) market=$($t.market) side=$($t.side) pnl_pct=$($t.pnl_percent) pnl_usd=$($t.pnl_usd) source=$($t.source) close_reason=$($t.close_reason)"
    }
} catch { Write-Host "ERRO trade_outcomes: $_" -ForegroundColor Red }

# ── 4. mentor_override_log (Supabase ou local) -- decisoes do Mentor ────────
Write-Host "`n--- Mentor overrides (ultimas 24h) ---" -ForegroundColor Yellow
try {
    $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" }
    $logPath = Join-Path $journalDir "mentor_override_log.jsonl"
    if (Test-Path $logPath) {
        $lines = @(Get-Content $logPath -Encoding UTF8 | ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } | Where-Object { $_ })
        $recent = @($lines | Where-Object { try { ([datetime]$_.ts_utc) -gt (Get-Date).ToUniversalTime().AddHours(-24) } catch { $false } })
        Write-Host "Local jsonl: $($recent.Count) overrides nas ultimas 24h (arquivo efemero do runner -- pode nao refletir todos os ciclos)" -ForegroundColor Green
        foreach ($o in $recent) {
            Write-Host "  ts=$($o.ts_utc) market=$($o.market) gate=$($o.gate_tag) direction=$($o.direction) conf=$($o.mentor_confidence)"
        }
    } else {
        Write-Host "journal/mentor_override_log.jsonl nao existe neste runner (efemero, esperado)" -ForegroundColor Yellow
    }
} catch { Write-Host "ERRO mentor_override_log: $_" -ForegroundColor Red }

# ── 5. conviction_observations (Supabase, criado ontem) -- volume acumulado ─
Write-Host "`n--- conviction_observations acumuladas desde ontem ---" -ForegroundColor Yellow
try {
    $convObs = @(Get-StateRecords -Table "conviction_observations")
    Write-Host "Total: $($convObs.Count)" -ForegroundColor Green
    if ($convObs.Count -gt 0) {
        $byTag = $convObs | Group-Object tag | Sort-Object Count -Descending
        $byTag | ForEach-Object { Write-Host "  tag=$($_.Name): $($_.Count)" }
    }
} catch { Write-Host "ERRO conviction_observations: $_" -ForegroundColor Red }

# ── 6. beta_history (Supabase, criado ontem) -- confirma persistencia real ──
Write-Host "`n--- beta_history: mercados com beta persistido ---" -ForegroundColor Yellow
try {
    $betas = @(Get-StateRecords -Table "beta_history")
    Write-Host "Total mercados com beta: $($betas.Count)" -ForegroundColor Green
    foreach ($b in ($betas | Select-Object -First 15)) {
        Write-Host "  $($b.market): beta=$($b.beta) ts=$($b.timestamp)"
    }
} catch { Write-Host "ERRO beta_history: $_" -ForegroundColor Red }

# ── 7. Capital real (CoinEx) ─────────────────────────────────────────────────
Write-Host "`n--- Capital real (CoinEx) ---" -ForegroundColor Yellow
try {
    $spotCap = CoinEx-GetSpotCapitalUSDT
    $futCap = CoinEx-GetFuturesCapitalUSDT
    Write-Host "SPOT: $spotCap USDT | FUTURES: $futCap USDT | TOTAL: $($spotCap + $futCap) USDT" -ForegroundColor Green
} catch { Write-Host "ERRO capital: $_" -ForegroundColor Red }

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
