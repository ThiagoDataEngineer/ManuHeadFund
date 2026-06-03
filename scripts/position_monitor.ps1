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

                # Valida TP foi colocado corretamente
                if ($tp -le 0) {
                    Write-MonitorLog "WARN" "${mkt} TP NAO FOI COLOCADA! Valor: $tp"
                    Send-TelegramAlert -Message "⚠️ $mkt SEM TP! Fechar manualmente em $mark" | Out-Null
                }

                # Log contínuo de P&L
                Write-MonitorLog "POS" "${mkt} Entry: $entry Mark: $mark PnL: $pnl_usd USD ($pnl_pct%) TP: $tp SL: $sl"

                # Se atingiu TP ou SL, notifica
                if ($mark -ge $tp -and $tp -gt 0) {
                    Write-MonitorLog "TP_HIT" "${mkt} Atingiu TP em $mark ganho: $pnl_pct%"
                    Send-TelegramAlert -Message "✅ $mkt TP ATINGIDO! Ganho: $pnl_pct% ($pnl_usd USD)" | Out-Null
                } elseif ($mark -le $sl -and $sl -gt 0) {
                    Write-MonitorLog "SL_HIT" "${mkt} Atingiu SL em $mark perda: $pnl_pct%"
                    Send-TelegramAlert -Message "🛑 $mkt SL ATIVADO. Perda: $pnl_pct% ($pnl_usd USD)" | Out-Null
                }
            }
        }

        Start-Sleep -Seconds $CheckInterval
    } catch {
        Write-MonitorLog "ERROR" "Check falhou: $_"
        Start-Sleep -Seconds $CheckInterval
    }
}
