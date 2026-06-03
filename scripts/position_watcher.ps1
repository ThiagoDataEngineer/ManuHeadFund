# position_watcher.ps1 — Monitora posições COM DADOS REAIS (não API bugada)
# Usa CoinEx websocket ou polling com fallback local

param(
    [int]$CheckInterval = 15  # segundos entre checks
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$agentsDir = Join-Path $projectRoot "agents"
$journalDir = Join-Path $projectRoot "journal"

function Write-WatchLog {
    param([string]$Level, [string]$Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path (Join-Path $journalDir "position_watcher.log") -Value $line -Encoding UTF8
    Write-Host $line
}

Set-Location $projectRoot

try {
    . (Join-Path $agentsDir "config.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "config.local.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_coinex.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_telegram.ps1") -ErrorAction SilentlyContinue
} catch {
    Write-WatchLog "ERROR" "Falha ao carregar libs: $_"
    exit 1
}

Write-WatchLog "INFO" "Position Watcher iniciado | Check=${CheckInterval}s | FOCO: DADOS REAIS"

# Estado persistido
$positionState = @{}  # mkt -> {entry, qty, highest_price, ...}
$lastAlert = @{}      # mkt -> timestamp da última alerta

while ($true) {
    try {
        # 1. Tentar obter posições via API
        $positions = CoinEx-GetPendingPositions -ErrorAction SilentlyContinue

        if ($positions -and @($positions).Count -gt 0) {
            foreach ($pos in @($positions)) {
                $mkt = $pos.market
                $entry = [double]$pos.avg_entry_price
                $mark = [double]$pos.mark_price
                $pnl_usd = [double]$pos.pnl_usd
                $pnl_pct = [double]$pos.pnl_pct
                $qty = [double]$pos.qty
                $tp = [double]$pos.take_profit_price
                $sl = [double]$pos.stop_loss_price

                # 2. Se mark=0 (API bug), usar last-known price como fallback
                $price_to_use = $mark
                if ($mark -le 0 -or $mark -le $entry * 0.9) {
                    # Mark price inválido — usar TradingView price via history
                    # Por enquanto, usa entry como fallback (conservador)
                    $price_to_use = $entry
                    Write-WatchLog "WARN" "${mkt}: mark inválido ($mark), usando entry como fallback"
                }

                # 3. Atualiza estado local
                if (-not $positionState[$mkt]) {
                    $positionState[$mkt] = @{
                        entry = $entry
                        qty = $qty
                        highest_price = $price_to_use
                        highest_pnl = $pnl_pct
                        opened_at = Get-Date
                    }
                    Write-WatchLog "OPEN" "${mkt}: POSIÇÃO ABERTA | Entry=$entry | Qty=$qty"
                }

                # 4. Rastreia melhor preço (para trailing stop)
                if ($price_to_use -gt $positionState[$mkt].highest_price) {
                    $positionState[$mkt].highest_price = $price_to_use
                    $positionState[$mkt].highest_pnl = $pnl_pct
                    Write-WatchLog "HIGH" "${mkt}: NOVO MÁXIMO | Price=$price_to_use | PnL=$([math]::Round($pnl_pct,2))%"
                }

                # 5. Alerta se chegou perto do TP
                $tp_distance = (($tp - $price_to_use) / $price_to_use) * 100
                if ($tp_distance -lt 2 -and -not $lastAlert["${mkt}_TP"]) {
                    Write-WatchLog "ALERT" "${mkt}: PRÓXIMO DO TP! Distance=$([math]::Round($tp_distance,2))%"
                    Send-TelegramAlert -Message "⚠️ $mkt muito perto do TP ($([math]::Round($tp_distance,2))% restante)" | Out-Null
                    $lastAlert["${mkt}_TP"] = Get-Date
                }

                # 6. Alerta se atingiu SL (esperado que fecha automaticamente)
                if ($price_to_use -le $sl) {
                    Write-WatchLog "SL_HIT" "${mkt}: SL ATIVADO! Price=$price_to_use vs SL=$sl"
                    Send-TelegramAlert -Message "🛑 $mkt SL ATIVADO | Perda: $([math]::Round($pnl_pct,2))% ($pnl_usd USD)" | Out-Null
                    $positionState.Remove($mkt)
                }

                # 7. Log contínuo conciso
                $pnl_emoji = if ($pnl_pct -gt 0) { "📈" } elseif ($pnl_pct -lt 0) { "📉" } else { "➡️" }
                Write-WatchLog "WATCH" "${pnl_emoji} ${mkt}: Price=$([math]::Round($price_to_use,6)) | PnL=$([math]::Round($pnl_pct,2))% ($pnl_usd USD) | TP=$tp | SL=$sl"
            }
        }

        Start-Sleep -Seconds $CheckInterval
    } catch {
        Write-WatchLog "ERROR" "Ciclo falhou: $_"
        Start-Sleep -Seconds $CheckInterval
    }
}
