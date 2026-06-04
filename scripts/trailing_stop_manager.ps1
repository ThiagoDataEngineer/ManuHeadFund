# trailing_stop_manager.ps1 — Gerencia trailing stop AUTOMÁTICO para posições abertas
# Atualiza SL quando preço sobe, garante lock-in de lucro

param(
    [int]$CheckInterval = 60  # segundos entre checks
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$agentsDir = Join-Path $projectRoot "agents"
$journalDir = Join-Path $projectRoot "journal"

function Write-TrailingLog {
    param([string]$Level, [string]$Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path (Join-Path $journalDir "trailing_stop.log") -Value $line -Encoding UTF8
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
    Write-TrailingLog "ERROR" "Falha ao carregar libs: $_"
    exit 1
}

Write-TrailingLog "INFO" "Trailing Stop Manager iniciado. Check=$($CheckInterval)s (FUTURES + SPOT)"

$gemTradesPath = Join-Path $journalDir "gem_trades.csv"
$inv = [System.Globalization.CultureInfo]::InvariantCulture
$trailing_pct = 0.03   # 3% abaixo do peak
$activate_pct = 0.05   # ativa trailing apenas quando ganho >= 5%

# Estado por mercado: ultimo SL colocado + peak price
$state = @{}  # mkt -> @{ last_sl; peak }

# ─── helpers ──────────────────────────────────────────────────────────────────

function Update-TrailingFutures($mkt, $entry, $mark, $current_sl) {
    $pnl_pct = ($mark - $entry) / $entry
    if ($pnl_pct -lt $activate_pct) {
        Write-TrailingLog "HOLD" "FUTURES ${mkt}: ganho $([math]::Round($pnl_pct*100,1))pct < 5pct, aguardando"
        return
    }
    if (-not $state[$mkt]) { $state[$mkt] = @{ peak = $mark; last_sl = $current_sl } }
    if ($mark -gt $state[$mkt].peak) { $state[$mkt].peak = $mark }

    $new_sl = [math]::Round($state[$mkt].peak * (1 - $trailing_pct), 8)
    if ($new_sl -le $current_sl) {
        Write-TrailingLog "HOLD" "FUTURES ${mkt}: SL protegido (atual=$current_sl, novo=$new_sl)"
        return
    }
    try {
        $r = CoinEx-Post "/v2/futures/set-position-stop-loss" @{
            market          = $mkt
            market_type     = "FUTURES"
            stop_loss_type  = "mark_price"
            stop_loss_price = $new_sl.ToString($inv)
        }
        if ($r.code -eq 0) {
            Write-TrailingLog "SL_UPDATED" "FUTURES ${mkt}: $current_sl -> $new_sl (peak=$($state[$mkt].peak) +$([math]::Round($pnl_pct*100,1))pct)"
            $state[$mkt].last_sl = $new_sl
            $gain = [math]::Round($pnl_pct*100,1)
            Send-TelegramAlert -Message "TRAILING $mkt SL=$new_sl (+${gain}pct, peak=$($state[$mkt].peak))" | Out-Null
        } else {
            Write-TrailingLog "ERROR" "FUTURES ${mkt}: CoinEx rejeitou (code=$($r.code) $($r.message))"
        }
    } catch {
        Write-TrailingLog "ERROR" "FUTURES ${mkt}: $_"
    }
}

function Update-TrailingSpot($mkt, $entry, $current_price, $current_sl_id, $qty) {
    $pnl_pct = ($current_price - $entry) / $entry
    if ($pnl_pct -lt $activate_pct) {
        Write-TrailingLog "HOLD" "SPOT ${mkt}: ganho $([math]::Round($pnl_pct*100,1))pct < 5pct, aguardando"
        return $current_sl_id
    }
    if (-not $state["SPOT_$mkt"]) { $state["SPOT_$mkt"] = @{ peak = $current_price; last_sl = 0 } }
    if ($current_price -gt $state["SPOT_$mkt"].peak) { $state["SPOT_$mkt"].peak = $current_price }

    $new_sl = [math]::Round($state["SPOT_$mkt"].peak * (1 - $trailing_pct), 8)
    if ($new_sl -le $state["SPOT_$mkt"].last_sl) {
        Write-TrailingLog "HOLD" "SPOT ${mkt}: SL protegido (last=$($state["SPOT_$mkt"].last_sl), novo=$new_sl)"
        return $current_sl_id
    }

    # SPOT: cancela stop antiga e cria nova
    $new_sl_id = $null
    try {
        # 1. Cancela stop order anterior (se existir)
        if ($current_sl_id) {
            $rc = CoinEx-Post "/v2/spot/cancel-stop-order" @{ market=$mkt; market_type="SPOT"; stop_id=[long]$current_sl_id }
            if ($rc.code -eq 0) {
                Write-TrailingLog "CANCEL" "SPOT ${mkt}: stop $current_sl_id cancelada"
            }
        }
        # 2. Cria nova stop order com SL atualizado
        $base = $mkt -replace "USDT$",""
        $r = CoinEx-Post "/v2/spot/stop-order" @{
            market        = $mkt
            market_type   = "SPOT"
            side          = "sell"
            type          = "market"
            amount        = ([math]::Round($qty, 6)).ToString($inv)
            ccy           = $base
            trigger_price = $new_sl.ToString($inv)
            trigger_type  = "price_less_equal"
        }
        if ($r.code -eq 0) {
            $new_sl_id = $r.data.stop_id
            Write-TrailingLog "SL_UPDATED" "SPOT ${mkt}: SL $($state["SPOT_$mkt"].last_sl) -> $new_sl stop_id=$new_sl_id (peak=$($state["SPOT_$mkt"].peak))"
            $state["SPOT_$mkt"].last_sl = $new_sl
            $gain = [math]::Round($pnl_pct*100,1)
            Send-TelegramAlert -Message "TRAILING SPOT $mkt SL=$new_sl (+${gain}pct, peak=$($state["SPOT_$mkt"].peak))" | Out-Null
            return $new_sl_id
        } else {
            Write-TrailingLog "ERROR" "SPOT ${mkt}: nova stop falhou (code=$($r.code) $($r.message))"
        }
    } catch {
        Write-TrailingLog "ERROR" "SPOT ${mkt}: $_"
    }
    return $current_sl_id
}

# Estado das stop orders SPOT ativas por market (stop_id)
$spotStopIds = @{}

# ─── loop principal ───────────────────────────────────────────────────────────

while ($true) {
    try {
        # ── FUTURES ──────────────────────────────────────────────────────────
        $positions = CoinEx-GetPendingPositions -ErrorAction SilentlyContinue
        foreach ($pos in @($positions)) {
            $mkt   = $pos.market
            $entry = [double]$pos.avg_entry_price
            $mark  = [double]$pos.mark_price
            $sl    = [double]$pos.stop_loss_price
            if ($mark -le 0) { Write-TrailingLog "SKIP" "FUTURES ${mkt}: mark=0, pulando"; continue }
            if ($entry -le 0) { continue }
            Update-TrailingFutures $mkt $entry $mark $sl
        }

        # ── SPOT ─────────────────────────────────────────────────────────────
        if (Test-Path $gemTradesPath) {
            $openSpot = @(Import-Csv $gemTradesPath -EA SilentlyContinue |
                          Where-Object { $_.market_type -eq "SPOT" -and $_.status -eq "OPEN" })
            foreach ($t in $openSpot) {
                $mkt   = $t.market
                $entry = [double]$t.price_entry
                $sl    = [double]$t.stop_price
                $qty   = [double]$t.qty
                if ($entry -le 0) { continue }

                try {
                    $ticker = Invoke-RestMethod "https://api.coinex.com/v2/spot/ticker?market=$mkt" -EA Stop
                    $price  = [double]$ticker.data.last
                } catch { continue }
                if ($price -le 0) { continue }

                # Busca stop_id atual (da última vez que foi atualizado ou do estado inicial)
                if (-not $spotStopIds[$mkt]) { $spotStopIds[$mkt] = 0 }

                # Verifica stop ativas na exchange para pegar o stop_id real
                if ($spotStopIds[$mkt] -eq 0) {
                    try {
                        $sr = CoinEx-Get "/v2/spot/pending-stop-order?market=$mkt&limit=5"
                        if ($sr.code -eq 0 -and @($sr.data.items).Count -gt 0) {
                            $stopItem = $sr.data.items | Sort-Object created_at -Descending | Select-Object -First 1
                            $spotStopIds[$mkt] = $stopItem.stop_id
                        }
                    } catch {}
                }

                $spotStopIds[$mkt] = Update-TrailingSpot $mkt $entry $price $spotStopIds[$mkt] $qty
            }
        }

        Start-Sleep -Seconds $CheckInterval
    } catch {
        Write-TrailingLog "ERROR" "Ciclo falhou: $_"
        Start-Sleep -Seconds $CheckInterval
    }
}
