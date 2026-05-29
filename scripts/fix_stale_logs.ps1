# fix_stale_logs.ps1 — Diagnosticar e resolver logs desatualizados
# 2026-05-29: Resolver problemas de position_risk.log, system.log e dashboard.log

param(
    [switch] $Diagnose,      # Apenas diagnosticar
    [switch] $FixCredentials, # Configurar credenciais
    [switch] $FixDashboard,   # Ativar dashboard cron
    [switch] $All             # Fazer tudo
)

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$agentsDir = Join-Path $scriptDir "..\agents"
$logsDir = Join-Path $scriptDir "..\logs"
$journalDir = Join-Path $scriptDir "..\journal"

# Cores
$colorGreen = "Green"
$colorRed = "Red"
$colorYellow = "Yellow"
$colorCyan = "Cyan"

Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor $colorCyan
Write-Host "║  FIX STALE LOGS - Diagnóstico e Resolução                     ║" -ForegroundColor $colorCyan
Write-Host "║  2026-05-29                                                   ║" -ForegroundColor $colorCyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor $colorCyan
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# DIAGNÓSTICO
# ─────────────────────────────────────────────────────────────────────────────

function Diagnose-Logs {
    Write-Host "📊 DIAGNÓSTICO DE LOGS" -ForegroundColor $colorCyan
    Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor $colorCyan
    Write-Host ""

    # 1. position_risk.log
    Write-Host "1️⃣  position_risk.log" -ForegroundColor $colorCyan
    $prFile = Join-Path $logsDir "position_risk.log"
    if (Test-Path $prFile) {
        $lastWrite = (Get-Item $prFile).LastWriteTime
        $age = (Get-Date) - $lastWrite
        $status = if ($age.TotalMinutes -lt 30) { "✅ OK" } else { "⚠️  STALE" }
        Write-Host "   Status: $status"
        Write-Host "   Última atualização: $lastWrite"
        Write-Host "   Idade: $([math]::Round($age.TotalMinutes, 1)) minutos"
    } else {
        Write-Host "   Status: ❌ NÃO ENCONTRADO"
    }
    Write-Host ""

    # 2. system.log
    Write-Host "2️⃣  system.log" -ForegroundColor $colorCyan
    $sysFile = Join-Path $logsDir "system.log"
    if (Test-Path $sysFile) {
        $lastWrite = (Get-Item $sysFile).LastWriteTime
        $age = (Get-Date) - $lastWrite
        $status = if ($age.TotalMinutes -lt 30) { "✅ OK" } else { "⚠️  STALE" }
        Write-Host "   Status: $status"
        Write-Host "   Última atualização: $lastWrite"
        Write-Host "   Idade: $([math]::Round($age.TotalMinutes, 1)) minutos"
        
        # Verificar credenciais
        $content = Get-Content $sysFile -Raw
        if ($content -match "Credentials not configured") {
            Write-Host "   ⚠️  CREDENCIAIS NÃO CONFIGURADAS"
        }
    } else {
        Write-Host "   Status: ❌ NÃO ENCONTRADO"
    }
    Write-Host ""

    # 3. dashboard.log
    Write-Host "3️⃣  dashboard.log" -ForegroundColor $colorCyan
    $dbFile = Join-Path $logsDir "dashboard.log"
    if (Test-Path $dbFile) {
        $lastWrite = (Get-Item $dbFile).LastWriteTime
        $age = (Get-Date) - $lastWrite
        $status = if ($age.TotalMinutes -lt 30) { "✅ OK" } else { "⚠️  STALE" }
        Write-Host "   Status: $status"
        Write-Host "   Última atualização: $lastWrite"
        Write-Host "   Idade: $([math]::Round($age.TotalMinutes, 1)) minutos"
    } else {
        Write-Host "   Status: ❌ NÃO ENCONTRADO"
    }
    Write-Host ""

    # 4. Daemons
    Write-Host "4️⃣  Status dos Daemons" -ForegroundColor $colorCyan
    $daemons = @("gem_loop", "scan_master", "watchdog_paper", "telegram_listener")
    foreach ($daemon in $daemons) {
        $processes = @(Get-Process -Name "powershell" -ErrorAction SilentlyContinue | 
                      Where-Object { $_.CommandLine -like "*$daemon*" })
        if ($processes.Count -gt 0) {
            Write-Host "   ✅ $daemon (PID: $($processes[0].Id))"
        } else {
            Write-Host "   ❌ $daemon (não encontrado)"
        }
    }
    Write-Host ""

    # 5. Credenciais
    Write-Host "5️⃣  Credenciais" -ForegroundColor $colorCyan
    $hasAccessId = -not [string]::IsNullOrWhiteSpace($env:COINEX_ACCESS_ID)
    $hasSecretKey = -not [string]::IsNullOrWhiteSpace($env:COINEX_SECRET_KEY)
    
    Write-Host "   COINEX_ACCESS_ID: $(if ($hasAccessId) { '✅ Configurada' } else { '❌ Não configurada' })"
    Write-Host "   COINEX_SECRET_KEY: $(if ($hasSecretKey) { '✅ Configurada' } else { '❌ Não configurada' })"
    
    # Verificar .env
    $envFile = Join-Path $scriptDir "..\backtest\.env"
    if (Test-Path $envFile) {
        Write-Host "   .env encontrado: ✅"
    } else {
        Write-Host "   .env encontrado: ❌"
    }
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
# CORREÇÕES
# ─────────────────────────────────────────────────────────────────────────────

function Fix-Credentials {
    Write-Host "🔧 CONFIGURAR CREDENCIAIS" -ForegroundColor $colorCyan
    Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor $colorCyan
    Write-Host ""

    Write-Host "⚠️  AVISO: Você precisa configurar as credenciais da CoinEx" -ForegroundColor $colorYellow
    Write-Host ""
    Write-Host "Opção 1: Variáveis de Ambiente (Recomendado)" -ForegroundColor $colorGreen
    Write-Host "   `$env:COINEX_ACCESS_ID = 'seu_access_id'"
    Write-Host "   `$env:COINEX_SECRET_KEY = 'seu_secret_key'"
    Write-Host ""
    Write-Host "Opção 2: Arquivo .env" -ForegroundColor $colorGreen
    Write-Host "   Criar arquivo: backtest/.env"
    Write-Host "   Conteúdo:"
    Write-Host "   COINEX_ACCESS_ID=seu_access_id"
    Write-Host "   COINEX_SECRET_KEY=seu_secret_key"
    Write-Host ""
    Write-Host "Opção 3: config.local.ps1" -ForegroundColor $colorGreen
    Write-Host "   Criar arquivo: agents/config.local.ps1"
    Write-Host "   Conteúdo:"
    Write-Host "   `$env:COINEX_ACCESS_ID = 'seu_access_id'"
    Write-Host "   `$env:COINEX_SECRET_KEY = 'seu_secret_key'"
    Write-Host ""
}

function Fix-Dashboard {
    Write-Host "🔧 ATIVAR DASHBOARD CRON" -ForegroundColor $colorCyan
    Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor $colorCyan
    Write-Host ""

    Write-Host "⚠️  AVISO: Dashboard não está em cron job" -ForegroundColor $colorYellow
    Write-Host ""
    Write-Host "Para ativar, adicione ao Windows Task Scheduler:" -ForegroundColor $colorGreen
    Write-Host ""
    Write-Host "1. Abra Task Scheduler (taskschd.msc)"
    Write-Host "2. Crie uma nova tarefa:"
    Write-Host "   - Nome: 'Coinex Dashboard Generator'"
    Write-Host "   - Ação: Executar programa"
    Write-Host "   - Programa: pwsh"
    Write-Host "   - Argumentos: -File scripts/collect_dashboard_data.ps1"
    Write-Host "   - Diretório: $scriptDir"
    Write-Host "   - Frequência: A cada 5-10 minutos"
    Write-Host ""
    Write-Host "Ou execute manualmente:"
    Write-Host "   pwsh -File scripts/collect_dashboard_data.ps1"
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

if ($Diagnose -or $All) {
    Diagnose-Logs
}

if ($FixCredentials -or $All) {
    Fix-Credentials
}

if ($FixDashboard -or $All) {
    Fix-Dashboard
}

if (-not $Diagnose -and -not $FixCredentials -and -not $FixDashboard -and -not $All) {
    Write-Host "Uso:" -ForegroundColor $colorYellow
    Write-Host "  .\fix_stale_logs.ps1 -Diagnose      # Apenas diagnosticar"
    Write-Host "  .\fix_stale_logs.ps1 -FixCredentials # Configurar credenciais"
    Write-Host "  .\fix_stale_logs.ps1 -FixDashboard   # Ativar dashboard cron"
    Write-Host "  .\fix_stale_logs.ps1 -All            # Fazer tudo"
    Write-Host ""
}

Write-Host "✅ Diagnóstico concluído" -ForegroundColor $colorGreen
