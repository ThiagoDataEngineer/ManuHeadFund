# diag_mentor_override_cost_benefit_readonly_2026_08_04.ps1 -- ONE-SHOT, so leitura.
#
# Owner pesquisando: journal/MENTOR_OVERRIDE_BUDGET.flag=10 (git-tracked,
# vale em producao real) fez 8 de 18 tentativas de override neste ciclo
# serem negadas so por estourar o teto, sem o Mentor avaliar. Antes de
# decidir se vale subir o budget, precisa saber o custo real por chamada
# (manuheadfund.llm_usage, agent=mentor) pra comparar com o edge medido
# (mce_counterfactual_agg: BEAR|LONG|breadth_long_blocked n=62 hit_rate=
# 67.7%, ~$43/dia projetado com sizing 7% se os 62 sinais fossem
# recuperados via override).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

Write-Host "=== DIAG: custo real do Mentor LLM por chamada (llm_usage) ===" -ForegroundColor Cyan

try {
    $records = @(Get-StateRecords -Table "llm_usage" -Filter @{ agent = "mentor" } -ErrorAction Stop)
    Write-Host "Total registros agent=mentor: $($records.Count)"

    if ($records.Count -eq 0) {
        Write-Host "Sem registros -- tentando sem filtro de agent (todos)" -ForegroundColor Yellow
        $records = @(Get-StateRecords -Table "llm_usage" -ErrorAction Stop)
        Write-Host "Total registros (todos os agents): $($records.Count)"
    }

    if ($records.Count -gt 0) {
        $byModel = @{}
        foreach ($r in $records) {
            $model = if ($r.model) { [string]$r.model } else { "unknown" }
            if (-not $byModel.ContainsKey($model)) {
                $byModel[$model] = [PSCustomObject]@{ calls = 0; cost_sum = 0.0; in_tok = 0; out_tok = 0 }
            }
            $byModel[$model].calls++
            if ($r.cost_usd) { $byModel[$model].cost_sum += [double]$r.cost_usd }
            if ($r.input_tokens) { $byModel[$model].in_tok += [int]$r.input_tokens }
            if ($r.output_tokens) { $byModel[$model].out_tok += [int]$r.output_tokens }
        }

        Write-Host "`n--- Por modelo ---" -ForegroundColor Yellow
        $totalCost = 0.0
        $totalCalls = 0
        foreach ($k in $byModel.Keys) {
            $m = $byModel[$k]
            $avgCost = if ($m.calls -gt 0) { $m.cost_sum / $m.calls } else { 0 }
            Write-Host ("{0,-30} calls={1,-6} custo_total=`${2:N4} custo_medio/call=`${3:N6}" -f $k, $m.calls, $m.cost_sum, $avgCost)
            $totalCost += $m.cost_sum
            $totalCalls += $m.calls
        }

        $avgCostOverall = if ($totalCalls -gt 0) { $totalCost / $totalCalls } else { 0 }
        Write-Host "`nTotal chamadas: $totalCalls | Custo total: `$$([math]::Round($totalCost,4)) | Custo medio/chamada: `$$([math]::Round($avgCostOverall,6))" -ForegroundColor Green

        # Se budget subir de 10 para 20 (dobro), e ciclo roda a cada 5min (288 ciclos/dia)
        $extraCallsPerCycle = 10
        $cyclesPerDay = 288
        $extraCostPerDay = $extraCallsPerCycle * $cyclesPerDay * $avgCostOverall
        Write-Host "`n--- Projecao: se budget subir de 10 para 20 (10 chamadas extras/ciclo) ---" -ForegroundColor Yellow
        Write-Host "Custo extra estimado/dia (assumindo todos os 10 extras SEMPRE usados, $cyclesPerDay ciclos/dia): `$$([math]::Round($extraCostPerDay,2))"
    } else {
        Write-Host "Nenhum registro de custo encontrado em llm_usage." -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERRO ao consultar llm_usage: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
