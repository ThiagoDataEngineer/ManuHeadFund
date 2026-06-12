# lib_asymmetric_demote.ps1 -- Demote rapido (3 dias FLAG = auto-fired).
#
# Filosofia assimetrica:
#   - PROMOTE eh lento: Sharpe60 1.5+, DSR 0.6+, PSR 0.9+, multiple validations
#   - DEMOTE eh rapido: 3 dias FLAG consecutivos OR 1 CRITICAL = auto-fired
#
# Protege contra crashes Luna-style (-99% em 72h). Reverso de cooldown 30d:
#   demote nao tem cooldown na hora de fechar, so na hora de RE-PROMOTE.
#
# Wire futuro: drawdown_monitor cron diario chama Invoke-AutoDemoteIfNeeded
# pra cada Tier A LIVE; se streak hit, demote + TG alert.

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}


function Test-AsymmetricDemoteCondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $FlagHistoryPath = (Join-Path $global:JOURNAL_DIR "tier_a_flag_history.jsonl"),
        [int] $StreakThreshold = 3
    )
    if (-not (Test-Path $FlagHistoryPath)) {
        return [PSCustomObject]@{ should_demote = $false; streak = 0; reason = "no_history" }
    }

    $events = @()
    foreach ($line in Get-Content $FlagHistoryPath -Encoding UTF8 -ErrorAction SilentlyContinue) {
        if (-not $line) { continue }
        try { $events += ($line | ConvertFrom-Json) } catch {}
    }
    if ($events.Count -eq 0) {
        return [PSCustomObject]@{ should_demote = $false; streak = 0; reason = "empty_history" }
    }

    # Sort por timestamp asc (oldest first)
    $sorted = @($events | Sort-Object { [DateTime]::Parse([string]$_.ts) })

    # CRITICAL ultimo evento = demote imediato (1-day rule)
    $last = $sorted[-1]
    $criticalList = @($last.critical)
    if ($criticalList -contains $Market) {
        return [PSCustomObject]@{
            should_demote = $true
            streak = 1
            reason = "critical_immediate"
            last_event_ts = [string]$last.ts
        }
    }

    # Walk backwards: conta streak consecutivo FLAG.
    # Detect gaps: se proximo event > 36h antes do atual, streak quebrou (dia faltou no monitor).
    $streak = 0
    $prevTs = $null
    for ($i = $sorted.Count - 1; $i -ge 0; $i--) {
        $ev = $sorted[$i]
        $flaggedList = @($ev.flagged)
        $criticalList = @($ev.critical)
        $thisTs = [DateTime]::Parse([string]$ev.ts)
        if ($null -ne $prevTs) {
            $hoursGap = ($prevTs - $thisTs).TotalHours
            if ($hoursGap -gt 36) {
                # gap maior que ~1.5 dias = monitor pulou um dia OU event de outro market = streak broke
                break
            }
        }
        if (($flaggedList -contains $Market) -or ($criticalList -contains $Market)) {
            $streak++
            $prevTs = $thisTs
        } else {
            break
        }
    }

    $shouldDemote = $streak -ge $StreakThreshold
    return [PSCustomObject]@{
        should_demote = $shouldDemote
        streak        = $streak
        threshold     = $StreakThreshold
        reason        = if ($shouldDemote) { "${streak}_consecutive_flags" } else { "streak_${streak}_below_${StreakThreshold}" }
    }
}


function Invoke-AutoDemoteIfNeeded {
    # Wrapper: testa condicao + executa demote se trigger.
    # Demote = Add-DemoteEvent + Add-PromotionEvent (ladder) + (optional TG alert).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $FlagHistoryPath  = (Join-Path $global:JOURNAL_DIR "tier_a_flag_history.jsonl"),
        [string] $DemoteHistoryPath = (Join-Path $global:JOURNAL_DIR "demote_history.jsonl"),
        [string] $PipelinePath     = (Join-Path $global:JOURNAL_DIR "promotion_pipeline.jsonl"),
        [int] $StreakThreshold = 3,
        [switch] $SkipTelegram
    )
    $check = Test-AsymmetricDemoteCondition -Market $Market `
                -FlagHistoryPath $FlagHistoryPath -StreakThreshold $StreakThreshold
    if (-not $check.should_demote) {
        return [PSCustomObject]@{ demoted = $false; check = $check }
    }

    # 1. Add to demote_history
    $reason = "asymmetric_auto_demote_${($check.reason)}"
    if (Get-Command Add-DemoteEvent -ErrorAction SilentlyContinue) {
        try { Add-DemoteEvent -Market $Market -Reason $reason -DemoteHistoryPath $DemoteHistoryPath } catch {}
    } else {
        # Fallback inline
        $ev = @{
            market = $Market
            demoted_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            reason = $reason
        } | ConvertTo-Json -Compress
        Add-Content -Path $DemoteHistoryPath -Value $ev -Encoding UTF8
    }

    # 2. Add ladder event (if Get-PromotionState available)
    if (Get-Command Get-PromotionState -ErrorAction SilentlyContinue) {
        try {
            $st = Get-PromotionState -Path $PipelinePath -Market $Market
            if ($st -and $st.tier_state -gt 1) {
                $newTier = [Math]::Max(1, $st.tier_state - 1)
                Add-PromotionEvent -Path $PipelinePath -Market $Market -Event "demoted" `
                    -TierState $newTier -Source "asymmetric_auto_demote" `
                    -Notes "Streak $($check.streak) FLAG/CRITICAL consecutivos -> auto-demote" | Out-Null
            }
        } catch {}
    }

    # 3. TG alert (best-effort)
    if (-not $SkipTelegram -and (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue)) {
        try {
            $msg = "<b>AUTO-DEMOTE</b> $Market`nStreak $($check.streak) dias FLAG -> demoted`nReason: $reason"
            Send-TelegramAlert -Message $msg | Out-Null
        } catch {}
    }

    return [PSCustomObject]@{ demoted = $true; check = $check; reason = $reason }
}
