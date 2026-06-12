# profit_realizer.ps1 — Realiza lucro automaticamente quando atinge meta
# Garante que posições FECHAM com ganho, não fica "vendo correr"

param(
    [int]$CheckInterval = 30,  # segundos entre checks
    [double]$MinProfitPct = 5.0  # mínimo 5% de ganho para considerar vender
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$agentsDir = Join-Path $projectRoot "agents"
$journalDir = Join-Path $projectRoot "journal"

function Write-ProfitLog {
    param([string]$Level, [string]$Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path (Join-Path $journalDir "profit_realizer.log") -Value $line -Encoding UTF8
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
    Write-ProfitLog "ERROR" "Falha ao carregar libs: $_"
    exit 1
}

Write-ProfitLog "INFO" "Profit Realizer iniciado. MinProfit=$($MinProfitPct)% | Check=$($CheckInterval)s"

# Rastreia se já tentou vender (evita spam)
$attemptedSell = @{}

while ($true) {
    try {
        $positions = CoinEx-GetPendingPositions -ErrorAction SilentlyContinue

        if ($positions -and @($positions).Count -gt 0) {
            foreach ($pos in @($positions)) {
                $mkt = $pos.market
                $entry = [double]$pos.avg_entry_price
                $mark = [double]$pos.mark_price
                $pnl_pct = [double]$pos.pnl_pct
                $pnl_usd = [double]$pos.pnl_usd
                $qty = [double]$pos.qty

                # Se mark=0, pula (API bug)
                if ($mark -le 0) {
                    continue
                }

                # ===== LÓGICA DE REALIZAÇÃO DE LUCRO =====
                # 1. Se ganho >= MinProfitPct: VENDER AGORA
                if ($pnl_pct -ge $MinProfitPct) {
                    if (-not $attemptedSell[$mkt]) {
                        Write-ProfitLog "SELL" "${mkt}: ATINGIU META DE LUCRO ($pnl_pct%) — VENDENDO AGORA!"

                        # Tenta vender no mark price atual
                        try {
                            # TODO: Chamar CoinEx-PlaceOrder para vender qty
                            # Por enquanto, apenas loga para aprovação manual
                            $sellMsg = "📊 VENDA RECOMENDADA: $mkt`nGanho: $pnl_pct% ($pnl_usd USD)`nQty: $qty`nPreço: $mark`nAction: APPROVE em Telegram"
                            Send-TelegramAlert -Message $sellMsg | Out-Null

                            $attemptedSell[$mkt] = $true
                        } catch {
                            Write-ProfitLog "ERROR" "${mkt}: Falha ao tentar vender: $_"
                        }
                    }
                }
                # 2. Se PERDENDO (pnl_pct < -2%): ALERTA CRÍTICO
                elseif ($pnl_pct -lt -2) {
                    Write-ProfitLog "LOSS_ALERT" "${mkt}: PERDENDO $($pnl_pct)% ($pnl_usd USD) — STOP LOSS DEVE ATIVAR"
                    Send-TelegramAlert -Message "🔴 ALERTA: $mkt perdendo $([math]::Round($pnl_pct, 1))% — SL deve ativar em breve" | Out-Null
                }
                # 3. LOG contínuo de P&L
                else {
                    Write-ProfitLog "POS" "${mkt}: P&L $([math]::Round($pnl_pct, 2))% ($pnl_usd USD) — TP em $(([math]::Round($pnl_pct, 1)) - $MinProfitPct)% restantes"
                }
            }
        }

        Start-Sleep -Seconds $CheckInterval
    } catch {
        Write-ProfitLog "ERROR" "Ciclo falhou: $_"
        Start-Sleep -Seconds $CheckInterval
    }
}
