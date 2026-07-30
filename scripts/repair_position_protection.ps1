# scripts\repair_position_protection.ps1
# REPARO IMEDIATO: garante TP/SL real na corretora para posicoes abertas sem protecao.
# Causa raiz: SL/TP embutido em ordem MARKET nao aplica confiavel na CoinEx V2.
# Uso:
#   # Audita todas as posicoes (somente leitura):
#   powershell -File scripts\repair_position_protection.ps1 -AuditOnly
#
#   # Conserta INJUSDT com trailing habilitado:
#   powershell -File scripts\repair_position_protection.ps1 -Market INJUSDT -EnableTrailing
#
#   # Conserta INJUSDT com SL/TP explicitos:
#   powershell -File scripts\repair_position_protection.ps1 -Market INJUSDT -StopLoss 5.70 -TakeProfit 8.50
#
#   # Conserta TODAS as posicoes desprotegidas (SL/TP calculados do entry):
#   powershell -File scripts\repair_position_protection.ps1 -All

[CmdletBinding()]
param(
    [string] $Market = "",
    [double] $StopLoss = 0,
    [double] $TakeProfit = 0,
    [double] $StopPct = 0.08,      # 8% padrao p/ recalcular SL do entry (LONG)
    [double] $TargetPct = 0.32,    # 32% padrao p/ recalcular TP do entry (LONG)
    [switch] $EnableTrailing,
    [switch] $AuditOnly,
    [switch] $All
)

$ErrorActionPreference = "Stop"

# ── Bootstrap ────────────────────────────────────────────────────────────────
$projectRoot = Split-Path -Parent $PSScriptRoot
$agentsDir   = Join-Path $projectRoot "agents"

$configLocal = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocal) { . $configLocal }

. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_coinex_position_management.ps1")
. (Join-Path $agentsDir "lib_order_validation.ps1")
. (Join-Path $agentsDir "lib_trailing_stop_intelligent.ps1")  # Get-StructuralStopTarget (SL/TP por suporte/resistencia)
. (Join-Path $agentsDir "lib_position_protection.ps1")
$telegramLib = Join-Path $agentsDir "lib_telegram.ps1"
if (Test-Path $telegramLib) { . $telegramLib }

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path $projectRoot "journal"
}

Write-Host ""
Write-Host ("=" * 72)
Write-Host " REPARO DE PROTECAO DE POSICAO (TP/SL real na corretora)"
Write-Host ("=" * 72)

# ── 1. AUDITORIA ───────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[1] Auditando posicoes abertas..."
$audit = Test-AllPositionsProtected

if (-not $audit -or @($audit).Count -eq 0) {
    Write-Host "    Nenhuma posicao aberta encontrada."
    exit 0
}

foreach ($p in $audit) {
    $slTxt = if ($p.has_sl) { "SL=$($p.sl_price)" } else { "SL=AUSENTE" }
    $tpTxt = if ($p.has_tp) { "TP=$($p.tp_price)" } else { "TP=AUSENTE" }
    $flag  = if ($p.protected) { "[OK]" } else { "[DESPROTEGIDA]" }
    $color = if ($p.protected) { "Green" } else { "Red" }
    Write-Host ("    {0} {1} {2} entry={3} {4} {5} liq={6}" -f `
        $flag, $p.market, $p.side, $p.entry, $slTxt, $tpTxt, $p.liq_price) -ForegroundColor $color
}

$unprotected = @($audit | Where-Object { -not $_.protected })
Write-Host ""
Write-Host "    Total: $(@($audit).Count) posicao(oes) | Desprotegidas: $($unprotected.Count)"

if ($AuditOnly) {
    Write-Host ""
    Write-Host "[AuditOnly] Nenhuma alteracao feita."
    exit 0
}

# ── 2. REPARO ────────────────────────────────────────────────────────────────
$targets = @()
if ($All) {
    $targets = $unprotected | ForEach-Object { $_.market }
} elseif ($Market) {
    $targets = @($Market)
} else {
    Write-Host ""
    Write-Host "Nada a reparar. Use -Market <PAR>, -All, ou -AuditOnly." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "[2] Reparando: $($targets -join ', ')"

$repairResults = @()
foreach ($mkt in $targets) {
    Write-Host ""
    Write-Host "    -> $mkt"
    $r = Repair-PositionProtection -Market $mkt `
            -StopLoss $StopLoss -TakeProfit $TakeProfit `
            -StopPct $StopPct -TargetPct $TargetPct `
            -EnableTrailing ([bool]$EnableTrailing)
    $repairResults += $r

    if ($r.success) {
        Write-Host ("       [OK] entry={0} SL={1} TP={2} trailing={3}" -f `
            $r.entry, $r.stop_loss, $r.take_profit, $r.trailing_armed) -ForegroundColor Green
    } else {
        Write-Host ("       [FALHOU] motivo={0} sl_set={1} tp_set={2}" -f `
            $r.reason, $r.sl_set, $r.tp_set) -ForegroundColor Red
    }
}

# ── 3. RE-VALIDACAO ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[3] Re-validando na corretora..."
$audit2 = Test-AllPositionsProtected
foreach ($mkt in $targets) {
    $p = $audit2 | Where-Object { $_.market -eq $mkt } | Select-Object -First 1
    if ($p) {
        $flag  = if ($p.protected) { "[OK]" } else { "[AINDA DESPROTEGIDA]" }
        $color = if ($p.protected) { "Green" } else { "Red" }
        Write-Host ("    {0} {1} SL={2} TP={3}" -f $flag, $p.market, $p.sl_price, $p.tp_price) -ForegroundColor $color
    }
}

Write-Host ""
$okCount = @($repairResults | Where-Object { $_.success }).Count
Write-Host ("RESULTADO: {0}/{1} reparada(s) com sucesso" -f $okCount, @($repairResults).Count)
Write-Host ("=" * 72)

if ($okCount -lt @($repairResults).Count) { exit 1 }
exit 0
