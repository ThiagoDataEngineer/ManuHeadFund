# lib_orchestrator_parallel.ps1 -- RunspacePool wrapper para Invoke-OrchestratorV6.
#
# Cada candidato roda em runspace dedicado dentro de pool (default 3 concurrent).
# Speedup esperado: 7 candidatos x ~30s seq (~200s) -> 3 paralelo (~80s) ~2.5x.
#
# Opt-in: scan_master chama Invoke-OrchestratorCandidatesParallel quando -Parallel
# ou $global:ORCHESTRATOR_PARALLEL = $true. Default OFF (serial path estavel).
#
# Cada runspace tem session state isolado: precisa re-dot-source libs minimas.
# Isso adiciona ~3-5s de init por slot mas é amortizado pelos 30s+ por candidato.
#
# PS 5.1, UTF-8 BOM, pure aside from log writes.

function Invoke-OrchestratorCandidatesParallel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array] $Candidates,        # array PSCustomObject @{market;scanInfo;mode;dryRun}
        # B28b fix 2026-05-21: default 3 -> 2 (reduzir burst inter-market). Callers
        # podem subir explicitamente se Groq RPM aumentar (paid tier) ou se Lidar
        # mover pra Haiku (B28d) liberar bucket Groq.
        [int] $MaxConcurrency = 2,
        # 2026-05-22 PM: bump 120->240. Mesa cascade Groq->Gemini->Haiku pode levar
        # 30-60s (Wait-Job mesa_agent ate 40s + Mentor ate 20s + libs init 3-5s).
        # Timeout 120s estava matando runspaces mid-LLM-call -> "Mentor indisponivel"
        # com provider=none em 67% das decisions hoje. 240s da folga sem perder edge:
        # markets verdadeiramente travados ainda sao killed.
        [int] $PerCandidateTimeoutSec = 240,
        [string] $AgentsDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "agents")
    )

    if (-not $Candidates -or $Candidates.Count -eq 0) { return @() }

    $iss  = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $pool = [RunspaceFactory]::CreateRunspacePool(1, [Math]::Max(1, $MaxConcurrency), $iss, $Host)
    $pool.Open()

    $script = {
        param($Market, $ScanInfoJson, $DryRun, $Mode, $AgentsDir)
        try {
            # Re-dot-source libs minimas necessarias pro orchestrator_v6 + sub-agentes.
            # Ordem importa: knowledge_retriever ANTES de triagem (mock idempotente).
            # CRITICAL FIX 2026-06-01: Lista COMPLETA de libs que orchestrator_v6 precisa
            $libs = @(
                "config.ps1","config.local.ps1","lib_coinex.ps1","lib_cost_tracker.ps1","lib_claude.ps1",
                "lib_macro.ps1","lib_indicators.ps1","lib_seasonality.ps1","lib_telegram.ps1",
                "lib_idempotency.ps1","lib_retry.ps1","lib_order_idempotency.ps1","lib_price_freshness.ps1",
                "lib_mentor_hallucination_detector.ps1","lib_fqs_enrichment_queue.ps1",
                "lib_tori_proximity.ps1","lib_trailing.ps1","lib_trailing_adaptive.ps1",
                "lib_mentor_reflection.ps1","lib_layer4_tori_timestop.ps1","lib_moon_bag.ps1",
                "lib_position_register.ps1","lib_validation_logger.ps1","lib_trade_logger.ps1",
                "lib_trade_reason_archive.ps1","lib_universe_sweep.ps1","lib_hit_rate.ps1",
                "lib_observation_logger.ps1","lib_mentor_invariants.ps1","lib_gem_safety.ps1",
                "lib_gem_auto_approve.ps1","gem_agent.ps1","gem_executor.ps1",
                "lib_cycle_indicators.ps1","lib_cycle_indicators_advanced.ps1","scanner.ps1",
                "lib_market_context.ps1","lib_market_context_engine.ps1","lib_operational_whitelist.ps1",
                "lib_enhanced_short_entry.ps1","lib_mesa_consensus_relaxed.ps1","lib_quant_whitelist.ps1",
                "lib_top_candidates.ps1","lib_fqs_drain.ps1","lib_live_guards.ps1",
                "lib_promotion_gates.ps1","lib_llm_quota_optimizer.ps1","lib_short_execution.ps1",
                # 2026-05-20 PM3: libs orfas em runspace child -- causavam Get-Command null
                # silencioso. Adicionar pra orchestrator_v6 nao chamar funcoes inexistentes.
                "lib_market_router_wire.ps1","lib_order_routed.ps1",
                "lib_entry_score_boost.ps1","lib_news_entry_boost.ps1",
                # Core agents MUST be loaded in correct order
                "knowledge_retriever.ps1","triagem_agent.ps1","mesa_agent.ps1",
                "mentor_agent.ps1","lib_esquadrao_mocks.ps1","orchestrator_v6.ps1"
            )
            foreach ($l in $libs) {
                $p = Join-Path $AgentsDir $l
                if (Test-Path $p) { . $p }
            }
            $scanInfo = if ($ScanInfoJson) { $ScanInfoJson | ConvertFrom-Json } else { $null }
            $orchArgs = @{ Market = $Market; ScannerInfo = $scanInfo; Mode = $Mode }
            if ($DryRun) { $orchArgs.DryRun = $true }
            $r = Invoke-OrchestratorV6 @orchArgs
            return [PSCustomObject]@{ ok = $true; market = $Market; result = $r }
        } catch {
            return [PSCustomObject]@{ ok = $false; market = $Market; error = "$_" }
        }
    }

    $invocations = @()
    foreach ($c in $Candidates) {
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $pool
        # ScannerInfo serializa via JSON pra cruzar runspace boundary sem ref issues.
        $scanInfoJson = if ($c.scanInfo) { ($c.scanInfo | ConvertTo-Json -Compress) } else { $null }
        $modeArg   = if ($c.mode)   { [string]$c.mode } else { "paper" }
        $dryRunArg = if ($null -ne $c.dryRun) { [bool]$c.dryRun } else { $false }
        [void]$ps.AddScript($script).AddArgument($c.market).AddArgument($scanInfoJson).AddArgument($dryRunArg).AddArgument($modeArg).AddArgument($AgentsDir)
        $handle = $ps.BeginInvoke()
        $invocations += [PSCustomObject]@{
            ps      = $ps
            handle  = $handle
            market  = $c.market
            started = Get-Date
        }
    }

    $results = @()
    foreach ($inv in $invocations) {
        try {
            # WaitOne timeout em ms
            $waited = $inv.handle.AsyncWaitHandle.WaitOne($PerCandidateTimeoutSec * 1000)
            if (-not $waited) {
                $inv.ps.Stop()
                $results += [PSCustomObject]@{ ok = $false; market = $inv.market; error = "timeout_$($PerCandidateTimeoutSec)s" }
            } else {
                $out = $inv.ps.EndInvoke($inv.handle)
                # Capturar erros do runspace para diagnostico
                if ($inv.ps.Streams.Error.Count -gt 0) {
                    $errMsg = ($inv.ps.Streams.Error | ForEach-Object { $_.ToString() }) -join "; "
                    Write-Warning "[PARALLEL] $($inv.market) runspace errors: $($errMsg.Substring(0,[Math]::Min(200,$errMsg.Length)))"
                }
                # EndInvoke retorna PSDataCollection; pega ultimo
                $final = $null
                foreach ($x in $out) { $final = $x }
                if ($null -eq $final) {
                    $results += [PSCustomObject]@{ ok = $false; market = $inv.market; error = "empty_result" }
                } else {
                    $results += $final
                }
            }
        } catch {
            $results += [PSCustomObject]@{ ok = $false; market = $inv.market; error = "$_" }
        } finally {
            try { $inv.ps.Dispose() } catch {}
        }
    }

    try { $pool.Close(); $pool.Dispose() } catch {}
    return ,$results
}
