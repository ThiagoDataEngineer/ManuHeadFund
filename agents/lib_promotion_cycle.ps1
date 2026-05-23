# lib_promotion_cycle.ps1 -- Cron logic pura (sem Telegram I/O)
#
# Invoke-PromotionCycle:
#   1. Le pipeline jsonl
#   2. Agrupa por market, pega ultimo state
#   3. Para cada market nao-terminal:
#      a. Fetch metrics via -MetricsProvider scriptblock
#      b. Avalia gate apropriado
#      c. Se passou -> retorna action propose_promote
#      d. Se demote trigger -> retorna action propose_demote
#      e. Sempre incrementa DSR global
#      f. Log evaluation no pipeline (Add-PromotionEvent event=evaluated)
#
# MetricsProvider injetavel facilita teste. Em producao recebe Get-PromotionMetrics
# que faz fetch CoinEx + observations.csv.
#
# PS 5.1. UTF-8 BOM.

function Invoke-PromotionCycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $PipelinePath,
        [Parameter(Mandatory)] [string] $DsrPath,
        [Parameter(Mandatory)] [scriptblock] $MetricsProvider,
        # 2026-05-20 PM: EnforceGates opt-in. Quando $true, roda Invoke-AllGates
        # antes de aprovar promote -> bloqueia se gates falharem. Antes era SO
        # Test-Gate*ToB (DSR/Sharpe), agora cobre concentration/beta/FQS/etc.
        [switch] $EnforceGates,
        [string[]] $CurrentTierAMarkets = @(),
        [double] $VolumeUsd = 0,
        [double] $EquityTodayPct = 0,
        [AllowNull()] $PhaseChangedAt = $null
    )
    $actions   = @()
    $evaluated = @()

    if (-not (Test-Path $PipelinePath)) {
        return [PSCustomObject]@{ actions = $actions; evaluated = $evaluated }
    }

    # Agrupa por market, pega ultimo state
    $lines = Get-Content $PipelinePath -Encoding UTF8
    $byMarket = @{}
    foreach ($line in $lines) {
        if (-not $line) { continue }
        try {
            $obj = $line | ConvertFrom-Json
            $byMarket[$obj.market] = $obj
        } catch { continue }
    }

    foreach ($k in @($byMarket.Keys)) {
        $entry = $byMarket[$k]
        $state = [int]$entry.tier_state

        # Skip DESCOBERTA (state 0) -- precisa primeiro virar OBSERVATION via user-add
        # Skip terminal TIER_A_LIVE (state 4) -- so demote, nao promote
        if ($state -eq 0) { continue }

        # Fetch metrics via provider
        $metrics = & $MetricsProvider $k
        if (-not $metrics) { continue }

        $evaluated += $k

        # Avalia demote trigger primeiro (qualquer tier pode demotar)
        $weekly = if ($metrics.weekly_sharpes) { [double[]]$metrics.weekly_sharpes } else { [double[]]@() }
        $daysSince = if ($metrics.days_since_last_trade) { [int]$metrics.days_since_last_trade } else { 0 }
        $demote = Test-DemoteTrigger -WeeklySharpes $weekly -DaysSinceLastTrade $daysSince
        if ($demote.should_demote -and $state -gt 1) {
            $actions += [PSCustomObject]@{
                action = "propose_demote"
                market = $k
                from_state = $state
                to_state = $state - 1
                reason = $demote.reason
            }
            # Log evaluation
            Add-PromotionEvent -Path $PipelinePath -Market $k -Event "evaluated" -Metrics $metrics `
                -GateEval @{ gate = "demote"; passed = $true; reason = $demote.reason } | Out-Null
            Add-DsrTrial -Path $DsrPath -GateName "demote" -Market $k | Out-Null
            continue
        }

        # Skip promote check para TIER_A_LIVE (so demote acima foi avaliado)
        if ($state -eq 4) { continue }

        # C3 fix 2026-05-21: detect phase atual pra regime-conditioned thresholds
        $currentPhase = "unknown"
        if (Get-Command Get-HalvingPhase -ErrorAction SilentlyContinue) {
            try { $currentPhase = [string](Get-HalvingPhase) } catch {}
        }

        # Avalia promote gate apropriado (C3: phase-aware em obs_to_c)
        $gateResult = $null
        $gateName   = $null
        switch ($state) {
            1 { $gateResult = Test-GateObservationToC -Metrics $metrics -Phase $currentPhase; $gateName = "obs_to_c" }
            2 { $gateResult = Test-GateCToB           -Metrics $metrics; $gateName = "c_to_b" }
            3 { $gateResult = Test-GateBToLive        -Metrics $metrics; $gateName = "b_to_a" }
        }

        # DSR trial incrementado SEMPRE que avalia gate
        if ($gateName) {
            Add-DsrTrial -Path $DsrPath -GateName $gateName -Market $k | Out-Null
        }

        if ($gateResult -and $gateResult.passed) {
            # 2026-05-20 PM: EnforceGates aplica Invoke-AllGates como segunda barreira.
            # Antes Invoke-AllGates so era chamada por Invoke-PromotionPropose (orfa em prod).
            # Agora cobre concentration/beta/FQS/sector/cooldown/funding em todos promotes.
            $blockedByAllGates = $false
            $allGatesBlockReason = ""
            if ($EnforceGates -and (Get-Command Invoke-AllGates -ErrorAction SilentlyContinue)) {
                # 2026-05-23 wire: pass Phase from regime_state.json para beta_cap_per_phase dynamic.
                # Backward compat: se BETA_CAP_PER_PHASE_ENABLED env=0, ignora Phase param.
                $currentPhase = ""
                try {
                    $regimePath = Join-Path $global:JOURNAL_DIR "regime_state.json"
                    if (Test-Path $regimePath) {
                        $rs = Get-Content $regimePath -Raw -Encoding UTF8 | ConvertFrom-Json
                        if ($rs.phase) { $currentPhase = [string]$rs.phase }
                    }
                } catch {}
                try {
                    $aagResult = Invoke-AllGates `
                        -Market $k `
                        -VolumeUsd $VolumeUsd `
                        -CurrentTierACount $CurrentTierAMarkets.Count `
                        -CurrentTierAMarkets $CurrentTierAMarkets `
                        -EquityTodayPct $EquityTodayPct `
                        -PhaseChangedAt $PhaseChangedAt `
                        -DsrPath $DsrPath `
                        -Phase $currentPhase
                    if (-not $aagResult.all_pass) {
                        $blockedByAllGates = $true
                        $allGatesBlockReason = "all_gates: " + ($aagResult.blocked_by -join ",")
                    }
                } catch {
                    # Defensive: AllGates error nao bloqueia (avisa log)
                }
            }
            if ($blockedByAllGates) {
                $actions += [PSCustomObject]@{
                    action = "blocked_by_gates"
                    market = $k
                    from_state = $state
                    blocked_by = $aagResult.blocked_by
                    reason = $allGatesBlockReason
                }
                Add-PromotionEvent -Path $PipelinePath -Market $k -Event "evaluated" -Metrics $metrics `
                    -GateEval @{ gate = "all_gates"; passed = $false; failures = $aagResult.blocked_by } | Out-Null
                continue
            }
            $actions += [PSCustomObject]@{
                action = "propose_promote"
                market = $k
                from_state = $state
                to_state = $state + 1
                gate = $gateResult
            }
            Add-PromotionEvent -Path $PipelinePath -Market $k -Event "evaluated" -Metrics $metrics `
                -GateEval @{ gate = $gateName; passed = $true; reasons = $gateResult.reasons } | Out-Null
        } else {
            # Log evaluation com falha (audit trail)
            # C6 fix 2026-05-20 PM6+580min: PS 5.1 unwrap single-element arrays implicitamente
            # em property assignment. Force @(...) pra preservar array no JSON output.
            $failures = @(if ($gateResult) { $gateResult.failures } else { @() })
            Add-PromotionEvent -Path $PipelinePath -Market $k -Event "evaluated" -Metrics $metrics `
                -GateEval @{ gate = $gateName; passed = $false; failures = $failures } | Out-Null
        }
    }

    return [PSCustomObject]@{
        actions = $actions
        evaluated = $evaluated
    }
}
