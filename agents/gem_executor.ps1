# gem_executor.ps1 -- Execucao real de gems na CoinEx
# Padrao: FUTURES (isolated margin). Fallback: SPOT quando par nao tem futuros.
# Dot-source: . (Join-Path $PSScriptRoot "gem_executor.ps1")

. (Join-Path $PSScriptRoot "lib_coinex.ps1")
. (Join-Path $PSScriptRoot "lib_journal.ps1")
. (Join-Path $PSScriptRoot "lib_telegram.ps1")
. (Join-Path $PSScriptRoot "lib_gem_safety.ps1")
# 2026-05-21: B9 cache TTL (Add-GemRejection + Test-GemRecentlyRejected).
# Bug encontrado: scan_master dot-sourced gem_executor mas NAO lib_gem_decision_cache,
# entao Get-Command Test-GemRecentlyRejected returnava null silently -> cache check
# nunca firing -> Tori path executando sempre -> custo LLM desperdiçado (PEAQ loop).
$__gemCachePath = Join-Path $PSScriptRoot "lib_gem_decision_cache.ps1"
if (Test-Path $__gemCachePath) { . $__gemCachePath }
# 2026-05-20: Invoke-OrderRouted era codigo morto -- agora wired aqui.
$__orderRoutedPath = Join-Path $PSScriptRoot "lib_order_routed.ps1"
if (Test-Path $__orderRoutedPath) { . $__orderRoutedPath }

# Exit Ladder (Haiku) + Tracker (Agent B). Dot-source defensivo: testes podem
# substituir Get-ExitLadder por mock antes da chamada.
$__ladderPath = Join-Path $PSScriptRoot "lib_exit_ladder.ps1"
if (Test-Path $__ladderPath) { . $__ladderPath }
$__trackerPath = Join-Path $PSScriptRoot "lib_ladder_tracker.ps1"
if (Test-Path $__trackerPath) { . $__trackerPath }

# Carrega tech_agent_ai (provedor de Get-ToriTrendlineSignal) se ainda nao dot-sourced.
if (-not (Get-Command Get-ToriTrendlineSignal -ErrorAction SilentlyContinue)) {
    $__toriPath = Join-Path $PSScriptRoot "tech_agent_ai.ps1"
    if (Test-Path $__toriPath) { . $__toriPath }
}

# 2026-05-21: auto-enqueue FQS para GEMs sem registry (skip se ja registrado/recente).
# Defesa contra gap: gem_executor pode bloquear via Tori ANTES de chamar Mentor,
# entao o enqueue do Mentor nunca dispara. Cobrir aqui.
$__fqsQueuePath = Join-Path $PSScriptRoot "lib_fqs_enrichment_queue.ps1"
if (Test-Path $__fqsQueuePath) { . $__fqsQueuePath }

# 2026-05-23: Position Management - trailing stops automaticos + risk management
$__posManagementPath = Join-Path $PSScriptRoot "lib_coinex_position_management.ps1"
if (Test-Path $__posManagementPath) { . $__posManagementPath }
$__riskManagerPath = Join-Path $PSScriptRoot "lib_position_risk_manager.ps1"
if (Test-Path $__riskManagerPath) { . $__riskManagerPath }

# 2026-05-29: Order validation (retry+fallback SL/TP) + Position protection (garante TP/SL reais).
# Causa raiz corrigida: SL/TP embutido em ordem MARKET nao aplica confiavel na CoinEx V2.
# Solucao: aplicar SL/TP via set-position-* APOS fill + validar + retry.
$__orderValidationPath = Join-Path $PSScriptRoot "lib_order_validation.ps1"
if (Test-Path $__orderValidationPath) { . $__orderValidationPath }
$__posProtectionPath = Join-Path $PSScriptRoot "lib_position_protection.ps1"
if (Test-Path $__posProtectionPath) { . $__posProtectionPath }

# 2026-05-29: Analise de mercado automatica (nossa "AI Analysis" interna,
# multi-timeframe 1h/4h/1d). Enviada no alerta de abertura de trade.
foreach ($__amaDep in @("lib_chart_patterns.ps1","lib_trailing_stop_intelligent.ps1","lib_auto_market_analysis.ps1")) {
    $__amaPath = Join-Path $PSScriptRoot $__amaDep
    if (Test-Path $__amaPath) { . $__amaPath }
}

# ─────────────────────────────────────────────────────────────────────────────
# CoinEx-HasFuturesMarket
# Verifica se o par existe no mercado de futuros da CoinEx
# ─────────────────────────────────────────────────────────────────────────────
function CoinEx-HasFuturesMarket {
    param([string]$Market)
    try {
        $r = Invoke-RestMethod -Uri "$global:COINEX_BASE_URL/v2/futures/market?market=$Market" -Method GET -ErrorAction Stop
        return ($r.code -eq 0 -and $r.data -and $r.data.Count -gt 0)
    } catch { return $false }
}

# NOTA: CoinEx-PlaceSpotOrder e CoinEx-PlaceSpotStopOrder vivem em lib_coinex.ps1
# (movidos para corrigir bug code 3639 "Invalid Parameter" -- exige campo ccy).

# -----------------------------------------------------------------------------
# Calculate-StopTarget
# Funcao pura de calculo stop/target. Resolve bug 2026-05-14 (AIUSDT sub-dollar):
#   - Usa [decimal] para preservar precisao em pares < $1
#   - Serializa com InvariantCulture (evita virgula PT-BR corromper CSV/JSON/API)
#   - Valida invariantes geometricos (target>entry>stop em LONG)
#   - Valida entradas (entry>0, pct em range valido)
#
# Retorna: PSCustomObject { stop_price; target_price; stop_price_str; target_price_str;
#                          stop_pct_actual; target_pct_actual; rr_ratio }
# Lanca excecao em entradas invalidas (fail-fast antes de PlaceOrder).
# -----------------------------------------------------------------------------
function Calculate-StopTarget {
    param(
        [Parameter(Mandatory)] [double] $Entry,
        [Parameter(Mandatory)] [double] $StopPct,
        [Parameter(Mandatory)] [double] $TargetPct,
        [Parameter(Mandatory)] [string] $Direction,   # "LONG" | "SHORT"
        [int] $Precision = 8,
        [double] $MaxDeviationPct = 0.05              # 5% desvio max entre pct config e pct calculado
    )

    # 1. Validacoes de entrada (fail-fast)
    if ($Entry -le 0) {
        throw "Calculate-StopTarget: Entry deve ser > 0 (recebido $Entry)"
    }
    if ($StopPct -le 0 -or $StopPct -ge 1) {
        throw "Calculate-StopTarget: StopPct deve estar em (0,1) (recebido $StopPct -- esperado fracao tipo 0.50 para -50%)"
    }
    if ($TargetPct -le 0) {
        throw "Calculate-StopTarget: TargetPct deve ser > 0 em LONG (recebido $TargetPct)"
    }
    if ($Direction -notin @("LONG","SHORT")) {
        throw "Calculate-StopTarget: Direction deve ser LONG ou SHORT (recebido '$Direction')"
    }

    # 2. Calculo em [decimal] (precisao exata em sub-dollar)
    $entryD  = [decimal]$Entry
    $stopD   = [decimal]$StopPct
    $tgtD    = [decimal]$TargetPct
    $oneD    = [decimal]1

    if ($Direction -eq "LONG") {
        $stopPriceD   = [math]::Round($entryD * ($oneD - $stopD), $Precision)
        $targetPriceD = [math]::Round($entryD * ($oneD + $tgtD),  $Precision)
    } else {
        # SHORT: stop acima, target abaixo
        $stopPriceD   = [math]::Round($entryD * ($oneD + $stopD), $Precision)
        $targetPriceD = [math]::Round($entryD * ($oneD - $tgtD),  $Precision)
    }

    $stopPrice   = [double]$stopPriceD
    $targetPrice = [double]$targetPriceD

    # 3. Invariantes geometricos (defensive double-check)
    if ($Direction -eq "LONG") {
        if ($stopPrice -ge $Entry) {
            throw "Calculate-StopTarget: LONG stop ($stopPrice) >= entry ($Entry) -- INVERTIDO. Abortando."
        }
        if ($targetPrice -le $Entry) {
            throw "Calculate-StopTarget: LONG target ($targetPrice) <= entry ($Entry) -- INVERTIDO. Abortando."
        }
        if ($targetPrice -le $stopPrice) {
            throw "Calculate-StopTarget: LONG target ($targetPrice) <= stop ($stopPrice) -- R:R invalido."
        }
    } else {
        if ($stopPrice -le $Entry)   { throw "Calculate-StopTarget: SHORT stop ($stopPrice) <= entry -- INVERTIDO." }
        if ($targetPrice -ge $Entry) { throw "Calculate-StopTarget: SHORT target ($targetPrice) >= entry -- INVERTIDO." }
    }

    # 4. Desvio efetivo vs configurado (detecta corrupcao de tipos -- ex: string ',' decimal)
    $stopPctActual   = [math]::Abs(($Entry - $stopPrice) / $Entry)
    $targetPctActual = [math]::Abs(($targetPrice - $Entry) / $Entry)
    $stopDeviation   = [math]::Abs($stopPctActual   - $StopPct)
    $targetDeviation = [math]::Abs($targetPctActual - $TargetPct)
    if ($stopDeviation -gt $MaxDeviationPct) {
        throw "Calculate-StopTarget: stop_pct desvio $stopDeviation (configurado=$StopPct, real=$stopPctActual) > max $MaxDeviationPct. Possivel corrupcao."
    }
    if ($targetDeviation -gt ($MaxDeviationPct * $TargetPct + $MaxDeviationPct)) {
        # tolerancia maior em target (escala 2.00 = 200%)
        throw "Calculate-StopTarget: target_pct desvio $targetDeviation (configurado=$TargetPct, real=$targetPctActual) > tolerancia. Possivel corrupcao."
    }

    # 5. Serializacao com InvariantCulture (evita virgula PT-BR corromper API/CSV)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $stopStr   = $stopPrice.ToString($inv)
    $targetStr = $targetPrice.ToString($inv)

    $rrRatio = if ($stopPctActual -gt 0) {
        [math]::Round($targetPctActual / $stopPctActual, 2)
    } else { 0 }

    return [PSCustomObject]@{
        stop_price        = $stopPrice
        target_price      = $targetPrice
        stop_price_str    = $stopStr
        target_price_str  = $targetStr
        stop_pct_actual   = [math]::Round($stopPctActual, 6)
        target_pct_actual = [math]::Round($targetPctActual, 6)
        rr_ratio          = $rrRatio
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-LadderTemplateForSetup
# Decide qual template de exit ladder usar baseado em contexto do setup.
#
# Politica:
#  - GEM FUTURES + spike BULLISH       -> gem_runner (recupera capital + runner)
#  - GEM (qualquer)  + score < 70       -> tori     (conservador, 3 TPs progressivos)
#  - GEM (demais)                       -> tori     (default seguro)
#  - STANDARD regime=BULL_STRONG        -> bull_strong_conservative (RR 1:2 + 1:5)
#  - STANDARD regime=TRANSITION_UP (+Mon)-> melao_kelly (Kelly fracionario 4 TPs)
#  - STANDARD outro                      -> tori (fallback seguro)
#
# Retorna string template_id (validado contra ValidateSet do Get-ExitLadder).
# ─────────────────────────────────────────────────────────────────────────────
function Get-LadderTemplateForSetup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Setup,
        [string] $Regime  = "",
        [bool]   $GemMode = $false,
        [string] $DayOfWeek = ""    # opcional ("Monday"...) p/ TRANSITION_UP rule
    )

    $score      = if ($Setup.PSObject.Properties['score']) { [int]$Setup.score } else { 0 }
    $marketType = if ($Setup.PSObject.Properties['market_type']) { [string]$Setup.market_type } else { "" }
    $spike      = ""
    if ($Setup.PSObject.Properties['vol_data'] -and $Setup.vol_data) {
        if ($Setup.vol_data.PSObject.Properties['spike_type']) {
            $spike = [string]$Setup.vol_data.spike_type
        }
    }

    if ($GemMode) {
        if ($marketType -eq "FUTURES" -and $spike -eq "BULLISH" -and $score -ge 70) {
            return "gem_runner"
        }
        if ($score -lt 70) {
            return "tori"
        }
        return "tori"
    }

    $reg = $Regime.ToUpper()
    if ($reg -eq "BULL_STRONG") {
        return "bull_strong_conservative"
    }
    if ($reg -eq "TRANSITION_UP") {
        return "melao_kelly"
    }
    return "tori"
}

# ─────────────────────────────────────────────────────────────────────────────
# Invoke-GemExecute
# Pipeline: valida gem -> detecta mercado -> sizing -> executa -> stop loss
#
# Uso:
#   Invoke-GemExecute -Gem $gem -DryRun    # simula sem enviar ordem
#   Invoke-GemExecute -Gem $gem            # executa com capital real
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-GemExecute {
    param(
        [Parameter(Mandatory)] [object] $Gem,
        [switch] $DryRun
    )

    $mkt = $Gem.market
    $sz  = $Gem.sizing
    $vd  = $Gem.vol_data

    Write-Host ""
    Write-Host "=== GEM EXECUTOR -- $mkt ===" -ForegroundColor Cyan

    # 2026-05-21: auto-enqueue FQS antes de qualquer block. Garante que GEMs novos
    # (ARRR/PROVE patterns) eventualmente recebem entry no registry mesmo bloqueados.
    if (Get-Command Add-FqsEnrichmentRequest -ErrorAction SilentlyContinue) {
        try { [void](Add-FqsEnrichmentRequest -Market $mkt -Source "gem_executor") } catch {}
    }

    # B9 fix 2026-05-20 PM6+: TTL cache pra evitar re-veto loop.
    # DASH rejeitado 5x hoje com mesmo MCE_BLOCK 0.1823 -> ~$0.03 desperdicio LLM.
    # Skip silencioso se mesma (market, score-block) <60min.
    if (Get-Command Test-GemRecentlyRejected -ErrorAction SilentlyContinue) {
        $cachePath = Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json"
        $skipReason = "score=$($Gem.score) mode=$($Gem.mode)"
        if (Test-GemRecentlyRejected -Path $cachePath -Market $mkt -Reason $skipReason -TtlMinutes 60) {
            Write-Host "SKIP CACHE: $mkt mesma condicao <60min (poupanca LLM)" -ForegroundColor DarkGray
            return [PSCustomObject]@{ blocked = $true; blocked_by = @("recent_decision_cache"); cache_hit = $true }
        }
    }

    # ── Validacoes ────────────────────────────────────────────────────────────
    $scoreMin = if ($Gem.mode -eq "DISCOVERY") { $global:GEM_SCORE_MIN_DISC } else { $global:GEM_SCORE_MIN_MOM }
    if ($Gem.score -lt $scoreMin) {
        Write-Host "BLOQUEADO: score $($Gem.score) abaixo do minimo $scoreMin" -ForegroundColor Red
        # Add to cache pra evitar re-veto
        if (Get-Command Add-GemRejection -ErrorAction SilentlyContinue) {
            try { Add-GemRejection -Path (Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json") -Market $mkt -Reason "score_below_min $($Gem.score)" } catch {}
        }
        # B fix 2026-05-21: retornar PSCustomObject blocked com reason explicit pra caller
        return [PSCustomObject]@{ blocked = $true; blocked_by = @("score_below_min_$($Gem.score)_lt_$scoreMin"); market = $mkt }
    }
    if (-not $sz -or $sz.sizing_pct -le 0) {
        Write-Host "BLOQUEADO: sizing invalido" -ForegroundColor Red
        return [PSCustomObject]@{ blocked = $true; blocked_by = @("sizing_invalido"); market = $mkt }
    }
    if ($vd.spike_type -eq "BEARISH") {
        Write-Host "BLOQUEADO: spike BEARISH detectado (G1B)" -ForegroundColor Red
        return [PSCustomObject]@{ blocked = $true; blocked_by = @("spike_BEARISH_G1B"); market = $mkt }
    }

    # ── Detectar tipo de mercado ──────────────────────────────────────────────
    # 2026-05-19 PM: usa Get-GemRouteForMarket (consolidado via lib_market_router_wire)
    # GEM prefere spot (sem leverage; risco controlado). Fallback ao pattern antigo.
    if (Get-Command Get-GemRouteForMarket -ErrorAction SilentlyContinue) {
        $routeInfo = Get-GemRouteForMarket -Market $mkt
        $hasFutures = ($routeInfo.market_type -eq "FUTURES")
        $marketType = $routeInfo.market_type
        if ($marketType -eq "NONE") {
            Write-Host "  [Route] $mkt sem rota disponivel (delisted?) -- abortar" -ForegroundColor Red
            return [PSCustomObject]@{ blocked = $true; blocked_by = @("route_NONE_delisted"); market = $mkt }
        }
        Write-Host "  [Route] $mkt -> $($routeInfo.route) (spot=$($routeInfo.spot_available) fut=$($routeInfo.futures_available))" -ForegroundColor DarkCyan
    } else {
        $hasFutures  = CoinEx-HasFuturesMarket $mkt
        $marketType  = if ($hasFutures) { "FUTURES" } else { "SPOT" }
    }
    # 2026-05-19 PM: sizing usa TOTAL CoinEx (spot+futures) -- representa portfolio real.
    # Execucao em FUTURES exige margem em futures wallet; gate adicional logo abaixo
    # checa se usd_size <= futures_balance pra evitar margin call.
    $capital     = if (Get-Command CoinEx-GetTotalCapitalUSDT -ErrorAction SilentlyContinue) {
        CoinEx-GetTotalCapitalUSDT
    } elseif ($hasFutures) {
        CoinEx-GetFuturesCapitalUSDT
    } else {
        CoinEx-GetSpotCapitalUSDT
    }
    $executionWalletCap = if ($hasFutures) { CoinEx-GetFuturesCapitalUSDT } else { CoinEx-GetSpotCapitalUSDT }

    # ── Preco atual ───────────────────────────────────────────────────────────
    $tickerEndpoint = if ($hasFutures) { "/v2/futures/ticker?market=$mkt" } else { "/v2/spot/ticker?market=$mkt" }
    $ticker = Invoke-RestMethod -Uri "$global:COINEX_BASE_URL$tickerEndpoint" -Method GET
    if ($ticker.code -ne 0 -or -not $ticker.data) { throw "Ticker indisponivel para $mkt" }
    $price = [double]$ticker.data[0].last

    # ── Sizing (calculo de usd_size, qty -- precede gates) ───────────────────
    # 2026-05-19 PM: usa Get-ExecutorSize (Kelly-aware via $global:USE_KELLY_SIZING flag).
    # Flag OFF (default) = legacy capital * sizing_pct. Flag ON = Kelly-fractional adaptive.
    if (Get-Command Get-ExecutorSize -ErrorAction SilentlyContinue) {
        $szResolved = Get-ExecutorSize -Market $mkt -Mode "GEM" -Capital $capital -BasePct $sz.sizing_pct
        $usd_size = [double]$szResolved.size_usd
        if ($szResolved.method -eq "kelly_adaptive") {
            Write-Host "  [SIZING] Kelly adaptive: f_used=$($szResolved.f_used) win_prob=$($szResolved.win_prob) (n=$($szResolved.n_trades))" -ForegroundColor DarkCyan
        }
    } else {
        $usd_size = [math]::Round($capital * $sz.sizing_pct, 2)
    }
    $qty         = [math]::Round($usd_size / $price, 6)
    $spike_pct   = $vd.pct_change_today

    Write-Host "  Mercado    : $mkt [$($Gem.mode)] score=$($Gem.score) tipo=$marketType" -ForegroundColor White
    Write-Host "  Capital    : $capital USDT ($marketType real)" -ForegroundColor Gray
    Write-Host "  Sizing     : $([math]::Round($sz.sizing_pct*100,3))% = $usd_size USDT" -ForegroundColor Yellow
    Write-Host "  Preco      : $price  Qtd: $qty" -ForegroundColor White
    Write-Host "  Vol spike  : $($vd.spike_ratio)x $($vd.spike_type) (+${spike_pct}%)" -ForegroundColor Gray
    Write-Host "  Max dias   : $($sz.max_days)d" -ForegroundColor Gray

    if ($marketType -eq "FUTURES") {
        Write-Host "  LEMBRETE: margem isolated deve estar configurada para $mkt" -ForegroundColor DarkYellow
    }

    # ── 1. GEM SAFETY GUARDS (block runaway exposure) ────────────────────────
    # Aplica em DryRun tambem para sinalizar bloqueios em paper trade.
    $safetyStatePath = Join-Path $global:JOURNAL_DIR "gem_safety_state.json"
    $safety = Test-GemSafetyGuards -TradeSizeUsdt $usd_size -TotalCapitalUsdt $capital -StateFilePath $safetyStatePath
    if (-not $safety.allowed) {
        Write-Host "  [GEM SAFETY BLOCK] ${mkt}: $($safety.reason)" -ForegroundColor Red
        try { Send-TelegramAlert -Message "GEM bloqueado: $($safety.reason)`n$($safety.telegram_message)" | Out-Null } catch {}
        # C fix: TTL cache pra evitar loop re-aprovacao
        if (Get-Command Add-GemRejection -ErrorAction SilentlyContinue) {
            try { Add-GemRejection -Path (Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json") -Market $mkt -Reason "gem_safety:$($safety.reason)" } catch {}
        }
        return [PSCustomObject]@{ blocked = $true; blocked_by = @("gem_safety:$($safety.reason)"); market = $mkt }
    }
    if ($safety.requires_confirmation) {
        Write-Host "  [GEM SAFETY] confirmacao dupla exigida (projetado $($safety.projected_exposure_pct)%)." -ForegroundColor Yellow
        try { Send-TelegramAlert -Message "GEM aviso: $($safety.telegram_message)" | Out-Null } catch {}
        # 2026-05-20: confirmation policy = warning-only (segue trade). Wait-TelegramApproval
        # existe em lib_telegram.ps1:153 mas decisao explicita: GEM mantem aviso unico
        # (sizing 0.2% ja eh tao pequeno que double-confirm seria overkill).
    }

    # ── 2. TORI GATE (qualidade tecnica de trendline; ENTER|SKIP|WAIT) ───────
    # Bloqueia GEMs sem ancora tecnica antes de comprometer capital. Defensivo:
    # qualquer falha upstream (Claude indisponivel, exception) aborta o trade.
    $tori_signal = "ENTER"
    $tori_reason = ""
    try {
        $tori = Get-ToriTrendlineSignal -Market $mkt
        $tori_signal = "$($tori.signal)".ToUpper()
        $tori_reason = "$($tori.reason)"
    } catch {
        Write-Host "  [GEM TORI ERROR] ${mkt}: $_" -ForegroundColor Red
        try { Send-TelegramAlert -Message "GEM bloqueado por Tori (error): $mkt -- $_" | Out-Null } catch {}
        return [PSCustomObject]@{ blocked = $true; blocked_by = @("tori_error:$($_.Exception.Message)"); market = $mkt }
    }
    if ($tori_signal -in @("SKIP","WAIT")) {
        $tag = "tori:" + $tori_signal.ToLower() + ":" + $tori_reason
        Write-Host "  [GEM TORI BLOCK] ${mkt}: $tag" -ForegroundColor Red

        # 2026-05-18 Opcao C: SKIP por DADOS AUSENTES vira log silencioso (nao spam TG).
        # 2026-05-21 fix: ainda retorna PSCustomObject blocked pra caller saber motivo.
        $reasonLower = "$tori_reason".ToLower()
        $isDataAbsent = ($reasonLower -match "n/a|no_trendline_data|no_verdict|tech_agent_null|impossivel identificar|impossível identificar|sem dados|sem pontos de ancoragem|retornaram n/a")

        # A. MISSED log enriquecido 2026-05-22: quando Tori SKIP por timing missed,
        # cruza com snapshot tori_proximity pra capturar setup_ripening pre-spike.
        # Zero LLM, zero risco LIVE -- so observa SKIP que ja aconteceu pra dataset
        # decidir "afrouxar 16% threshold" data-driven em 7 dias.
        $isTimingMissed = ($reasonLower -match "missed|ja se distanciou|ja rompeu|distancia significativa|overbought extremo|chase|distanciou.*line")
        if ($isTimingMissed -and (Get-Command Get-ToriProximityForMarket -ErrorAction SilentlyContinue)) {
            try {
                $statePath = Join-Path $global:JOURNAL_DIR "tori_proximity_state.json"
                $missedPath = Join-Path $global:JOURNAL_DIR "missed_setups.jsonl"
                $tp = Get-ToriProximityForMarket -Market $mkt -StatePath $statePath -MaxAgeMinutes 60
                $entry = [ordered]@{
                    ts_skip          = (Get-Date).ToUniversalTime().ToString("o")
                    market           = $mkt
                    tori_reason      = "$tori_reason".Substring(0, [Math]::Min(200, "$tori_reason".Length))
                    proximity_snap   = if ($tp) { [ordered]@{
                        ts_snap        = if ($tp.PSObject.Properties['ts_utc']) { "$($tp.ts_utc)" } else { $null }
                        side           = "$($tp.side)"
                        proximity_pct  = $tp.proximity_pct
                        action_line    = $tp.action_line
                        slope_deg      = $tp.slope_deg
                        rsi            = $tp.rsi
                        vol_drying     = $tp.vol_drying
                        setup_ripening = [bool]$tp.setup_ripening
                    } } else { $null }
                    snapshot_present = ($null -ne $tp)
                }
                $dir = Split-Path -Parent $missedPath
                if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                Add-Content -Path $missedPath -Value ($entry | ConvertTo-Json -Compress -Depth 4) -Encoding UTF8
            } catch {}
        }

        if ($isDataAbsent) {
            Write-Host "  [GEM TORI SKIP-SILENT] ${mkt}: dados ausentes -- nao spam TG" -ForegroundColor DarkYellow
        } else {
            try { Send-TelegramAlert -Message "GEM bloqueado por Tori ($tori_signal): $mkt -- $tori_reason" | Out-Null } catch {}
        }
        # C fix 2026-05-21: TTL cache pra prevenir loop re-aprovacao em market sem dados.
        # Sem isso, PROVE reaparece a cada cycle horario e user re-aprova inutilmente.
        # TTL 24h pra dados ausentes (só muda com tempo); 1h pra Tori SKIP normal.
        if (Get-Command Add-GemRejection -ErrorAction SilentlyContinue) {
            $cacheReason = if ($isDataAbsent) { "tori_data_absent" } else { "tori_$($tori_signal.ToLower())" }
            try { Add-GemRejection -Path (Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json") -Market $mkt -Reason $cacheReason } catch {}
        }
        return [PSCustomObject]@{ blocked = $true; blocked_by = @("tori_$($tori_signal.ToLower())_$tori_reason"); market = $mkt; tori_data_absent = $isDataAbsent }
    }

    # ── 3. CALCULATE STOP/TARGET (precision math, fix sub-dollar 2026-05-14) ──
    # Decimal-based; serializa InvariantCulture. So acontece se safety + tori passaram.
    # Consulta precision de mercado ANTES (cache 1h) -- garante que sub-dollar tokens
    # arredondem na precisao correta (AIUSDT spot: quote_ccy_precision=6+).
    $precType   = if ($hasFutures) { "futures" } else { "spot" }
    $precision  = $null
    try {
        $precision = Get-MarketPrecision -Market $mkt -MarketType $precType
    } catch {
        Write-Host "  [PRECISION WARN] ${mkt}: Get-MarketPrecision falhou ($_); usando fallback 8 casas" -ForegroundColor Yellow
    }
    $pricePrec = if ($precision -and $precision.quote_ccy_precision) {
        [int]$precision.quote_ccy_precision
    } else {
        Write-Host "  [PRECISION WARN] ${mkt}: precision indisponivel; fallback quote=8" -ForegroundColor Yellow
        8
    }
    $basePrec  = if ($precision -and $precision.base_ccy_precision) { [int]$precision.base_ccy_precision } else { 6 }
    $cachedTag = if ($precision) { "true" } else { "false" }
    Write-Host "  [PRECISION] $mkt $precType quote=$pricePrec base=$basePrec cached=$cachedTag" -ForegroundColor DarkGray

    try {
        $st = Calculate-StopTarget `
            -Entry     ([double]$price) `
            -StopPct   ([double]$sz.stop_pct) `
            -TargetPct ([double]$sz.target_pct) `
            -Direction "LONG" `
            -Precision $pricePrec
    } catch {
        Write-Host "BLOQUEADO: Calculate-StopTarget falhou para ${mkt}: $_" -ForegroundColor Red
        return [PSCustomObject]@{ blocked = $true; blocked_by = @("calculate_stoptarget_error:$($_.Exception.Message)"); market = $mkt }
    }
    $stop_price  = $st.stop_price
    $tgt_price   = $st.target_price
    $stop_pct_display   = [math]::Round($sz.stop_pct * 100, 0)
    $target_pct_display = [math]::Round($sz.target_pct * 100, 0)

    Write-Host "  Stop       : $stop_price  (-${stop_pct_display}%)" -ForegroundColor Red
    Write-Host "  Target     : $tgt_price   (+${target_pct_display}%)" -ForegroundColor Green
    Write-Host "  Tori       : $tori_signal ($tori_reason)" -ForegroundColor DarkGreen

    # ── 4. EXIT LADDER (multi TP/SL knowledge-driven) ───────────────────────────
    # Decide template baseado em context (GEM/STANDARD/regime/spike) e instancia.
    # Defensive: se Get-ExitLadder nao estiver carregado, segue trade legacy (1 TP).
    $ladder      = $null
    $ladderTplId = $null
    if (Get-Command Get-ExitLadder -ErrorAction SilentlyContinue) {
        $setupForLadder = [PSCustomObject]@{
            score       = $Gem.score
            market_type = $marketType
            vol_data    = $vd
        }
        try {
            $ladderTplId = Get-LadderTemplateForSetup -Setup $setupForLadder -Regime "" -GemMode $true
            $ladder      = Get-ExitLadder -TemplateId $ladderTplId -Entry ([decimal]$price) -AtrValue ([decimal]0)
            $tpsCount    = if ($ladder -and $ladder.tp_levels) { @($ladder.tp_levels).Count } else { 0 }
            $slsCount    = if ($ladder -and $ladder.sl_levels) { @($ladder.sl_levels).Count } else { 0 }
            $beAfter     = if ($ladder.PSObject.Properties['breakeven_after_tp']) { $ladder.breakeven_after_tp } else { 0 }
            Write-Host "  [LADDER] $mkt template=$ladderTplId tps=$tpsCount sls=$slsCount breakeven_after=$beAfter" -ForegroundColor Cyan
        } catch {
            Write-Host "  [LADDER WARN] Get-ExitLadder falhou para ${mkt}: $_ (segue legacy single TP)" -ForegroundColor Yellow
            $ladder = $null
        }
    }

    if ($DryRun) {
        Write-Host "  [DRY RUN] Ordem NAO enviada." -ForegroundColor DarkYellow
        Write-GemTradeJournal -Market $mkt -Price $price -Qty $qty -StopPrice $stop_price `
            -TargetPrice $tgt_price -SizingUsd $usd_size -GemScore $Gem.score `
            -Mode $Gem.mode -MarketType $marketType -DryRun $true -ToriSignal $tori_signal
        if ($ladder -and (Get-Command Add-LadderEntryRecord -ErrorAction SilentlyContinue)) {
            try {
                Add-LadderEntryRecord -Market $mkt -TemplateId $ladderTplId -Regime "GEM" `
                    -Entry $price -AtrValue 0 `
                    -TpsCount (@($ladder.tp_levels).Count) -SlsCount (@($ladder.sl_levels).Count) `
                    -Notes "dry_run" | Out-Null
            } catch {}
        }
        return [PSCustomObject]@{
            market              = $mkt
            market_type         = $marketType
            price               = $price
            qty                 = $qty
            stop                = $stop_price
            target              = $tgt_price
            sizing_usd          = $usd_size
            dry_run             = $true
            ladder_template_id  = $ladderTplId
            ladder              = $ladder
        }
    }

    # ── GUARD: Promotion Ladder sizing (Phase 2 2026-05-18) ───────────────────
    # Se market esta na ladder, aplica multiplier por tier_state (25/50/100%).
    # State 0/1 (DESCOBERTA/OBSERVATION) bloqueia trade. Markets fora da ladder
    # caem pra guards antigos abaixo (compat).
    if (Get-Command Resolve-PromotionSizing -ErrorAction SilentlyContinue) {
        $pipelinePath = Join-Path (Split-Path $PSScriptRoot -Parent) "journal\promotion_pipeline.jsonl"
        if (Test-Path $pipelinePath) {
            $ladderSize = Resolve-PromotionSizing -PipelinePath $pipelinePath -Market $mkt -BaseSize $usd_size
            if ($ladderSize.source -eq "ladder") {
                if (-not $ladderSize.allowed) {
                    Write-Host "  [LADDER] $mkt em $($ladderSize.tier_label) -- trade NAO permitido (size=0)" -ForegroundColor DarkYellow
                    return [PSCustomObject]@{
                        market = $mkt; market_type = $marketType
                        price = $price; qty = 0
                        stop = $stop_price; target = $tgt_price
                        sizing_usd = 0; dry_run = $false
                        blocked = $true; blocked_by = @("ladder_tier_$($ladderSize.tier_label)")
                    }
                }
                if ($ladderSize.size_usd -lt $usd_size) {
                    Write-Host "  [LADDER] $mkt sizing $usd_size -> $($ladderSize.size_usd) ($($ladderSize.tier_label))" -ForegroundColor Cyan
                    $usd_size = [double]$ladderSize.size_usd
                    $qty = [Math]::Round($usd_size / $price, 8)
                }
            }
        }
    }

    # ── GUARD: tier whitelist + 4 live guards (2026-05-18) ────────────────────
    # GemAgent agora respeita Mode 2 LIVE guards. Bloqueia GEMs fora Tier A/B em LIVE.
    # 2026-06-03: DISCOVERY mode exempto de tier whitelist (são pares novos por definição)
    if (Get-Command Test-LiveTradeGuards -ErrorAction SilentlyContinue) {
        $tierMode = if ($gem.mode -eq "DISCOVERY") { "ANY" } else {
            if ($global:LIVE_TIER_FILTER) { $global:LIVE_TIER_FILTER } else { "PAPER" }
        }
        $maxSize  = if ($global:LIVE_MAX_SIZE_USD) { [double]$global:LIVE_MAX_SIZE_USD } else { 100.0 }
        $maxFreq  = if ($global:LIVE_MAX_TRADES_PER_WEEK) { [int]$global:LIVE_MAX_TRADES_PER_WEEK } else { 5 }
        $maxCust  = if ($global:LIVE_MAX_CUSTODIAL_RATIO) { [double]$global:LIVE_MAX_CUSTODIAL_RATIO } else { 0.30 }
        $totCap   = if ($global:TOTAL_CAPITAL_USD) { [double]$global:TOTAL_CAPITAL_USD } else { 0 }
        $exchBal  = 0.0
        try { $exchBal = [double](CoinEx-GetTotalCapitalUSDT) } catch {}

        $guards = Test-LiveTradeGuards `
            -Market $mkt -ProposedSizeUsd $usd_size `
            -ExchangeBalanceUsd $exchBal -TotalCapitalUsd $totCap `
            -MaxSizeUsd $maxSize -MaxTradesPerWeek $maxFreq `
            -AllowedTierMode $tierMode -MaxCustodialRatio $maxCust
        if (-not $guards.pass) {
            $reasons = ($guards.blocked_by -join " | ")
            Write-Host "  [GEM GUARD BLOCKED] $mkt -- $reasons" -ForegroundColor Red
            $tsBlock = (Get-Date).ToString("HH:mm dd/MM/yy")
            $blockMsg = "*GEM BLOQUEADO* -- $mkt`nMotivo: $reasons`n_$tsBlock_"
            try { Send-TelegramAlert -Message $blockMsg | Out-Null } catch {}
            return [PSCustomObject]@{
                market = $mkt; market_type = $marketType
                price = $price; qty = $qty
                stop = $stop_price; target = $tgt_price
                sizing_usd = $usd_size; dry_run = $false
                blocked = $true; blocked_by = $guards.blocked_by
            }
        }
    }

    # ── Alerta PRE-ordem ─────────────────────────────────────────────────────
    $mktType = if ($hasFutures) { "FUTURES" } else { "SPOT" }
    $ts = (Get-Date).ToString("HH:mm dd/MM/yy")
    $preMsg = "*EXECUTANDO GEM* -- $mkt [$mktType]`nEntrada: $price | Stop: $stop_price | Alvo: $tgt_price`nSizing: $usd_size USDT`n_$ts_"
    Send-TelegramAlert -Message $preMsg | Out-Null

    # ── Execucao via Invoke-OrderRouted (2026-05-20 wire) ──────────────────
    # Antes: chamava CoinEx-PlaceOrder/PlaceSpotOrder direto (bypass router).
    # Agora: route unified via Invoke-OrderRouted (futures|spot). Mesmo comportamento.
    $route = if ($hasFutures) { "futures" } else { "spot" }
    $orderTypeLabel = if ($hasFutures) { "FUTURES" } else { "SPOT (fallback)" }
    Write-Host "  Enviando ordem $orderTypeLabel..." -ForegroundColor Cyan
    if ($hasFutures) {
        $order = Invoke-OrderRouted -Route "futures" -Market $mkt -Side "buy" -Type "market" `
                                     -Amount $qty -StopLoss $stop_price
    } else {
        # Market BUY usa quote currency (USDT): QuoteAmountUsd carrega o sizing
        $order = Invoke-OrderRouted -Route "spot" -Market $mkt -Side "buy" -Type "market" `
                                     -Amount $qty -QuoteAmountUsd $usd_size
    }
    Write-Host "  Ordem: id=$($order.order_id)" -ForegroundColor Green
    $filled_qty = if ($order.filled_amount) { [double]$order.filled_amount } else { $qty }
    $avg_price  = if ($order.avg_deal_price -and [double]$order.avg_deal_price -gt 0) { [double]$order.avg_deal_price } else { $price }

    if (-not $hasFutures) {

        # Stop condicional para spot
        try {
            CoinEx-PlaceSpotStopOrder -Market $mkt -Side "sell" -TriggerPrice $stop_price -Amount $filled_qty | Out-Null
            Write-Host "  Stop condicional colocado em $stop_price" -ForegroundColor Yellow
        } catch {
            Write-Host "  AVISO: stop order falhou -- monitore manualmente. $_" -ForegroundColor Red
        }
    }

    Write-GemTradeJournal -Market $mkt -Price $avg_price -Qty $filled_qty -StopPrice $stop_price `
        -TargetPrice $tgt_price -SizingUsd $usd_size -GemScore $Gem.score `
        -Mode $Gem.mode -MarketType $marketType -DryRun $false -OrderId $order.order_id `
        -ToriSignal $tori_signal

    # Registra exposure para guard cumulativo
    try { Add-OpenGemPosition -Market $mkt -SizeUsdt $usd_size -StateFilePath $safetyStatePath } catch {}

    # ── PROTECAO OBRIGATORIA: SL + TP REAIS na corretora (2026-05-29) ───────────
    # CAUSA RAIZ CORRIGIDA: SL/TP embutido em ordem MARKET (CoinEx-PlaceOrder) NAO
    # aplica de forma confiavel na CoinEx V2 (posicao ainda nao existe no submit).
    # Resultado anterior: posicao INJUSDT ficou com TP/SL="--" (sem protecao, corria
    # ate liquidacao). Agora: aplica SL+TP via set-position-* APOS fill, valida na
    # corretora e faz retry. Se falhar, alerta Telegram (acao manual).
    if ($hasFutures -and (Get-Command Set-PositionProtection -ErrorAction SilentlyContinue)) {
        Start-Sleep -Seconds 2  # aguarda posicao materializar na API
        $protect = Set-PositionProtection -Market $mkt -StopLoss $stop_price -TakeProfit $tgt_price -MaxRetries 3 -AlertOnFailure $true
        if ($protect.success) {
            Write-Host "  [PROTECAO OK] $mkt SL=$($protect.sl_price) TP=$($protect.tp_price) (validado na corretora)" -ForegroundColor Green
        } else {
            Write-Host "  [PROTECAO FALHOU] $mkt sl_set=$($protect.sl_set) tp_set=$($protect.tp_set) -- ALERTA ENVIADO" -ForegroundColor Red
        }
    }

    # ── Multi TP/SL nativo CoinEx (apenas FUTURES; spot usa stop ja colocado) ───
    if ($ladder -and $hasFutures -and (Get-Command CoinEx-PlaceMultiExitLadder -ErrorAction SilentlyContinue)) {
        try {
            $multi = CoinEx-PlaceMultiExitLadder -Market $mkt -PositionSide "long" `
                -TotalAmount ([decimal]$filled_qty) -Entry ([decimal]$avg_price) `
                -Ladder $ladder -AtrValue ([decimal]0) -PricePrecision $pricePrec -AmountPrecision $basePrec
            Write-Host "  [LADDER PLACED] tps=$(@($multi.tp_orders).Count) sls=$(@($multi.sl_orders).Count)" -ForegroundColor Cyan
        } catch {
            Write-Host "  [LADDER WARN] CoinEx-PlaceMultiExitLadder falhou: $_" -ForegroundColor Yellow
        }
    }

    if ($ladder -and (Get-Command Add-LadderEntryRecord -ErrorAction SilentlyContinue)) {
        try {
            Add-LadderEntryRecord -Market $mkt -TemplateId $ladderTplId -Regime "GEM" `
                -Entry $avg_price -AtrValue 0 `
                -TpsCount (@($ladder.tp_levels).Count) -SlsCount (@($ladder.sl_levels).Count) `
                -TradeId $order.order_id -Notes "live" | Out-Null
        } catch {}
    }

    # ── Confirmacao POS-ordem ─────────────────────────────────────────────────
    $execObj = [PSCustomObject]@{ market=$mkt; market_type=$mktType; order_id=$order.order_id; price=$avg_price; qty=$filled_qty; stop=$stop_price; target=$tgt_price }
    Send-TelegramAlert -Message (Format-TgGemExecuted -ExecResult $execObj -Gem $Gem) | Out-Null

    # ── 2026-05-29: ALERTA DE TRADE ABERTO EM DESTAQUE ────────────────────────
    # Antes: abertura passava sem destaque (so a linha generica acima). Agora envia
    # mensagem em destaque com entry/stop/TP/size para nao passar despercebida.
    if (Get-Command Format-TgTradeOpenedHighlight -ErrorAction SilentlyContinue) {
        try {
            $stopPctCalc   = if ($avg_price -gt 0) { [math]::Round([math]::Abs(($avg_price - $stop_price) / $avg_price) * 100, 1) } else { 0 }
            $targetPctCalc = if ($avg_price -gt 0) { [math]::Round([math]::Abs(($tgt_price - $avg_price) / $avg_price) * 100, 1) } else { 0 }
            $sideForMsg = if ($hasFutures) { "long" } else { "long" }  # GEM long-only
            $tradeHl = @{
                market      = $mkt
                side        = $sideForMsg
                entry_price = $avg_price
                size        = $filled_qty
                stop_loss   = $stop_price
                take_profit = $tgt_price
                stop_pct    = $stopPctCalc
                target_pct  = $targetPctCalc
                capital     = $usd_size
            }
            Send-TelegramAlert -Message (Format-TgTradeOpenedHighlight -Trade $tradeHl) | Out-Null
        } catch {
            Write-Host "  [TG HIGHLIGHT WARN] Falha ao enviar destaque: $_" -ForegroundColor Yellow
        }
    }

    # ── 2026-05-29: ANALISE DE MERCADO AUTOMATICA (multi-timeframe) ───────────
    # Nossa "AI Analysis" interna: contexto 1h/4h/1d (RSI/MACD/Bollinger/niveis)
    # enviado junto da abertura para dar visao de mercado no momento da entrada.
    if ($hasFutures -and (Get-Command Get-AutoMarketAnalysis -ErrorAction SilentlyContinue)) {
        try {
            $autoAnalysis = Get-AutoMarketAnalysis -Market $mkt
            if ($autoAnalysis.success -and (Get-Command Format-TgAutoAnalysis -ErrorAction SilentlyContinue)) {
                Send-TelegramAlert -Message (Format-TgAutoAnalysis -Analysis $autoAnalysis) | Out-Null
            }
        } catch {
            Write-Host "  [AUTO ANALYSIS WARN] Falha ao gerar analise: $_" -ForegroundColor Yellow
        }
    }

    # ── 2026-05-23: TRAILING STOP AUTOMATICO (Position Management) ────────────
    # Ativa trailing stop ATR-based automaticamente apos GEM executado com sucesso.
    # Parametros: ATR 2x, ativa apos 2% lucro minimo (protege capital + deixa correr).
    # Executa em background (nao bloqueia retorno) e loga resultado.
    if ($hasFutures -and (Get-Command Update-TrailingStop -ErrorAction SilentlyContinue)) {
        try {
            Write-Host "  [TRAILING STOP] Agendando ativacao automatica em 60s..." -ForegroundColor DarkCyan
            # Agendar trailing stop para 60s depois (tempo para posicao aparecer na API)
            $trailingJob = Start-Job -ScriptBlock {
                param($Market, $ScriptRoot, $AccessId, $SecretKey, $BaseUrl)
                Start-Sleep -Seconds 60
                # Carregar credenciais no job (nao herdam do processo pai)
                $env:COINEX_ACCESS_ID  = $AccessId
                $env:COINEX_SECRET_KEY = $SecretKey
                if ($BaseUrl) { $global:COINEX_BASE_URL = $BaseUrl }
                . "$ScriptRoot\config.ps1"
                . "$ScriptRoot\lib_coinex.ps1"
                . "$ScriptRoot\lib_coinex_position_management.ps1"
                . "$ScriptRoot\lib_position_risk_manager.ps1"
                $result = Update-TrailingStop -Market $Market -AtrMultiplier 2.0 -MinProfitPct 2.0
                return $result
            } -ArgumentList $mkt, $PSScriptRoot, $env:COINEX_ACCESS_ID, $env:COINEX_SECRET_KEY, $global:COINEX_BASE_URL
            
            Write-Host "  [TRAILING STOP] Job ID: $($trailingJob.Id) (rodando em background)" -ForegroundColor DarkGray
        } catch {
            Write-Host "  [TRAILING STOP WARN] Falha ao agendar: $_" -ForegroundColor Yellow
        }
    }

    Write-Host "=== ENTRADA REGISTRADA ===" -ForegroundColor Cyan
    return [PSCustomObject]@{
        market      = $mkt
        market_type = $marketType
        order_id    = $order.order_id
        price       = $avg_price
        qty         = $filled_qty
        stop        = $stop_price
        target      = $tgt_price
        sizing_usd  = $usd_size
        dry_run     = $false
        trailing_stop_job_id = if ($trailingJob) { $trailingJob.Id } else { $null }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Write-GemTradeJournal
# ─────────────────────────────────────────────────────────────────────────────
# BUG FIX 2026-05-29: Adicionar escape de aspas e formatação correta de números
# Problema: valores numéricos estavam sendo truncados/corrompidos no CSV
# Solução: usar InvariantCulture para serialização e escape de aspas
function Write-GemTradeJournal {
    param(
        [string] $Market,
        [double] $Price,
        [double] $Qty,
        [double] $StopPrice,
        [double] $TargetPrice,
        [double] $SizingUsd,
        [int]    $GemScore,
        [string] $Mode,
        [string] $MarketType = "FUTURES",
        [bool]   $DryRun,
        [string] $OrderId = "",
        [string] $ToriSignal = ""
    )

    $tradeFile = Join-Path $global:JOURNAL_DIR "gem_trades.csv"
    if (-not (Test-Path $tradeFile)) {
        "timestamp,market,mode,market_type,score,price_entry,qty,stop_price,target_price,sizing_usd,order_id,dry_run,status,price_exit,pnl_pct,tori_signal,notes" |
            Out-File -FilePath $tradeFile -Encoding utf8 -Force
    }

    # BUG FIX: Usar InvariantCulture para evitar corrupção de números (vírgula PT-BR)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $priceStr = $Price.ToString($inv)
    $qtyStr = $Qty.ToString($inv)
    $stopStr = $StopPrice.ToString($inv)
    $targetStr = $TargetPrice.ToString($inv)
    $sizingStr = $SizingUsd.ToString($inv)
    
    # Escape de aspas em campos de texto
    $marketEsc = $Market -replace '"', '""'
    $modeEsc = $Mode -replace '"', '""'
    $marketTypeEsc = $MarketType -replace '"', '""'
    $orderIdEsc = $OrderId -replace '"', '""'
    $toriSignalEsc = $ToriSignal -replace '"', '""'

    $row = @(
        (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),
        $marketEsc, $modeEsc, $marketTypeEsc, $GemScore,
        $priceStr, $qtyStr, $stopStr, $targetStr, $sizingStr,
        $orderIdEsc,
        $(if ($DryRun) { "true" } else { "false" }),
        "OPEN", "", "", $toriSignalEsc, ""
    ) -join ","

    Add-Content -Path $tradeFile -Value $row -Encoding utf8
}
