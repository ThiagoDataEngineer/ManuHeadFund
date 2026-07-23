# lib_portfolio_rebalance.ps1 -- Rebalanceamento de carteira ASSET-LEVEL (puro + gate).
#
# 2026-06-17 (#3): diferente de lib_rebalancing_daemon (wallet SPOT<->FUTURES, dead code),
# este computa acoes de COMPRA/VENDA por ATIVO para voltar aos pesos-alvo.
#
# Filosofia (alinhada ao CLAUDE.md):
#   - Fungibilidade total: todos os ativos sao tratados igualmente pra compra/venda.
#     Se quer fazer HODL de um ativo (ex: BTC long-term), coloca em carteira separada.
#   - Banda de drift: so age se |peso_atual - peso_alvo| > BandPct (evita churn + fees).
#   - Filtro de poeira: ignora trades < MinTradeUsd.
#   - Regra de ouro #8: execucao DESLIGADA por padrao (opt-in via flag).
# Funcoes de calculo sao PURAS (testaveis sem rede). Execucao real fica separada.

# ─────────────────────────────────────────────────────────────────────────────
# Get-PortfolioWeights (PURA) -- holdings[] {asset, value_usd} -> hashtable peso fracionario.
# ─────────────────────────────────────────────────────────────────────────────
function Get-PortfolioWeights {
    param([object[]]$Holdings)
    $w = @{}
    if (-not $Holdings -or @($Holdings).Count -eq 0) { return $w }
    $total = 0.0
    foreach ($h in $Holdings) { if ($h) { $total += [double]$h.value_usd } }
    if ($total -le 0) { return $w }
    foreach ($h in $Holdings) {
        if (-not $h) { continue }
        $w["$($h.asset)"] = [double]$h.value_usd / $total
    }
    return $w
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-RebalanceActions (PURA) -- calcula acoes BUY/SELL para voltar aos alvos.
#
# Holdings:   array {asset, value_usd}
# Targets:    hashtable asset->fracao alvo (0..1). Ativo ausente = alvo 0 (vender tudo).
# BandPct:    so age se |drift| (em pontos %) > BandPct.
# MinTradeUsd:ignora trades menores (poeira).
# CoreAssets: ativos protegidos de venda (DEIXAR VAZIO por padrao). Se quer HODL um ativo,
#             coloca em carteira separada — eh mais limpo que protege-lo aqui.
#
# Retorna: array {asset, action(BUY/SELL), amount_usd, current_pct, target_pct, drift_pct, reason}
#          ordenado SELL primeiro (vendas financiam compras).
# ─────────────────────────────────────────────────────────────────────────────
function Get-RebalanceActions {
    param(
        [object[]]$Holdings,
        [hashtable]$Targets,
        [double]$BandPct = 5,
        [double]$MinTradeUsd = 10,
        [string[]]$CoreAssets = @()
    )
    if (-not $Holdings -or @($Holdings).Count -eq 0) { return @() }
    if (-not $Targets) { $Targets = @{} }

    $total = 0.0
    $valById = @{}
    foreach ($h in $Holdings) {
        if (-not $h) { continue }
        $a = "$($h.asset)"
        $v = [double]$h.value_usd
        $valById[$a] = $v
        $total += $v
    }
    if ($total -le 0) { return @() }

    # Universo = ativos presentes + ativos alvo (p/ comprar o que falta)
    $universe = @{}
    foreach ($k in $valById.Keys)  { $universe[$k] = $true }
    foreach ($k in $Targets.Keys)  { $universe[$k] = $true }

    $actions = @()
    foreach ($asset in $universe.Keys) {
        $cur   = if ($valById.ContainsKey($asset)) { $valById[$asset] } else { 0.0 }
        $tgtW  = if ($Targets.ContainsKey($asset)) { [double]$Targets[$asset] } else { 0.0 }
        $curW  = $cur / $total
        $driftW = $curW - $tgtW                 # >0 = sobrealocado
        $driftPct = $driftW * 100
        $driftUsd = $driftW * $total

        if ([math]::Abs($driftPct) -le $BandPct) { continue }       # dentro da banda
        if ([math]::Abs($driftUsd) -lt $MinTradeUsd) { continue }   # poeira

        $action = if ($driftUsd -gt 0) { "SELL" } else { "BUY" }

        # BTC-core: nunca vende ativo core abaixo do alvo
        if ($action -eq "SELL" -and ($CoreAssets -contains $asset)) { continue }

        $actions += [PSCustomObject]@{
            asset       = $asset
            action      = $action
            amount_usd  = [math]::Round([math]::Abs($driftUsd), 2)
            current_pct = [math]::Round($curW * 100, 2)
            target_pct  = [math]::Round($tgtW * 100, 2)
            drift_pct   = [math]::Round($driftPct, 2)
            reason      = "drift $([math]::Round($driftPct,1))% > banda ${BandPct}%"
        }
    }

    # SELL primeiro (financia BUYs)
    return @($actions | Sort-Object @{Expression={ if ($_.action -eq "SELL") {0} else {1} }}, @{Expression="amount_usd";Descending=$true})
}

# ─────────────────────────────────────────────────────────────────────────────
# Format-RebalancePlan (PURA) -- plano legivel p/ humano/Telegram.
# ─────────────────────────────────────────────────────────────────────────────
function Format-RebalancePlan {
    param([object[]]$Actions)
    if (-not $Actions -or @($Actions).Count -eq 0) { return "Carteira equilibrada — nenhuma acao." }
    $lines = @("<b>PLANO DE REBALANCEAMENTO</b>")
    foreach ($a in $Actions) {
        $icon = if ($a.action -eq "SELL") { "🔴" } else { "🟢" }
        $lines += "$icon $($a.action) `$$($a.amount_usd) $($a.asset) (atual $($a.current_pct)% -> alvo $($a.target_pct)%)"
    }
    return ($lines -join "`n")
}

# ─────────────────────────────────────────────────────────────────────────────
# Test-RebalanceEnabled (gate) -- execucao OPT-IN. Regra de ouro: fail-closed.
# ─────────────────────────────────────────────────────────────────────────────
function Test-RebalanceEnabled {
    param(
        [string]$FlagPath = $(
            $base = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path $PSScriptRoot ".." "journal" }
            Join-Path $base "REBALANCE_ENABLED.flag"
        )
    )
    if ($null -ne $global:REBALANCE_ENABLED) { return [bool]$global:REBALANCE_ENABLED }
    return (Test-Path $FlagPath)
}
