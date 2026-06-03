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

Write-TrailingLog "INFO" "Trailing Stop Manager iniciado. Check=$($CheckInterval)s"

# Estado: último SL que foi colocado (evita spam de updates)
$lastSlPerMarket = @{}

while ($true) {
    try {
        $positions = CoinEx-GetPendingPositions -ErrorAction SilentlyContinue

        if ($positions -and @($positions).Count -gt 0) {
            foreach ($pos in @($positions)) {
                $mkt = $pos.market
                $entry = [double]$pos.avg_entry_price
                $mark = [double]$pos.mark_price
                $current_sl = [double]$pos.stop_loss_price
                $qty = [double]$pos.qty
                $side = [string]$pos.side

                # Valida dados
                if ($mark -le 0 -or $entry -le 0) {
                    Write-TrailingLog "SKIP" "${mkt}: dados invalidos (mark=$mark entry=$entry)"
                    continue
                }

                # Calcula trailing stop (3% abaixo do mark price)
                $trailing_pct = 0.03  # 3%
                $new_sl = [math]::Round($mark * (1 - $trailing_pct), 8)

                # Se posição em GANHO, atualiza SL (lock-in de lucro)
                $pnl_pct = ($mark - $entry) / $entry
                if ($pnl_pct -gt 0.05) {  # Pelo menos 5% ganho antes de ativar trailing

                    # Se novo SL é MAIOR que atual (mais proteção), atualiza
                    if ($new_sl -gt $current_sl) {
                        $sl_improvement = $new_sl - $current_sl

                        Write-TrailingLog "UPDATE" "${mkt}: atualizando SL de $current_sl para $new_sl (ganho: $([math]::Round($pnl_pct*100,1))%)"

                        # Tenta colocar novo SL na CoinEx
                        try {
                            $inv = [System.Globalization.CultureInfo]::InvariantCulture
                            $body = @{
                                market = $mkt
                                market_type = "FUTURES"
                                stop_loss_type = "mark_price"
                                stop_loss_price = $new_sl.ToString($inv)
                            } | ConvertTo-Json

                            $response = CoinEx-Post -path "/v2/futures/set-position-stop-loss" -bodyObj ([hashtable]$body) -ErrorAction SilentlyContinue

                            if ($response.code -eq 0) {
                                Write-TrailingLog "SL_UPDATED" "${mkt}: SL atualizado com sucesso ($new_sl)"
                                $lastSlPerMarket[$mkt] = $new_sl

                                # Alerta Telegram (1x por mudança)
                                $change_pct = [math]::Round(($mark - $entry)/$entry*100, 1)
                                Send-TelegramAlert -Message "📈 $mkt | Trailing SL atualizado: $new_sl (+$change_pct% ganho, proteção 3%)" | Out-Null
                            } else {
                                Write-TrailingLog "ERROR" "${mkt}: CoinEx rejeitou SL update (code=$($response.code))"
                            }
                        } catch {
                            Write-TrailingLog "ERROR" "${mkt}: Falha ao atualizar SL: $_"
                        }
                    } else {
                        Write-TrailingLog "HOLD" "${mkt}: SL já está protegido (atual=$current_sl, novo=$new_sl)"
                    }
                } else {
                    Write-TrailingLog "HOLD" "${mkt}: ganho insuficiente ($([math]::Round($pnl_pct*100,1))%), não ativar trailing"
                }
            }
        }

        Start-Sleep -Seconds $CheckInterval
    } catch {
        Write-TrailingLog "ERROR" "Ciclo falhou: $_"
        Start-Sleep -Seconds $CheckInterval
    }
}
