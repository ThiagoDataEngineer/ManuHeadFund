# diag_babydoge_entry_origin_2026_07_20.ps1 -- diagnostico ONE-SHOT, so leitura
#
# BABYDOGEUSDT foi comprado de forma 100% autonoma pelo sistema (confirmado
# pelo usuario -- nao foi manual), mas os journals LOCAIS mostram 45 vetos
# do gate FQS/TIER_B_PAPER em 04-05/07 sem nenhuma aprovacao registrada.
# Journals locais estao desatualizados desde 08/07 -- este job busca nas
# fontes REAIS da nuvem (Supabase) qualquer rastro de como/quando essa
# entrada aconteceu, pra achar o caminho de codigo que contornou o gate FQS.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

Write-Host "=== DIAG BABYDOGE ENTRY ORIGIN (READ-ONLY) ===" -ForegroundColor Cyan
Write-Host ""

# [1] Historico real de ordens BABYDOGEUSDT na CoinEx -- quando comprou, que tipo de ordem.
Write-Host "[1] Historico real de ordens SPOT BABYDOGEUSDT (CoinEx direto)" -ForegroundColor Yellow
try {
    $r = CoinEx-Get "/v2/spot/finished-order?market=BABYDOGEUSDT&market_type=SPOT&page=1&limit=50" -EA Stop
    if ($r.code -eq 0 -and $r.data.Count -gt 0) {
        Write-Host "  $($r.data.Count) ordem(ns) encontrada(s):" -ForegroundColor White
        foreach ($o in ($r.data | Sort-Object created_at)) {
            $ts = try { [datetimeoffset]::FromUnixTimeMilliseconds([long]$o.created_at).UtcDateTime } catch { $null }
            Write-Host "    $($ts.ToString('yyyy-MM-dd HH:mm:ss')) UTC | side=$($o.side) type=$($o.type) price=$($o.price) filled_amount=$($o.filled_amount) filled_value=$($o.filled_value) client_id=$($o.client_id)"
        }
    } else {
        Write-Host "  code=$($r.code) msg=$($r.message) -- sem ordens ou erro" -ForegroundColor DarkYellow
    }
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# [2] trade_rejections no Supabase -- BABYDOGE tambem foi vetado la, ou so localmente?
Write-Host "[2] trade_rejections (Supabase) -- historico de vetos reais pra BABYDOGE" -ForegroundColor Yellow
try {
    $rej = @(Get-StateRecords -Table "trade_rejections" -ErrorAction Stop)
    $babyRej = @($rej | Where-Object { "$($_.market)" -like "*BABYDOGE*" })
    Write-Host "  Total trade_rejections: $($rej.Count) | BABYDOGE: $($babyRej.Count)" -ForegroundColor White
    foreach ($b in ($babyRej | Sort-Object ts)) {
        Write-Host "    $($b.ts) | gate=$($b.gate) | regime=$($b.regime) | entry_price=$($b.entry_price)"
    }
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# [3] trade_outcomes (Supabase) -- ha ALGUM registro de BABYDOGE, mesmo sem PnL?
Write-Host "[3] trade_outcomes (Supabase) -- registro de entrada BABYDOGE" -ForegroundColor Yellow
try {
    $outcomes = @(Get-StateRecords -Table "trade_outcomes" -ErrorAction Stop)
    $babyOut = @($outcomes | Where-Object { "$($_.market)" -like "*BABYDOGE*" })
    Write-Host "  Total trade_outcomes: $($outcomes.Count) | BABYDOGE: $($babyOut.Count)" -ForegroundColor White
    foreach ($b in $babyOut) {
        Write-Host "    closed_at=$($b.closed_at) source=$($b.source) mode=$($b.mode) entry=$($b.entry) status=$($b.status)"
    }
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# [4] trailing_positions (Supabase) -- BABYDOGE esta/esteve registrado com qual source/mode?
Write-Host "[4] trailing_positions (Supabase) -- registro de trailing pra BABYDOGE" -ForegroundColor Yellow
try {
    $tp = @(Get-StateRecords -Table "trailing_positions" -ErrorAction Stop)
    $babyTp = @($tp | Where-Object { "$($_.market)" -like "*BABYDOGE*" })
    Write-Host "  Total trailing_positions: $($tp.Count) | BABYDOGE: $($babyTp.Count)" -ForegroundColor White
    foreach ($b in $babyTp) {
        Write-Host "    market=$($b.market) source=$($b.source) mode=$($b.mode) entry=$($b.entry) active=$($b.active) openedAt=$($b.openedAt)"
    }
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# [5] gem_candidates ou fqs_enrichment_queue -- BABYDOGE apareceu como candidato aprovado em algum ponto?
Write-Host "[5] Outras tabelas relevantes (gems_candidates, fqs_enrichment_queue) se existirem" -ForegroundColor Yellow
foreach ($tbl in @("gems_candidates", "fqs_enrichment_queue")) {
    try {
        $rows = @(Get-StateRecords -Table $tbl -ErrorAction Stop)
        $babyRows = @($rows | Where-Object { "$($_.market)" -like "*BABYDOGE*" -or "$($_.ccy)" -like "*BABYDOGE*" })
        Write-Host "  [$tbl] total=$($rows.Count) BABYDOGE=$($babyRows.Count)" -ForegroundColor White
        foreach ($b in $babyRows) { Write-Host "    $($b | ConvertTo-Json -Compress -Depth 3)" }
    } catch {
        Write-Host "  [$tbl] erro ou tabela ausente: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

Write-Host ""
Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
