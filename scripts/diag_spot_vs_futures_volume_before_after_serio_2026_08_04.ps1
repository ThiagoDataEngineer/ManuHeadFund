# diag_spot_vs_futures_volume_before_after_serio_2026_08_04.ps1 -- ONE-SHOT, so leitura.
#
# Owner notou "nao vi SPOT mais" e pediu pra comparar volume SPOT vs FUTURES
# antes/depois do commit 9434320 (LONG-futures "serio", 2026-08-02 03:41 BRT
# = 06:41 UTC) pra confirmar se a nova rota esta canibalizando SPOT.
#
# Fonte: trailing_state (Supabase) -- registra Mode (GEM/TIER_A/STANDARD) e,
# quando presente, o journal local trailing_positions.json tem marketType
# explicito por posicao. Cruza com CoinEx-GetPendingPositions (FUTURES ao
# vivo) pra classificar marketType real quando o campo journal nao tiver.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")
. (Join-Path $agentsDir "lib_market_type_detector.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG: SPOT vs FUTURES antes/depois do LONG-futures serio (corte 2026-08-02 06:41 UTC) ===" -ForegroundColor Cyan

$cutoff = [datetime]::Parse("2026-08-02T06:41:00Z")

try {
    # trailing_state cobre so posicoes ATIVAS (FUTURES sempre passam por aqui;
    # SPOT tambem, ja que o motor unificado trata os dois). Rows fechadas nao
    # ficam retidas aqui -- olhamos tambem trade_outcomes pra historico mais amplo.
    $activeRows = @(Get-StateRecords -Table "trailing_state" -Filter @{ active = $true })
    Write-Host "trailing_state ativas agora: $($activeRows.Count)"

    $byMarketType = @{}
    foreach ($r in $activeRows) {
        $mt = if ($r.PSObject.Properties['marketType'] -and $r.marketType) { [string]$r.marketType }
              elseif ($r.PSObject.Properties['market_type'] -and $r.market_type) { [string]$r.market_type }
              else { "DESCONHECIDO" }
        if (-not $byMarketType.ContainsKey($mt)) { $byMarketType[$mt] = 0 }
        $byMarketType[$mt]++
    }
    Write-Host "`n--- Posicoes ATIVAS agora, por market_type ---" -ForegroundColor Yellow
    foreach ($k in $byMarketType.Keys) { Write-Host "  $k : $($byMarketType[$k])" }

    # trade_outcomes: historico real de fechamentos, com entry_ts real.
    Write-Host "`n--- trade_outcomes: contagem por dia (antes/depois do corte) ---" -ForegroundColor Yellow
    $outcomes = @(Get-StateRecords -Table "trade_outcomes" -ErrorAction Stop)
    Write-Host "Total trade_outcomes: $($outcomes.Count)"

    $withTs = @($outcomes | ForEach-Object {
        $raw = $_.entry_ts
        $ts = try { if ($raw -is [datetime]) { $raw } else { [datetime]::Parse([string]$raw) } } catch { $null }
        if ($ts) { [PSCustomObject]@{ ts = $ts; symbol = $_.symbol; source = $_.source; direction = $_.direction } }
    } | Where-Object { $_ })

    $before = @($withTs | Where-Object { $_.ts -lt $cutoff -and $_.ts -gt $cutoff.AddDays(-5) })
    $after  = @($withTs | Where-Object { $_.ts -ge $cutoff })

    Write-Host "`nJanela ANTES (5 dias pre-corte, $($cutoff.AddDays(-5).ToString('yyyy-MM-dd HH:mm')) a $($cutoff.ToString('yyyy-MM-dd HH:mm')) UTC): $($before.Count) trades"
    Write-Host "Janela DEPOIS (corte ate agora, $($cutoff.ToString('yyyy-MM-dd HH:mm')) UTC em diante): $($after.Count) trades"

    Write-Host "`n--- ANTES: por source ---" -ForegroundColor Yellow
    $before | Group-Object source | Sort-Object Count -Descending | ForEach-Object { Write-Host "  $($_.Name): $($_.Count)" }

    Write-Host "`n--- DEPOIS: por source ---" -ForegroundColor Yellow
    $after | Group-Object source | Sort-Object Count -Descending | ForEach-Object { Write-Host "  $($_.Name): $($_.Count)" }

    # 2026-08-04: Get-MarketType so diz se o SIMBOLO suporta FUTURES hoje --
    # nao diz se ESTE sistema de fato roteou o trade pra FUTURES ou SPOT
    # naquele momento (Get-RouteForMode pode escolher SPOT mesmo com futures
    # disponivel). Usa como "pode ter sido FUTURES (tem contrato)" vs
    # "SPOT-only (nao tem contrato, garantido SPOT)" -- nao confundir com
    # a rota real escolhida, que so o journal completo saberia.
    if (Get-Command Get-MarketType -ErrorAction SilentlyContinue) {
        Write-Host "`n--- ANTES: symbol tem contrato FUTURES hoje? (proxy, nao e a rota real) ---" -ForegroundColor Yellow
        $beforeByType = @{}
        foreach ($t in $before) {
            try { $mt = Get-MarketType -Market $t.symbol } catch { $mt = "erro" }
            if (-not $beforeByType.ContainsKey($mt)) { $beforeByType[$mt] = 0 }
            $beforeByType[$mt]++
        }
        foreach ($k in $beforeByType.Keys) { Write-Host "  $k : $($beforeByType[$k])" }

        Write-Host "`n--- DEPOIS: symbol tem contrato FUTURES hoje? (proxy, nao e a rota real) ---" -ForegroundColor Yellow
        $afterByType = @{}
        foreach ($t in $after) {
            try { $mt = Get-MarketType -Market $t.symbol } catch { $mt = "erro" }
            if (-not $afterByType.ContainsKey($mt)) { $afterByType[$mt] = 0 }
            $afterByType[$mt]++
        }
        foreach ($k in $afterByType.Keys) { Write-Host "  $k : $($afterByType[$k])" }
    } else {
        Write-Host "`nGet-MarketType nao carregado -- pulando classificacao aproximada." -ForegroundColor DarkYellow
    }

    Write-Host "`n--- Trades individuais DEPOIS do corte (detalhe) ---" -ForegroundColor Yellow
    $after | Sort-Object ts | ForEach-Object {
        Write-Host ("  {0:yyyy-MM-dd HH:mm} {1,-14} dir={2,-6} source={3}" -f $_.ts, $_.symbol, $_.direction, $_.source)
    }

} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
