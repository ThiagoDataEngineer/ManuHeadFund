# diag_trade_outcomes_schema_readonly_2026_07_20.ps1 -- diagnostico ONE-SHOT
#
# Confirma se pnl_percent/pnl_realized EXISTEM de verdade na tabela real
# manuheadfund.trade_outcomes -- achado de investigacao: nenhum ALTER TABLE
# no repo criou essas colunas, so o codigo (ConvertTo-SupabaseOutcome,
# commit 80cecfd) passou a tentar grava-las. Se a coluna nao existe, o
# insert falha com PGRST204 e cai no catch (so Write-Warning, nao bloqueia)
# -- silencioso, mesmo padrao que ja corrigimos 2x nesta sessao.
#
# Read-only (sobre o schema -- faz 1 insert/delete de teste isolado,
# id proprio, sempre limpo no final, pra confirmar existencia real das
# colunas sem depender de RPC exec_sql, que nao existe neste repo).

$agentsDir = Join-Path $PSScriptRoot ".." "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

Write-Host "=== DIAG TRADE_OUTCOMES SCHEMA (READ-ONLY) ===" -ForegroundColor Cyan
Write-Host ""

# [1] Idade dos 20 registros -- sao todos anteriores ao fix (80cecfd, ~2026-07-19 02:34 BRT)?
Write-Host "[1] Idade dos registros existentes" -ForegroundColor Yellow
try {
    $outcomes = @(Get-StateRecords -Table "trade_outcomes" -ErrorAction Stop)
    Write-Host "  Total: $($outcomes.Count)" -ForegroundColor White
    $fixCommitTime = [datetime]::Parse("2026-07-19T05:34:00Z")
    foreach ($o in ($outcomes | Sort-Object closed_at -Descending | Select-Object -First 25)) {
        $ts = try { [datetime]::Parse([string]$o.closed_at) } catch { $null }
        $marker = if ($ts -and $ts -gt $fixCommitTime) { "[POS-FIX]" } else { "[pre-fix]" }
        Write-Host "  $marker closed_at=$($o.closed_at) market=$($o.market) pnl_percent=$($o.pnl_percent) pnl_realized=$($o.pnl_realized)"
    }
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# [2] Teste de escrita/leitura direto -- se pnl_percent/pnl_realized nao
# existem na tabela real, o PostgREST rejeita o INSERT inteiro (PGRST204),
# confirmando a hipotese sem depender de RPC exec_sql (nao existe no repo).
Write-Host "[2] Teste de escrita/leitura direto (confirma existencia real das colunas)" -ForegroundColor Yellow
try {
    $testId = "DIAG_SCHEMA_TEST_$([guid]::NewGuid().ToString().Substring(0,8))"
    $testRecord = @{
        id = $testId
        market = "DIAGTEST"
        side = "LONG"
        entry = 1.0
        pnl_realized = 12.34
        pnl_percent = 5.67
        closed_at = (Get-Date -Format "o")
        close_reason = "diag_schema_test"
        source = "diag_schema_readonly"
    }
    Save-StateRecords -Table "trade_outcomes" -Records @($testRecord) -PrimaryKey "id" -ErrorAction Stop
    Start-Sleep -Seconds 1
    $readBack = @(Get-StateRecords -Table "trade_outcomes" -Filter @{ id = $testId } -ErrorAction Stop)
    if ($readBack.Count -gt 0) {
        $r = $readBack[0]
        Write-Host "  Escrita/leitura OK. pnl_realized lido=$($r.pnl_realized) pnl_percent lido=$($r.pnl_percent)" -ForegroundColor White
        if ($null -ne $r.pnl_realized -and [double]$r.pnl_realized -eq 12.34 -and $null -ne $r.pnl_percent -and [double]$r.pnl_percent -eq 5.67) {
            Write-Host "  [OK CONFIRMADO] colunas existem e persistem valor real corretamente" -ForegroundColor Green
        } else {
            Write-Host "  [CRITICAL] insert aceito mas pnl_percent/pnl_realized voltaram vazios/diferentes -- colunas provavelmente nao existem, Postgres ignorou campos desconhecidos ou ha outra rota" -ForegroundColor Red
        }
    } else {
        Write-Host "  [WARN] insert nao gerou erro mas leitura de volta nao encontrou o registro (dedup/race?)" -ForegroundColor Yellow
    }
    # Limpeza: remove o registro de teste (nao deixar lixo na tabela real).
    try { Remove-StateRecord -Table "trade_outcomes" -PrimaryKey "id" -Value $testId | Out-Null } catch {
        Write-Host "  [WARN] Falha ao limpar registro de teste $testId -- remover manualmente" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  [CRITICAL] INSERT FALHOU: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Isso confirma a hipotese: colunas pnl_percent/pnl_realized (ou outras no payload) nao existem na tabela real" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
