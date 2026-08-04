# diag_why_spot_not_entering_2026_08_04.ps1 -- ONE-SHOT, so leitura.
#
# Owner perguntou "porque spot nao esta entrando". Get-RouteForMode so
# prefere SPOT quando Mode="GEM" -- as 11 posicoes atuais sao todas
# FUTURES (10 SHORT estruturalmente FUTURES-only + 1 LONG promovida por
# FQS). Investiga se candidatos GEM (Mode=GEM, o unico caminho que
# preferiria SPOT) estao aparecendo no scan de hoje, e se sim, onde estao
# sendo bloqueados antes de chegar no roteamento.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG: por que SPOT nao esta entrando ===" -ForegroundColor Cyan

# [1] Posicoes SPOT reais AGORA na corretora (holdings, nao so trailing_state)
Write-Host "`n[1] SPOT holdings reais na CoinEx AGORA" -ForegroundColor Yellow
try {
    if (Get-Command CoinEx-GetOpenOrders -ErrorAction SilentlyContinue) {
        $openOrders = @(CoinEx-GetOpenOrders -MinValueUSD 3.0)
        $futPos = @(CoinEx-GetPendingPositions) | ForEach-Object { $_.market }
        $spotOnly = @($openOrders | Where-Object { $_.market -notin $futPos })
        Write-Host "Total holdings (todos): $($openOrders.Count) | Provavel SPOT-only (fora de FUTURES): $($spotOnly.Count)"
        $spotOnly | ForEach-Object { Write-Host "  $($_.market)" }
    }
} catch { Write-Host "ERRO: $_" -ForegroundColor Red }

# [2] trade_rejections: candidatos bloqueados HOJE, com gate (schema real:
# ts/market/direction/gate/entry_price/regime/source -- NAO tem coluna
# "reason"/"mode" dedicada, "gate" carrega o texto livre com o motivo).
Write-Host "`n[2] trade_rejections das ultimas 24h (por gate)" -ForegroundColor Yellow
try {
    $rejections = @(Get-StateRecords -Table "trade_rejections" -ErrorAction Stop)
    $cutoff = (Get-Date).ToUniversalTime().AddHours(-24)
    $recent = @($rejections | Where-Object {
        $raw = $_.ts
        if (-not $raw) { return $false }
        $ts = try { if ($raw -is [datetime]) { $raw } else { [datetime]::Parse([string]$raw) } } catch { $null }
        $ts -and $ts -gt $cutoff
    })
    Write-Host "Total rejections (todas): $($rejections.Count) | ultimas 24h: $($recent.Count)"
    $recent | Group-Object { $_.source } | Sort-Object Count -Descending | Select-Object -First 15 | ForEach-Object {
        Write-Host ("  source={0,-25} count={1}" -f $_.Name, $_.Count)
    }
} catch { Write-Host "ERRO ou tabela ausente: $_" -ForegroundColor Red }

# [3] Quantos desses rejections eram candidatos GEM especificamente (source contem "gem")
Write-Host "`n[3] Rejections com source contendo 'gem' ultimas 24h" -ForegroundColor Yellow
try {
    $gemRej = @($recent | Where-Object { "$($_.source)" -match "(?i)gem" })
    Write-Host "Total: $($gemRej.Count)"
    $gemRej | Select-Object -First 20 | ForEach-Object {
        Write-Host ("  {0} market={1} dir={2} gate={3}" -f $_.ts, $_.market, $_.direction, $_.gate)
    }
} catch { Write-Host "ERRO: $_" -ForegroundColor Red }

# [4] trailing_state: quando foi a ULTIMA vez que algo abriu com mode=GEM
Write-Host "`n[4] Ultima posicao mode=GEM (ativa ou nao) no trailing_state" -ForegroundColor Yellow
try {
    $allTrailing = @(Get-StateRecords -Table "trailing_state" -ErrorAction Stop)
    $gemPositions = @($allTrailing | Where-Object { "$($_.mode)" -eq "GEM" })
    Write-Host "Total registros mode=GEM (todos, ativos+fechados): $($gemPositions.Count)"
    $withTs = @($gemPositions | ForEach-Object {
        $raw = $_.openedAt
        $ts = try { if ($raw -is [datetime]) { $raw } else { [datetime]::Parse([string]$raw) } } catch { $null }
        if ($ts) { [PSCustomObject]@{ market = $_.market; ts = $ts; active = $_.active } }
    } | Sort-Object ts -Descending)
    $withTs | Select-Object -First 5 | ForEach-Object {
        Write-Host ("  {0} {1} active={2}" -f $_.ts, $_.market, $_.active)
    }
    if ($withTs.Count -eq 0) { Write-Host "  NENHUM registro mode=GEM encontrado no trailing_state." -ForegroundColor Red }
} catch { Write-Host "ERRO: $_" -ForegroundColor Red }

# [5] mce_counterfactual_agg: sinais GEM bloqueados que teriam dado lucro (edge perdido)
Write-Host "`n[5] Candidatos GEM vetados recentemente (log do dia, se existir)" -ForegroundColor Yellow
try {
    $logsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "logs"
    $todayLog = Join-Path $logsDir ("master_{0}.log" -f (Get-Date).ToString('yyyyMMdd'))
    if (Test-Path $todayLog) {
        $gemLines = Select-String -Path $todayLog -Pattern "BLOQUEADO|\[Route\]" -ErrorAction SilentlyContinue | Select-Object -Last 30
        $gemLines | ForEach-Object { Write-Host "  $($_.Line)" }
    } else {
        Write-Host "  Log de hoje nao encontrado em $todayLog (execucao local nao tem os logs do cloud)."
    }
} catch { Write-Host "ERRO: $_" -ForegroundColor Red }

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
