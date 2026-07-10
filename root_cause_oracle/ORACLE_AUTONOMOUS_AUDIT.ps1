# ORACLE_AUTONOMOUS_AUDIT.ps1
# Auditoria completa do sistema para 24/7 autonomous trading
# Verifica TUDO: libs, config, daemons, safeguards, profitability
# Deteta gaps e recomenda fixes

#Requires -Version 5.1
Set-StrictMode -Off

$workdir = "C:\Users\thiag\Coinex_AI_USER_API"
Set-Location $workdir

$auditResults = @{
    timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    checks = @()
    recommendations = @()
    blockers = @()
    confidence = 0.0
}

function Add-Check {
    param([string]$category, [string]$check, [bool]$status, [string]$details)
    $auditResults.checks += [PSCustomObject]@{
        category = $category
        check = $check
        status = if ($status) { "PASS" } else { "FAIL" }
        details = $details
        timestamp = Get-Date
    }
}

function Add-Blocker {
    param([string]$severity, [string]$issue, [string]$impact, [string]$fix)
    $auditResults.blockers += [PSCustomObject]@{
        severity = $severity
        issue = $issue
        impact = $impact
        fix = $fix
    }
}

function Add-Recommendation {
    param([string]$priority, [string]$recommendation, [string]$benefit, [string]$effort)
    $auditResults.recommendations += [PSCustomObject]@{
        priority = $priority
        recommendation = $recommendation
        benefit = $benefit
        effort = $effort
    }
}

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║   🔍 ORACLE AUTONOMOUS AUDIT — Diagnóstico profundo        ║" -ForegroundColor Magenta
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

# ============================================================================
# CATEGORIA 1: LIBS E CÓDIGO
# ============================================================================

Write-Host "📦 Verificando LIBS..." -ForegroundColor Cyan

$criticalLibs = @(
    "agents\lib_coinex.ps1",
    "agents\lib_gem_decision_cache.ps1",
    "agents\lib_position_sync_realtime.ps1",
    "agents\gem_executor.ps1",
    "agents\scan_master.ps1"
)

$missingLibs = @()
foreach ($lib in $criticalLibs) {
    if (Test-Path $lib) {
        Add-Check "LIBS" "$lib existe" $true "OK"
        Write-Host "   ✅ $lib" -ForegroundColor Green
    } else {
        Add-Check "LIBS" "$lib existe" $false "MISSING"
        $missingLibs += $lib
        Write-Host "   ❌ $lib" -ForegroundColor Red
    }
}

if ($missingLibs.Count -gt 0) {
    Add-Blocker "CRITICAL" "Libs faltando: $($missingLibs -join ', ')" "Sistema não inicia" "Restaurar de git"
}

Write-Host ""

# ============================================================================
# CATEGORIA 2: CONFIG E CREDENCIAIS
# ============================================================================

Write-Host "🔑 Verificando Config..." -ForegroundColor Cyan

if (Test-Path "agents\config.local.ps1") {
    Add-Check "CONFIG" "config.local.ps1 existe" $true "OK"
    Write-Host "   ✅ config.local.ps1" -ForegroundColor Green

    try {
        . "agents\config.local.ps1" -ErrorAction Stop
        Add-Check "CONFIG" "config.local.ps1 parsa" $true "OK"
        Write-Host "   ✅ Config parsa corretamente" -ForegroundColor Green
    } catch {
        Add-Check "CONFIG" "config.local.ps1 parsa" $false "SYNTAX ERROR: $_"
        Add-Blocker "CRITICAL" "Config syntax error" "Sistema não inicia" "Corrigir syntax em config.local.ps1"
        Write-Host "   ❌ Config parse error: $_" -ForegroundColor Red
    }
} else {
    Add-Check "CONFIG" "config.local.ps1 existe" $false "MISSING"
    Add-Blocker "CRITICAL" "Sem config.local.ps1" "Credenciais não carregam" "Copiar config.template.ps1 → config.local.ps1"
    Write-Host "   ❌ config.local.ps1 MISSING" -ForegroundColor Red
}

# Check credenciais
$accessId = if ($script:COINEX_ACCESS_ID -and $script:COINEX_ACCESS_ID -notlike "*placeholder*") { "SET" } else { "MISSING" }
$secretKey = if ($script:COINEX_SECRET_KEY -and $script:COINEX_SECRET_KEY -notlike "*placeholder*") { "SET" } else { "MISSING" }

Add-Check "CONFIG" "COINEX_ACCESS_ID" ($accessId -eq "SET") $accessId
Add-Check "CONFIG" "COINEX_SECRET_KEY" ($secretKey -eq "SET") $secretKey

Write-Host "   $($accessId -eq 'SET' ? '✅' : '❌') COINEX_ACCESS_ID: $accessId" -ForegroundColor (if ($accessId -eq "SET") { "Green" } else { "Red" })
Write-Host "   $($secretKey -eq 'SET' ? '✅' : '❌') COINEX_SECRET_KEY: $secretKey" -ForegroundColor (if ($secretKey -eq "SET") { "Green" } else { "Red" })

if ($accessId -ne "SET" -or $secretKey -ne "SET") {
    Add-Blocker "CRITICAL" "CoinEx credenciais incompletas" "Trades não executam" "Set COINEX_ACCESS_ID e COINEX_SECRET_KEY em config.local.ps1"
}

Write-Host ""

# ============================================================================
# CATEGORIA 3: JOURNAL E ESTADO
# ============================================================================

Write-Host "📋 Verificando Journal..." -ForegroundColor Cyan

$journalFiles = @(
    "journal\trade_outcomes.jsonl",
    "journal\open_positions_tracking.jsonl",
    "journal\gem_recent_decisions.json",
    "journal\MARKET_REGIME.flag"
)

foreach ($file in $journalFiles) {
    $exists = Test-Path $file
    Add-Check "JOURNAL" "$file" $exists "$(if ($exists) { 'OK' } else { 'MISSING' })"
    Write-Host "   $($exists ? '✅' : '❌') $file" -ForegroundColor (if ($exists) { "Green" } else { "Yellow" })
}

# Check regime
if (Test-Path "journal\MARKET_REGIME.flag") {
    $regime = Get-Content "journal\MARKET_REGIME.flag" -Raw
    Write-Host "   ℹ️  Regime atual: $regime" -ForegroundColor Gray
}

Write-Host ""

# ============================================================================
# CATEGORIA 4: DAEMONS E AUTO-EXECUTION
# ============================================================================

Write-Host "⚙️  Verificando Daemons..." -ForegroundColor Cyan

$daemons = @(
    "agents\gem_loop.ps1",
    "agents\scan_master.ps1",
    "agents\position_watcher.ps1",
    "agents\tori_daemon_simple.ps1"
)

$activeDaemons = 0
foreach ($daemon in $daemons) {
    $exists = Test-Path $daemon
    Add-Check "DAEMONS" "$(Split-Path $daemon -Leaf)" $exists "$(if ($exists) { 'EXISTS' } else { 'MISSING' })"
    if ($exists) {
        Write-Host "   ✅ $(Split-Path $daemon -Leaf)" -ForegroundColor Green
        $activeDaemons++
    } else {
        Write-Host "   ⚠️  $(Split-Path $daemon -Leaf)" -ForegroundColor Yellow
    }
}

Write-Host "   ℹ️  Daemons disponíveis: $activeDaemons/4" -ForegroundColor Gray

if ($activeDaemons -lt 2) {
    Add-Blocker "HIGH" "Poucos daemons" "Autonomia reduzida" "Restaurar gem_loop.ps1 e scan_master.ps1"
}

Write-Host ""

# ============================================================================
# CATEGORIA 5: SAFEGUARDS E FAIL-CLOSED
# ============================================================================

Write-Host "🛡️  Verificando Safeguards..." -ForegroundColor Cyan

$safeguards = @(
    @{ name = "Stop Loss Gate"; file = "agents\lib_position_protection.ps1" },
    @{ name = "Entry Quality Gate"; file = "agents\lib_entry_quality_gate.ps1" },
    @{ name = "Regime Gate"; file = "agents\lib_btc_regime_gate.ps1" },
    @{ name = "Risk Manager"; file = "agents\lib_position_risk_manager.ps1" }
)

$safeguardCount = 0
foreach ($sg in $safeguards) {
    $exists = Test-Path $sg.file
    Add-Check "SAFEGUARDS" $sg.name $exists "$(if ($exists) { 'ACTIVE' } else { 'MISSING' })"
    Write-Host "   $($exists ? '✅' : '⚠️ ') $($sg.name)" -ForegroundColor (if ($exists) { "Green" } else { "Yellow" })
    if ($exists) { $safeguardCount++ }
}

Write-Host "   ℹ️  Safeguards ativas: $safeguardCount/4" -ForegroundColor Gray

if ($safeguardCount -lt 3) {
    Add-Recommendation "CRITICAL" "Ativar todos safeguards" "Protege capital contra erros e market crashes" "2h"
}

Write-Host ""

# ============================================================================
# CATEGORIA 6: SUPABASE E CLOUD STATE
# ============================================================================

Write-Host "☁️  Verificando Supabase..." -ForegroundColor Cyan

$supaUrl = if ($script:SUPABASE_URL) { "CONFIGURED" } else { "MISSING" }
$supaKey = if ($script:SUPABASE_SERVICE_KEY) { "CONFIGURED" } else { "MISSING" }

Add-Check "SUPABASE" "SUPABASE_URL" ($supaUrl -eq "CONFIGURED") $supaUrl
Add-Check "SUPABASE" "SUPABASE_SERVICE_KEY" ($supaKey -eq "CONFIGURED") $supaKey

Write-Host "   $($supaUrl -eq 'CONFIGURED' ? '✅' : '⚠️ ') URL: $supaUrl" -ForegroundColor (if ($supaUrl -eq "CONFIGURED") { "Green" } else { "Yellow" })
Write-Host "   $($supaKey -eq 'CONFIGURED' ? '✅' : '⚠️ ') Key: $supaKey" -ForegroundColor (if ($supaKey -eq "CONFIGURED") { "Green" } else { "Yellow" })

if ($supaUrl -ne "CONFIGURED" -or $supaKey -ne "CONFIGURED") {
    Add-Recommendation "HIGH" "Configurar Supabase" "State persistence na cloud + audit trail" "15min"
}

Write-Host ""

# ============================================================================
# CATEGORIA 7: PERFORMANCE E PROFITABILITY
# ============================================================================

Write-Host "📈 Verificando Profitability..." -ForegroundColor Cyan

if (Test-Path "journal\trade_outcomes.jsonl") {
    try {
        $trades = @(Get-Content "journal\trade_outcomes.jsonl" | ConvertFrom-Json -ErrorAction SilentlyContinue | Where-Object { $_ })
        $winTrades = @($trades | Where-Object { [double]$_.pnl_usd -gt 0 })
        $lossTrades = @($trades | Where-Object { [double]$_.pnl_usd -lt 0 })
        $totalPnL = ($trades | Measure-Object -Property pnl_usd -Sum).Sum

        $winRate = if ($trades.Count -gt 0) { ($winTrades.Count / $trades.Count * 100) } else { 0 }

        Add-Check "PROFITABILITY" "Total trades" $true "$($trades.Count) trades registrados"
        Add-Check "PROFITABILITY" "Win rate" $true "$([int]$winRate)% ($($winTrades.Count)/$($trades.Count))"
        Add-Check "PROFITABILITY" "PnL total" $true "`$$([math]::Round($totalPnL, 2))"

        Write-Host "   ℹ️  Total trades: $($trades.Count)" -ForegroundColor Gray
        Write-Host "   ℹ️  Win rate: $([int]$winRate)% ($($winTrades.Count) wins / $($lossTrades.Count) losses)" -ForegroundColor Gray
        Write-Host "   ℹ️  PnL total: `$$([math]::Round($totalPnL, 2))" -ForegroundColor Gray

        if ($winRate -lt 40) {
            Add-Blocker "HIGH" "Win rate < 40%" "Profitability marginal" "Revisar entry signals + stops"
        }
    } catch {
        Write-Host "   ⚠️  Erro ao ler trades: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "   ℹ️  Sem histórico de trades" -ForegroundColor Gray
}

Write-Host ""

# ============================================================================
# RESULTADO FINAL
# ============================================================================

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta

$passCount = @($auditResults.checks | Where-Object { $_.status -eq "PASS" }).Count
$failCount = @($auditResults.checks | Where-Object { $_.status -eq "FAIL" }).Count
$blockerCount = $auditResults.blockers.Count

Write-Host "📊 RESULTADO:" -ForegroundColor Magenta
Write-Host "   ✅ Checks passando: $passCount" -ForegroundColor Green
Write-Host "   ❌ Checks falhando: $failCount" -ForegroundColor Red
Write-Host "   🚨 Blockers críticos: $blockerCount" -ForegroundColor Red
Write-Host ""

if ($blockerCount -gt 0) {
    Write-Host "🚨 BLOCKERS CRÍTICOS:" -ForegroundColor Red
    foreach ($blocker in $auditResults.blockers) {
        Write-Host "   [$($blocker.severity)] $($blocker.issue)" -ForegroundColor Red
        Write-Host "      Impact: $($blocker.impact)" -ForegroundColor Red
        Write-Host "      Fix: $($blocker.fix)" -ForegroundColor Yellow
        Write-Host ""
    }
}

if ($auditResults.recommendations.Count -gt 0) {
    Write-Host "💡 RECOMENDAÇÕES:" -ForegroundColor Cyan
    foreach ($rec in $auditResults.recommendations | Sort-Object { @{CRITICAL=0; HIGH=1; MEDIUM=2; LOW=3}[$_.priority] }) {
        Write-Host "   [$($rec.priority)] $($rec.recommendation)" -ForegroundColor Cyan
        Write-Host "      Benefício: $($rec.benefit)" -ForegroundColor Gray
        Write-Host "      Esforço: $($rec.effort)" -ForegroundColor Gray
        Write-Host ""
    }
}

# Confidence score
$confidence = (($passCount / ($passCount + $failCount)) * 100)
$auditResults.confidence = $confidence

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "🎯 AUTONOMY READINESS: $([int]$confidence)%" -ForegroundColor (if ($confidence -ge 80) { "Green" } else { "Red" })
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host ""

if ($confidence -ge 90) {
    Write-Host "🚀 SISTEMA PRONTO PARA 24/7 AUTONOMOUS (weekend completo)" -ForegroundColor Green
} elseif ($confidence -ge 75) {
    Write-Host "⚠️  SISTEMA COM 75%+ — Pode rodar 24/7 COM MONITORAMENTO" -ForegroundColor Yellow
} else {
    Write-Host "❌ SISTEMA NÃO PRONTO — Corrigir blockers antes de 24/7" -ForegroundColor Red
}

Write-Host ""

# Save report
$auditResults | ConvertTo-Json | Out-File -FilePath "root_cause_oracle\AUDIT_REPORT_$(Get-Date -Format 'yyyyMMdd_HHmmss').json" -Encoding UTF8
Write-Host "📄 Relatório salvo em root_cause_oracle\AUDIT_REPORT_*.json" -ForegroundColor Gray
Write-Host ""
