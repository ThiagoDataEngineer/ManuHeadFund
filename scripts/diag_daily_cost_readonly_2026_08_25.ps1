# diag_daily_cost_readonly_2026_08_25.ps1 -- ONE-SHOT, so leitura.
#
# Owner pediu avaliacao end-to-end do custo diario do sistema. Get-CostSummary
# ja existe (lib_cost_tracker.ps1) e cobre custo de LLM real (Claude/Groq/
# Mistral/Cerebras via manuheadfund.llm_usage) -- este script consolida com
# taxas de trading reais (CoinEx) e reporta os 2 lados do custo operacional.
#
# NAO cobre (fora do escopo de dado disponivel): custo de infra GitHub Actions
# (minutos de runner -- plano do owner determina se e gratuito/pago),
# Supabase (plano determina custo fixo mensal, nao por uso).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")
. (Join-Path $agentsDir "lib_cost_tracker.ps1")

Write-Host "=== DIAG: CUSTO DIARIO END-TO-END (READ-ONLY) ===" -ForegroundColor Cyan

Write-Host "`n--- [1] Custo LLM (Get-CostSummary, dado real Supabase llm_usage) ---" -ForegroundColor Yellow
try {
    $cost = Get-CostSummary
    Write-Host "Hoje (24h): `$$($cost.today) ($($cost.todayCalls) calls)"
    Write-Host "Semana (7d): `$$($cost.week) ($($cost.weekCalls) calls)"
    Write-Host "Mes (30d): `$$($cost.month) ($($cost.monthCalls) calls)"
    Write-Host "Total historico: `$$($cost.total)"
    Write-Host "Projecao mensal (baseado nos ultimos 7d): `$$($cost.projectedMonthly)"
    Write-Host "`nPor agente:"
    if ($cost.byAgent -and $cost.byAgent.Count -gt 0) {
        foreach ($kv in ($cost.byAgent.GetEnumerator() | Sort-Object -Property Value -Descending)) {
            Write-Host "  $($kv.Key): `$$([math]::Round($kv.Value,4))"
        }
    } else {
        Write-Host "  (sem dados por agente)"
    }
} catch {
    Write-Host "ERRO em Get-CostSummary: $_" -ForegroundColor Red
}

Write-Host "`n--- [2] Taxas de trading FUTURES (via finished-order, que carrega a taxa real por execucao) ---" -ForegroundColor Yellow
try {
    $futPos = CoinEx-Get "/v2/futures/pending-position?market_type=FUTURES"
    $futMarkets = @()
    if ($futPos.code -eq 0) {
        $futMarkets = @($futPos.data | ForEach-Object { $_.market } | Select-Object -Unique)
    }
    $totalFeeFut = 0.0
    $countFut = 0
    $windowStart = (Get-Date).AddDays(-1)
    $totalFeeFut24h = 0.0
    $countFut24h = 0
    $__schemaShown = $false
    foreach ($mkt in $futMarkets) {
        try {
            $r = CoinEx-Get "/v2/futures/finished-order?market=$mkt&market_type=FUTURES&page=1&limit=50"
            if ($r.code -ne 0) {
                Write-Host "  ${mkt}: finished-order code=$($r.code) message=$($r.message)" -ForegroundColor DarkYellow
                continue
            }
            if (-not $__schemaShown -and @($r.data).Count -gt 0) {
                Write-Host "  [schema real de 1 registro finished-order]:"
                ($r.data[0] | ConvertTo-Json -Compress) | Write-Host
                $__schemaShown = $true
            }
            foreach ($p in @($r.data)) {
                $fee = if ($p.PSObject.Properties['deal_fee']) { [double]$p.deal_fee }
                       elseif ($p.PSObject.Properties['fee']) { [double]$p.fee }
                       else { 0.0 }
                $totalFeeFut += $fee
                $countFut++
                $tsField = if ($p.PSObject.Properties['updated_at']) { $p.updated_at } elseif ($p.PSObject.Properties['create_time']) { $p.create_time } else { 0 }
                $updatedAt = try { [datetimeoffset]::FromUnixTimeMilliseconds([long]$tsField).UtcDateTime } catch { $null }
                if ($updatedAt -and $updatedAt -ge $windowStart) {
                    $totalFeeFut24h += $fee
                    $countFut24h++
                }
            }
        } catch {}
    }
    Write-Host "Taxas FUTURES (todos os mercados com posicao aberta agora, historico finished-order): `$$([math]::Round($totalFeeFut,4)) em $countFut ordens"
    Write-Host "Taxas FUTURES ultimas 24h: `$$([math]::Round($totalFeeFut24h,4)) em $countFut24h fechamentos"
} catch {
    Write-Host "ERRO ao calcular taxas futures: $_" -ForegroundColor Red
}

Write-Host "`n--- [3] Capital total (referencia pra % de custo sobre patrimonio) ---" -ForegroundColor Yellow
try {
    if (Get-Command CoinEx-GetTotalCapitalUSDT -ErrorAction SilentlyContinue) {
        $totalCap = CoinEx-GetTotalCapitalUSDT
        Write-Host "Capital total (spot+futures): `$$totalCap"
    }
} catch {
    Write-Host "ERRO ao buscar capital: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
