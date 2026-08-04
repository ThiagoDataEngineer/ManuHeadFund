# diag_spot_vs_futures_opens_2026_08_04.ps1 -- ONE-SHOT, so leitura.
#
# diag_spot_vs_futures_volume_before_after_serio (rodado antes) mostrou que
# trade_outcomes (fechamentos) esta vazio pro periodo recente -- posicoes
# ainda abertas nao aparecem la. Owner quer volume de ABERTURAS, nao
# fechamentos. Fonte real: trailing_state (todas ativas, com createdAt) +
# CoinEx direto (SPOT balances/FUTURES pending-position) pra contagem atual
# por tipo, ja que o journal nao guarda market_type explicito.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG: aberturas SPOT vs FUTURES (trailing_state, todas ativas) ===" -ForegroundColor Cyan

try {
    $rows = @(Get-StateRecords -Table "trailing_state" -Filter @{ active = $true })
    Write-Host "Total ativas: $($rows.Count)`n"

    Write-Host "--- Campos disponiveis no primeiro registro (schema real) ---" -ForegroundColor Yellow
    if ($rows.Count -gt 0) {
        $rows[0].PSObject.Properties | ForEach-Object { Write-Host "  $($_.Name) = $($_.Value)" }
    }

    Write-Host "`n--- Todas as posicoes ativas, ordenadas por abertura ---" -ForegroundColor Yellow
    $withTs = @($rows | ForEach-Object {
        $raw = if ($_.PSObject.Properties['createdAt']) { $_.createdAt } elseif ($_.PSObject.Properties['created_at']) { $_.created_at } else { $null }
        $ts = try { if ($raw -is [datetime]) { $raw } elseif ($raw) { [datetime]::Parse([string]$raw) } else { $null } } catch { $null }
        [PSCustomObject]@{ market = $_.market; mode = $_.mode; ts = $ts; side = $_.side }
    })
    $withTs | Sort-Object ts | ForEach-Object {
        $tsStr = if ($_.ts) { $_.ts.ToString("yyyy-MM-dd HH:mm") } else { "sem_timestamp" }
        Write-Host ("  {0} {1,-14} mode={2,-10} side={3}" -f $tsStr, $_.market, $_.mode, $_.side)
    }

    Write-Host "`n--- Contagem real AGORA: FUTURES (CoinEx-GetPendingPositions) ---" -ForegroundColor Yellow
    $futPos = @(CoinEx-GetPendingPositions)
    Write-Host "Total posicoes FUTURES abertas: $($futPos.Count)"
    $futPos | ForEach-Object { Write-Host "  $($_.market) side=$($_.side)" }

    Write-Host "`n--- Contagem real AGORA: SPOT holdings relevantes (CoinEx-GetOpenOrders, MinValueUSD>=3) ---" -ForegroundColor Yellow
    if (Get-Command CoinEx-GetOpenOrders -ErrorAction SilentlyContinue) {
        $openOrders = @(CoinEx-GetOpenOrders -MinValueUSD 3.0)
        $spotOnly = @($openOrders | Where-Object { $_.market_type -eq "SPOT" -or (-not $_.market_type -and $_.PSObject.Properties['side'] -and -not $futPos.market.Contains($_.market)) })
        Write-Host "Total registros de CoinEx-GetOpenOrders: $($openOrders.Count)"
        $openOrders | ForEach-Object {
            $mt = if ($_.PSObject.Properties['market_type']) { $_.market_type } else { "?" }
            Write-Host "  $($_.market) market_type=$mt"
        }
    } else {
        Write-Host "CoinEx-GetOpenOrders nao carregado." -ForegroundColor DarkYellow
    }

} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
