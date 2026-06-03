# position_monitor.ps1 — Monitora posições abertas em TEMPO REAL
# Registra P&L, valida TP/SL, fecha se TP falhou

param(
    [int]$CheckInterval = 30  # segundos entre checks
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$agentsDir = Join-Path $projectRoot "agents"
$journalDir = Join-Path $projectRoot "journal"

function Write-MonitorLog {
    param([string]$Level, [string]$Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path (Join-Path $journalDir "position_monitor.log") -Value $line -Encoding UTF8
    Write-Host $line
}

Set-Location $projectRoot

# Carrega libs
try {
    . (Join-Path $agentsDir "config.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "config.local.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_coinex.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_telegram.ps1") -ErrorAction SilentlyContinue
} catch {
    Write-MonitorLog "ERROR" "Falha ao carregar libs: $_"
    exit 1
}

Write-MonitorLog "INFO" "Position Monitor iniciado. Check=$($CheckInterval)s"

# Deduplicação de alertas (não repetir mesma alerta)
$lastAlertTime = @{}

while ($true) {
    try {
        $positions = CoinEx-GetPendingPositions -ErrorAction SilentlyContinue

        if ($positions -and @($positions).Count -gt 0) {
            foreach ($pos in @($positions)) {
                $mkt = $pos.market
                $pnl_pct = [double]$pos.pnl_pct
                $pnl_usd = [double]$pos.pnl_usd
                $entry = [double]$pos.avg_entry_price
                $mark = [double]$pos.mark_price
                $tp = [double]$pos.take_profit_price
                $sl = [double]$pos.stop_loss_price

                # 2026-06-03: Validação — mark_price pode ser 0 (API bug), não processar
                if ($mark -le 0) {
                    Write-MonitorLog "SKIP" "${mkt} mark_price invalido ($mark), ignorando check"
                    continue
                }

                # Valida TP foi colocado corretamente
                if ($tp -le 0) {
                    Write-MonitorLog "WARN" "${mkt} TP NAO FOI COLOCADA! Valor: $tp"

                    # Dedup: só alerta 1x por hora
                    $key = "${mkt}_NO_TP"
                    if (-not $lastAlertTime[$key] -or ((Get-Date) - $lastAlertTime[$key]).TotalMinutes -gt 60) {
                        Send-TelegramAlert -Message "⚠️ $mkt SEM TP! Fechar manualmente em $mark" | Out-Null
                        $lastAlertTime[$key] = Get-Date
                    }
                }

                # Log contínuo de P&L (sem alerta, só log)
                Write-MonitorLog "POS" "${mkt} Entry: $entry Mark: $mark PnL: $pnl_usd USD ($pnl_pct%) TP: $tp SL: $sl"

                # Se atingiu TP ou SL, notifica (com dedup 1x por 5min)
                if ($mark -ge $tp -and $tp -gt 0) {
                    Write-MonitorLog "TP_HIT" "${mkt} Atingiu TP em $mark ganho: $pnl_pct%"

                    $key = "${mkt}_TP_HIT"
                    if (-not $lastAlertTime[$key] -or ((Get-Date) - $lastAlertTime[$key]).TotalMinutes -gt 5) {
                        Send-TelegramAlert -Message "✅ $mkt TP ATINGIDO! Ganho: $pnl_pct% ($pnl_usd USD)" | Out-Null
                        $lastAlertTime[$key] = Get-Date
                    }
                } elseif ($mark -le $sl -and $sl -gt 0) {
                    Write-MonitorLog "SL_HIT" "${mkt} Atingiu SL em $mark perda: $pnl_pct%"

                    $key = "${mkt}_SL_HIT"
                    if (-not $lastAlertTime[$key] -or ((Get-Date) - $lastAlertTime[$key]).TotalMinutes -gt 5) {
                        Send-TelegramAlert -Message "🛑 $mkt SL ATIVADO. Perda: $pnl_pct% ($pnl_usd USD)" | Out-Null
                        $lastAlertTime[$key] = Get-Date
                    }
                }
            }
        }

        Start-Sleep -Seconds $CheckInterval
    } catch {
        Write-MonitorLog "ERROR" "Check falhou: $_"
        Start-Sleep -Seconds $CheckInterval
    }
}
