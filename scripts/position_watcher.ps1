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
    . (Join-Path $agentsDir "lib_position_price.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_daemon_singleton.ps1") -ErrorAction SilentlyContinue
} catch {
    Write-WatchLog "ERROR" "Falha ao carregar libs: $_"
    exit 1
}

# Anti-duplicata: position_watcher tambem e singleton (estava duplicando).
if (Get-Command Enter-DaemonSingleton -ErrorAction SilentlyContinue) {
    $__lockDir = Join-Path $journalDir "daemon_locks"
    if (-not (Enter-DaemonSingleton -Name "position_watcher" -LockDir $__lockDir)) {
        Write-WatchLog "SKIP" "Outro position_watcher ja detem o singleton lock; PID=$PID exit."
        exit 0
    }
}

Write-WatchLog "INFO" "Position Watcher iniciado | Check=${CheckInterval}s | FOCO: DADOS REAIS"

# Estado persistido
$positionState = @{}  # mkt -> {entry, qty, highest_price, ...}
$lastAlert = @{}      # mkt -> timestamp da última alerta

$gemTradesPath = Join-Path $journalDir "gem_trades.csv"

function Get-OpenSpotPositions {
    # Lê gem_trades.csv, filtra SPOT OPEN, verifica balance na exchange
    if (-not (Test-Path $gemTradesPath)) { return @() }
    $trades = Import-Csv $gemTradesPath -EA SilentlyContinue
    $openSpot = @($trades | Where-Object { $_.market_type -eq "SPOT" -and $_.status -eq "OPEN" })
    $result = @()
    foreach ($t in $openSpot) {
        $base = $t.market -replace "USDT$",""
        try {
            $bal = CoinEx-Get "/v2/assets/spot/balance" -EA SilentlyContinue
            $coin = if ($bal.code -eq 0) { $bal.data | Where-Object { $_.ccy -eq $base } | Select-Object -First 1 } else { $null }
            $qty = if ($coin) { [double]$coin.available + [double]$coin.frozen } else { [double]$t.qty }
            if ($qty -lt 0.0001) { continue }  # posição já fechada
            $result += [PSCustomObject]@{
                market      = $t.market
                entry_price = [double]$t.price_entry
                stop_price  = [double]$t.stop_price
                target_price= [double]$t.target_price
                qty         = $qty
                side        = "LONG"
            }
        } catch {}
    }
    return $result
}

while ($true) {
    try {
        # 1a. Posições FUTURES
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

                # 2. Se mark=0 (API bug comum em micro-caps), busca o ticker 'last'
                #    como fallback em vez de pular. Pular deixava a posicao SEM gestao
                #    de stop (capital cego). Ver lib_position_price + lib_position_price.Tests.
                if ($mark -le 0) {
                    $tickerLast = 0
                    try {
                        $ft = Invoke-RestMethod "https://api.coinex.com/v2/futures/ticker?market=$mkt" -TimeoutSec 8 -EA Stop
                        if ($ft.data) { $tickerLast = [double]$ft.data[0].last }
                    } catch { }
                    $mark = Resolve-MarkPrice -Mark $mark -TickerLast $tickerLast
                    if (-not (Test-PriceUsable -Price $mark)) {
                        Write-WatchLog "SKIP" "${mkt}: mark=0 E ticker last=0 (sem preco valido), aguardando proximo ciclo"
                        continue
                    }
                    # Recomputa pnl% price-based a partir do last real (pos.pnl_pct vinha 0/furado)
                    $pnl_pct = Get-PositionPnlPct -Price $mark -Entry $entry -Side $pos.side
                    Write-WatchLog "FALLBACK" "${mkt}: mark=0 -> ticker last=$mark | pnl(price)=$([math]::Round($pnl_pct,2))%"
                }

                $price_to_use = $mark
                if ($mark -le $entry * 0.9) {
                    # Mark price anormalmente baixo (>10% down) — verificar se é SL real
                    Write-WatchLog "WARN" "${mkt}: mark suspeito ($mark vs entry $entry), verificando SL"
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
                    $tp_dist_str = "$([math]::Round($tp_distance,2))pct"
                    Write-WatchLog "ALERT" "${mkt}: PROXIMO DO TP! Distance=$tp_dist_str"
                    Send-TelegramAlert -Message "ATENCAO: $mkt perto do TP ($tp_dist_str restante)" | Out-Null
                    $lastAlert["${mkt}_TP"] = Get-Date
                }

                # 6. Alerta se atingiu SL (esperado que fecha automaticamente)
                if ($price_to_use -le $sl) {
                    Write-WatchLog "SL_HIT" "${mkt}: SL ATIVADO! Price=$price_to_use vs SL=$sl"
                    Send-TelegramAlert -Message "SL ATIVADO $mkt | Perda: $([math]::Round($pnl_pct,2))% ($pnl_usd USD)" | Out-Null
                    $positionState.Remove($mkt)
                }

                # 7. Log contínuo conciso
                $pnl_dir = if ($pnl_pct -gt 0) { "UP" } elseif ($pnl_pct -lt 0) { "DOWN" } else { "FLAT" }
                $pnl_str = "$([math]::Round($pnl_pct,2))pct"
                Write-WatchLog "WATCH" "[$pnl_dir] ${mkt}: Price=$([math]::Round($price_to_use,6)) | PnL=$pnl_str ($pnl_usd USD) | TP=$tp | SL=$sl"
            }
        }

        # 1b. Posições SPOT (via gem_trades.csv)
        $spotPositions = Get-OpenSpotPositions
        foreach ($spos in $spotPositions) {
            $mkt = $spos.market
            try {
                $ticker = Invoke-RestMethod "https://api.coinex.com/v2/spot/ticker?market=$mkt" -EA Stop
                $currentPrice = [double]$ticker.data.last
            } catch { continue }

            if ($currentPrice -le 0) { continue }

            $entry  = $spos.entry_price
            $sl     = $spos.stop_price
            $tp     = $spos.target_price
            $qty    = $spos.qty
            $pnl_pct = if ($entry -gt 0) { [math]::Round(($currentPrice - $entry) / $entry * 100, 2) } else { 0 }
            $pnl_usd = [math]::Round(($currentPrice - $entry) * $qty, 2)

            if (-not $positionState["SPOT_$mkt"]) {
                $positionState["SPOT_$mkt"] = @{ entry=$entry; qty=$qty; highest_price=$currentPrice; opened_at=Get-Date }
                Write-WatchLog "OPEN" "SPOT ${mkt}: Entry=$entry | Qty=$qty | SL=$sl | TP=$tp"
            }
            if ($currentPrice -gt $positionState["SPOT_$mkt"].highest_price) {
                $positionState["SPOT_$mkt"].highest_price = $currentPrice
            }

            $pnl_emoji = if ($pnl_pct -gt 0) { "GANHO" } elseif ($pnl_pct -lt 0) { "PERDA" } else { "FLAT" }
            Write-WatchLog "SPOT" "[$pnl_emoji] ${mkt}: Price=$currentPrice | PnL=$pnl_pct% ($pnl_usd USD) | SL=$sl | TP=$tp"

            # Alerta se próximo do SL
            if ($sl -gt 0 -and $currentPrice -le ($sl * 1.05) -and -not $lastAlert["${mkt}_SL_WARN"]) {
                Send-TelegramAlert -Message "SPOT $mkt PROXIMO DO SL! Price=$currentPrice SL=$sl PnL=$pnl_pct%" | Out-Null
                $lastAlert["${mkt}_SL_WARN"] = Get-Date
                Write-WatchLog "WARN" "SPOT ${mkt}: Proximo do SL ($currentPrice vs $sl)"
            }
        }

        Start-Sleep -Seconds $CheckInterval
    } catch {
        Write-WatchLog "ERROR" "Ciclo falhou: $_"
        Start-Sleep -Seconds $CheckInterval
    }
}
