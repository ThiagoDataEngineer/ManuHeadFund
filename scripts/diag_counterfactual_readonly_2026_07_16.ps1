# diag_counterfactual_readonly_2026_07_16.ps1 -- diagnostico ONE-SHOT, so leitura
# Responde: os sinais que o sistema PULOU (breadth/score/tori/quality gate)
# teriam dado edge positivo se tivessem entrado? Usa mce_counterfactual_agg
# (agregado regime|direction, ja calculado por outro job de aprendizado) e
# decision_grades_agg (calibracao LLM: quantas vezes a decisao de BLOCK
# estava certa vs errada). NAO envia nenhuma ordem, so consulta Supabase.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

Write-Host "=== DIAG COUNTERFACTUAL (READ-ONLY) ===" -ForegroundColor Cyan
Write-Host ""

# === mce_counterfactual_agg: "e se tivesse entrado?" por regime|direction ===
Write-Host "[1] mce_counterfactual_agg (edge dos sinais pulados, por regime|direction)" -ForegroundColor Yellow
try {
    $cf = @(Get-StateRecords -Table "mce_counterfactual_agg" -ErrorAction Stop)
    if ($cf.Count -eq 0) {
        Write-Host "  (vazio -- sem dados ainda)" -ForegroundColor DarkYellow
    } else {
        $cf | Sort-Object -Property n -Descending | ForEach-Object {
            $hr = if ($_.hit_rate) { [Math]::Round([double]$_.hit_rate * 100, 1) } else { 0 }
            $f24 = if ($_.avg_fwd_24h) { [Math]::Round([double]$_.avg_fwd_24h, 2) } else { 0 }
            $f72 = if ($_.avg_fwd_72h) { [Math]::Round([double]$_.avg_fwd_72h, 2) } else { 0 }
            Write-Host "  $($_.group): n=$($_.n) hit_rate=$hr% avg_fwd_24h=$f24% avg_fwd_72h=$f72%" -ForegroundColor White
        }
    }
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# === decision_grades_agg: calibracao das decisoes de BLOCK/ENTER ===
Write-Host "[2] decision_grades_agg (acuracia das decisoes, por decision|direction|regime)" -ForegroundColor Yellow
try {
    $dg = @(Get-StateRecords -Table "decision_grades_agg" -ErrorAction Stop)
    if ($dg.Count -eq 0) {
        Write-Host "  (vazio -- sem dados ainda)" -ForegroundColor DarkYellow
    } else {
        $dg | Sort-Object -Property n -Descending | Select-Object -First 20 | ForEach-Object {
            $acc = if ($_.correct_rate) { [Math]::Round([double]$_.correct_rate * 100, 1) } else { 0 }
            $mv = if ($_.avg_move_dir) { [Math]::Round([double]$_.avg_move_dir, 2) } else { 0 }
            Write-Host "  $($_.key): n=$($_.n) correct_rate=$acc% avg_move_dir=$mv%" -ForegroundColor White
        }
    }
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# === trade_rejections: rejeicoes recentes com motivo (amostra) ===
Write-Host "[3] trade_rejections (amostra recente, se tabela existir)" -ForegroundColor Yellow
try {
    $rej = @(Get-StateRecords -Table "trade_rejections" -ErrorAction Stop)
    Write-Host "  Total registros: $($rej.Count)" -ForegroundColor White
    if ($rej.Count -gt 0) {
        $rej | Select-Object -Last 10 | ForEach-Object {
            Write-Host "  $($_.ts) $($_.market) $($_.direction) gate=$($_.gate)" -ForegroundColor Gray
        }
    }
} catch {
    Write-Host "  ERRO ou tabela ausente: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
