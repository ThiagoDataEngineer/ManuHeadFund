# lib_mentor_recalibration.ps1 — Mentor decision inversion por bolso de baixa calibração
# 2026-07-08 ataque: decision_grades mostra bolsos com acc<45% = INVERTER decisão.
# Exemplo: VETAR|SHORT|BEAR_WEAK acc=41% + would_win=57% -> INVERTAR vira APROVAR.
# Resultado: 673 falso-vetos liberados + classe SIREN mitigada por inversão mecânica.
# TDD: 12 testes (bolsos com inversão ativa vs passivo).

param([string]$DecisionGradesPath = "journal/decision_grades.jsonl")

# Calibração hard-coded baseada em 1500 samples (2026-07-08)
# Formato: "decision|direction|regime" = @{ invert=$true/false, min_acc=X, rationale="..." }
$RecalibrationPolicy = @{
    "APROVAR|LONG|BULL_STRONG" = @{ invert=$true; min_acc=0.10; rationale="acc 9% -> INVERTAR to VETAR" }
    "APROVAR|LONG|BULL_WEAK"    = @{ invert=$true; min_acc=0.10; rationale="acc 10% -> INVERTAR to VETAR" }
    "APROVAR|SHORT|BEAR_WEAK"   = @{ invert=$true; min_acc=0.32; rationale="acc 31% (SIREN) -> INVERTAR to VETAR" }
    "VETAR|SHORT|BEAR_WEAK"     = @{ invert=$true; min_acc=0.42; rationale="acc 41% would_win=57% -> INVERTAR to APROVAR" }
    "VETAR|LONG|BULL_WEAK"      = @{ invert=$true; min_acc=0.46; rationale="acc 45% would_win=46% -> INVERTAR to APROVAR" }
}

function Invoke-MentorRecalibration {
    [CmdletBinding()]
    param(
        [object]$MentorDecision,        # {decision, direction, regime, market, ...}
        [hashtable]$Policy = $RecalibrationPolicy
    )
    if (-not $MentorDecision -or -not $MentorDecision.decision) {
        return $MentorDecision
    }

    $key = "$($MentorDecision.decision)|$($MentorDecision.direction)|$($MentorDecision.regime)"
    $rule = $Policy[$key]
    if (-not $rule -or -not $rule.invert) {
        return $MentorDecision
    }

    $inverted = @{
        "APROVAR" = "VETAR"
        "VETAR"   = "APROVAR"
    }
    $original = $MentorDecision.decision
    $new = $inverted[$original]

    Write-Host "[MENTOR RECALIBRATION] $($MentorDecision.market) $($MentorDecision.direction): $original → $new ($($rule.rationale))" -ForegroundColor Magenta

    $MentorDecision.decision = $new
    $MentorDecision.recalibrated_from = $original
    $MentorDecision.recalibration_reason = $rule.rationale

    return $MentorDecision
}

# Wire ponto de entrada: se mentor_prompt caller usar esta lib, chama Invoke-MentorRecalibration
# antes de fazer a decision final pra gem_executor.
# Exemplo em gem_executor (post-mentor call):
#   if (Get-Command Invoke-MentorRecalibration -ErrorAction SilentlyContinue) {
#       $r = Invoke-MentorRecalibration -MentorDecision $mentorResult
#       $mentorResult = $r
#   }
