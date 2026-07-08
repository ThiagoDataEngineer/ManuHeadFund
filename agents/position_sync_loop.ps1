# position_sync_loop.ps1
# DAEMON: Sincroniza posições CoinEx → tracking.jsonl a cada 30-60 segundos
# CAUSA RAIZ FIX: lib_position_sync_realtime carregada mas nunca chamada
# 2026-07-08

#Requires -Version 5.1
$ErrorActionPreference = "Continue"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$baseDir = Split-Path -Parent $scriptDir
$journalDir = Join-Path $baseDir "journal"

# ─────────────────────────────────────────────────────────────────────────────
# LOAD LIBS
# ─────────────────────────────────────────────────────────────────────────────

try {
    . "$scriptDir\lib_coinex.ps1" -ErrorAction SilentlyContinue
    . "$scriptDir\lib_coinex_positions_fetch.ps1" -ErrorAction SilentlyContinue
    . "$scriptDir\lib_position_sync_realtime.ps1" -ErrorAction SilentlyContinue
    . "$scriptDir\lib_journal.ps1" -ErrorAction SilentlyContinue
} catch {
    Write-Host "❌ Erro ao carregar libs: $_" -ForegroundColor Red
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────

$syncInterval = 45  # segundos (entre sync)
$logFile = Join-Path $journalDir "position_sync_loop.log"
$lockFile = Join-Path $journalDir ".position_sync.lock"

function Write-SyncLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")] $Level = "INFO"
    )
    $ts = [datetime]::UtcNow.ToString("HH:mm:ss")
    $msg = "[$ts] [$Level] $Message"

    try {
        Add-Content -Path $logFile -Value $msg -ErrorAction SilentlyContinue
    } catch { }

    $color = @{ INFO = "Gray"; WARN = "Yellow"; ERROR = "Red"; SUCCESS = "Green" }[$Level]
    Write-Host $msg -ForegroundColor $color
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN LOOP
# ─────────────────────────────────────────────────────────────────────────────

Write-SyncLog "Position sync daemon started" "INFO"
Write-SyncLog "Sync interval: $syncInterval segundos" "INFO"

$syncCount = 0
$lastSync = [datetime]::MinValue

while ($true) {
    try {
        $now = [datetime]::UtcNow
        $timeSinceSync = ($now - $lastSync).TotalSeconds

        # Verificar se é hora de sincronizar
        if ($timeSinceSync -ge $syncInterval) {

            # Prevenir race condition
            if (Test-Path $lockFile) {
                Write-SyncLog "Sync já em progresso, aguardando..." "WARN"
                Start-Sleep -Seconds 5
                continue
            }

            try {
                # Criar lock file
                $now.ToString("O") | Set-Content -Path $lockFile -ErrorAction SilentlyContinue

                Write-SyncLog "Iniciando sync ($($syncCount + 1))" "INFO"

                # EXECUTAR SYNC
                if (Get-Command Sync-PositionsFromCoinEx -ErrorAction SilentlyContinue) {
                    $result = Sync-PositionsFromCoinEx -JournalDir $journalDir -ErrorAction SilentlyContinue

                    if ($result) {
                        Write-SyncLog "✅ Sync completo: $($result.synced_count) posições" "SUCCESS"
                        $syncCount++
                    } else {
                        Write-SyncLog "⚠️  Sync retornou vazio" "WARN"
                    }
                } else {
                    Write-SyncLog "❌ Sync-PositionsFromCoinEx não disponível" "ERROR"
                }

                $lastSync = $now

            } finally {
                # Remover lock file
                Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
            }
        }

        # Sleep curto para responsividade
        Start-Sleep -Seconds 5

    } catch {
        Write-SyncLog "Loop error: $_" "ERROR"
        Start-Sleep -Seconds 10
    }
}

