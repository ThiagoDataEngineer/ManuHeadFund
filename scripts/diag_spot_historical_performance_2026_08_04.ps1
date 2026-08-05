# diag_spot_historical_performance_2026_08_04.ps1 -- ONE-SHOT, so leitura.
#
# Owner disse "estavamos indo muito bem com spot nos ultimos dias" e pediu
# pra CONFIRMAR isso antes de decidir se vale evoluir o radar (achado:
# radar dinamico so cobre FUTURES, 35 moedas SPOT-only ficam invisiveis).
# Explicitamente pediu "nao quebre nada" -- este script e 100% leitura,
# sem nenhuma mudanca de codigo. So historico real de trade_outcomes +
# trailing_state pra SPOT dos ultimos ~7 dias.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG: performance real SPOT ultimos ~7 dias ===" -ForegroundColor Cyan

$cutoff = (Get-Date).ToUniversalTime().AddDays(-7)

# [1] trade_outcomes: fechamentos reais, classificados SPOT vs FUTURES via
# Get-MarketType (proxy: symbol tem contrato futures hoje -- nao e a rota
# exata da epoca, mas indicativo real).
. (Join-Path $agentsDir "lib_market_type_detector.ps1")

Write-Host "`n[1] trade_outcomes fechados (query direta, order=closed_at.desc)" -ForegroundColor Yellow
try {
    $cfg = Get-SupabaseRequestHeaders -Method "GET"
    # 2026-08-05 FIX: coluna real gravada por Add-TradeOutcome/ConvertTo-
    # SupabaseOutcome e closed_at, NAO entry_ts (esse so existe no writer
    # separado lib_trade_journal_supabase.ps1/Save-TradeOutcome). order=
    # numa coluna que nao existe em todas as linhas faz o PostgREST
    # devolver erro -- e Invoke-RestMethod nao lanca em corpo de erro JSON
    # com HTTP 200/4xx tratado como sucesso, entao "Total puxado: 1" era
    # o objeto de erro sendo contado como 1 registro, nao dado real.
    $uri = "$($cfg.url)/rest/v1/trade_outcomes?select=*&order=closed_at.desc&limit=500"
    $rawResp = Invoke-RestMethod -Uri $uri -Method GET -Headers $cfg.headers -TimeoutSec 30
    if ($rawResp -isnot [array] -and $rawResp.PSObject.Properties['message']) {
        Write-Host "  [ERRO PostgREST] $($rawResp.message) (code=$($rawResp.code))" -ForegroundColor Red
        $outcomes = @()
    } else {
        $outcomes = @($rawResp)
    }
    Write-Host "Total puxado: $($outcomes.Count)"

    $recent = @($outcomes | Where-Object {
        $raw = if ($_.PSObject.Properties['closed_at']) { $_.closed_at } else { $_.entry_ts }
        $ts = try { if ($raw -is [datetime]) { $raw } else { [datetime]::Parse([string]$raw) } } catch { $null }
        $ts -and $ts -gt $cutoff
    })
    Write-Host "Ultimos 7 dias: $($recent.Count)"

    $bySpotFut = @{ SPOT = @(); FUTURES = @() }
    foreach ($o in $recent) {
        $mkt = [string]$o.symbol
        $mt = "FUTURES"
        try { $mt = Get-MarketType -Market $mkt } catch {}
        $bySpotFut[$mt] += $o
    }

    Write-Host "`n--- SPOT: $($bySpotFut.SPOT.Count) trades fechados (7d) ---" -ForegroundColor Yellow
    if ($bySpotFut.SPOT.Count -gt 0) {
        $spotPnl = @($bySpotFut.SPOT | ForEach-Object { if ($null -ne $_.pnl_realized) { [double]$_.pnl_realized } })
        $spotWins = @($spotPnl | Where-Object { $_ -gt 0 })
        Write-Host "  Hit rate: $([math]::Round(($spotWins.Count / [math]::Max(1,$spotPnl.Count))*100,1))% ($($spotWins.Count)/$($spotPnl.Count))"
        Write-Host "  PnL total: `$$([math]::Round(($spotPnl | Measure-Object -Sum).Sum,2))"
        Write-Host "  PnL medio/trade: `$$([math]::Round(($spotPnl | Measure-Object -Average).Average,2))"
        $bySpotFut.SPOT | Sort-Object entry_ts -Descending | ForEach-Object {
            Write-Host ("    {0} {1} pnl=`${2}" -f $_.entry_ts, $_.symbol, $_.pnl_realized)
        }
    } else {
        Write-Host "  NENHUM trade SPOT fechado nos ultimos 7 dias." -ForegroundColor Red
    }

    Write-Host "`n--- FUTURES: $($bySpotFut.FUTURES.Count) trades fechados (7d) ---" -ForegroundColor Yellow
    if ($bySpotFut.FUTURES.Count -gt 0) {
        $futPnl = @($bySpotFut.FUTURES | ForEach-Object { if ($null -ne $_.pnl_realized) { [double]$_.pnl_realized } })
        $futWins = @($futPnl | Where-Object { $_ -gt 0 })
        Write-Host "  Hit rate: $([math]::Round(($futWins.Count / [math]::Max(1,$futPnl.Count))*100,1))% ($($futWins.Count)/$($futPnl.Count))"
        Write-Host "  PnL total: `$$([math]::Round(($futPnl | Measure-Object -Sum).Sum,2))"
        Write-Host "  PnL medio/trade: `$$([math]::Round(($futPnl | Measure-Object -Average).Average,2))"
    }
} catch { Write-Host "ERRO: $_" -ForegroundColor Red }

# [2] trailing_state: TODAS as posicoes SPOT (ativas + fechadas) dos ultimos 7 dias
Write-Host "`n[2] trailing_state -- posicoes SPOT (origin.asset_class=SPOT) ultimos 7 dias" -ForegroundColor Yellow
try {
    $cfg2 = Get-SupabaseRequestHeaders -Method "GET"
    $uri2 = "$($cfg2.url)/rest/v1/trailing_state?select=*&order=openedAt.desc&limit=200"
    $rawResp2 = Invoke-RestMethod -Uri $uri2 -Method GET -Headers $cfg2.headers -TimeoutSec 30
    if ($rawResp2 -isnot [array] -and $rawResp2.PSObject.Properties['message']) {
        Write-Host "  [ERRO PostgREST] $($rawResp2.message) (code=$($rawResp2.code))" -ForegroundColor Red
        $allPos = @()
    } else {
        $allPos = @($rawResp2)
    }
    Write-Host "Total puxado: $($allPos.Count)"

    $recentPos = @($allPos | Where-Object {
        $raw = $_.openedAt
        $ts = try { if ($raw -is [datetime]) { $raw } else { [datetime]::Parse([string]$raw) } } catch { $null }
        $ts -and $ts -gt $cutoff
    })
    Write-Host "Ultimos 7 dias (todas, SPOT+FUTURES): $($recentPos.Count)"

    # origin e JSONB -- defensivo contra vir como string crua (PostgREST
    # normalmente ja desserializa objeto aninhado, mas nao confia sem checar).
    $spotPos = @($recentPos | Where-Object {
        $o = $_.origin
        if ($o -is [string]) { try { $o = $o | ConvertFrom-Json } catch { return $false } }
        $o -and $o.asset_class -eq "SPOT"
    })
    Write-Host "`nDas quais SPOT (origin.asset_class=SPOT): $($spotPos.Count)"
    $spotPos | Sort-Object openedAt -Descending | ForEach-Object {
        $status = if ($_.active) { "ATIVA" } else { "fechada ($($_.closeReason))" }
        Write-Host ("  {0} {1} {2} entry={3} status={4}" -f $_.openedAt, $_.market, $_.side, $_.entry, $status)
    }

    # [3] BTC especificamente -- owner pediu direto (BTC existe em SPOT e
    # FUTURES; quer saber se "segurar" BTC em SPOT por alguns dias valeria a
    # pena). Usa origin.asset_class REAL (nao o proxy Get-MarketType, que
    # classificaria BTC como FUTURES sempre por ter contrato -- SEM olhar a
    # rota real escolhida na abertura).
    Write-Host "`n[3] BTCUSDT especificamente -- toda posicao (SPOT ou FUTURES) nos ultimos 7 dias" -ForegroundColor Yellow
    $btcPos = @($recentPos | Where-Object { $_.market -eq "BTCUSDT" })
    Write-Host "Total posicoes BTCUSDT (todas, qualquer origin): $($btcPos.Count)"
    $btcPos | Sort-Object openedAt -Descending | ForEach-Object {
        $o = $_.origin
        if ($o -is [string]) { try { $o = $o | ConvertFrom-Json } catch { $o = $null } }
        $assetClass = if ($o) { $o.asset_class } else { "UNKNOWN" }
        $status = if ($_.active) { "ATIVA" } else { "fechada ($($_.closeReason))" }
        $pnlPct = if ($_.active -and [double]$_.entry -gt 0 -and $_.PSObject.Properties['peak']) {
            "peak=$($_.peak)"
        } else { "" }
        Write-Host ("  {0} {1} side={2} entry={3} asset_class={4} status={5} {6}" -f `
            $_.openedAt, $_.market, $_.side, $_.entry, $assetClass, $status, $pnlPct)
    }
    if ($btcPos.Count -eq 0) {
        Write-Host "  NENHUMA posicao BTCUSDT (SPOT ou FUTURES) nos ultimos 7 dias." -ForegroundColor Red
    }

    # Preco atual BTC pra referencia rapida de quanto teria rendido segurar
    try {
        $btcTicker = CoinEx-GetTicker "BTCUSDT"
        Write-Host "`nPreco BTCUSDT AGORA: $($btcTicker.last)"
    } catch {}

} catch { Write-Host "ERRO: $_" -ForegroundColor Red }

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
