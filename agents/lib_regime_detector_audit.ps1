# lib_regime_detector_audit.ps1 — Auditoria + fix regime detector (BULL_* anti-preditivo)
# 2026-07-08 investigação real: BULL_WEAK acc 39% (pior que BEAR_WEAK 41%)
# Diagnóstico: lógica do detector está invertida ou threshold está errado.

# Dados de 1500 decisões gradeadas:
# BULL_STRONG: n=415, correct=80.24%, would_win=15% → **detector acerta, mas LONGs perdem**
# BULL_WEAK: n=414, correct=39.37%, move=+6.5%, would_win=46% → **anti-preditivo**
# BEAR_WEAK: n=609, correct=40.56%, move=-36.27%, would_win=57% → indeciso
# CAPITULATION: n=17, correct=70.59% → confiável
# TRANSITION_UP: n=16, correct=75% → confiável

function Invoke-RegimeDetectorAudit {
    # Retorna dict com regime_passivization_rules baseadas em calibração real
    # Formato: "regime" = @{ passivize=$true/false; reason="..." }

    return @{
        "BULL_STRONG" = @{
            passivize = $false
            reason = "acc 80% bom, MAS LONGs perdem média -11.4% em D+2 → detector inverte LONGs pra SHORTs sempre"
            action = "MANTER: acurácia alta. AÇÃO: em BULL_STRONG + LONG, questionar estrutura (possível bearish setup nele)"
        }

        "BULL_WEAK" = @{
            passivize = $true
            reason = "acc 39% < 45%, move favor 6.5% mas acerta 39% das vezes = ANTI-PREDITIVO"
            action = "PASSIVIZAR: ignorar rótulo BULL_WEAK (use NEUTRAL em vez). Próxima entrada vê 'sem regime info' ao invés de 'BULL_WEAK'"
        }

        "BEAR_WEAK" = @{
            passivize = $false
            reason = "acc 40.5% = indeciso, MAS would_win 57% dos SHORTs → sistema veta SHORTs que ganhariam"
            action = "MANTER: recalibração mentor (VETAR→APROVAR) já mitiga. Monitorar convergência próximas 50 decisões"
        }

        "BEAR_STRONG" = @{
            passivize = $false
            reason = "acc 44.8% = borderline, would_win 51% → neutro"
            action = "MANTER: monitorar. Próximo gate: se acc <45% após 100+ samples, passivize"
        }

        "CAPITULATION" = @{
            passivize = $false
            reason = "acc 70.6%, confiável, n=17 (pequeno mas sinal claro)"
            action = "MANTER: use como gate de alta confiança (aprovações em CAPITULATION têm 71% acerto)"
        }

        "TRANSITION_UP" = @{
            passivize = $false
            reason = "acc 75%, confiável, n=16"
            action = "MANTER: usar como aprovação em LONG breakout (75% acerto bom)"
        }

        "TRANSITION_DOWN" = @{
            passivize = $false
            reason = "n=1, sem significância estatística"
            action = "IGNORAR: sem dados; próxima observação aprenderá"
        }
    }
}

function Apply-RegimePassivization {
    # Aplica passivização ao rótulo de regime
    # BULL_WEAK + passivize=true → muda pra "NEUTRAL" (sem info de regime)
    [CmdletBinding()]
    param(
        [string]$RegimeLabel,
        [hashtable]$Rules = $null
    )
    if (-not $Rules) { $Rules = Invoke-RegimeDetectorAudit }

    $rule = $Rules[$RegimeLabel]
    if ($rule -and $rule.passivize) {
        return "NEUTRAL"  # Detector não tem poder discriminativo neste regime
    }
    return $RegimeLabel  # Passa através
}

function Audit-RegimeDetectorLive {
    # Valida regime detector live: testa últimas 50 decisões,
    # mostra accuracy por regime, flageia BULL_WEAK se <45%
    param(
        [string]$GradesPath = "journal/decision_grades.jsonl",
        [int]$SampleSize = 50
    )
    if (-not (Test-Path $GradesPath)) { return }

    $all = @(Get-Content $GradesPath | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} } | Where-Object { $_ })
    $recent = @($all | Select-Object -Last $SampleSize)

    Write-Host "[REGIME AUDIT] Últimas $($recent.Count) decisões" -ForegroundColor Cyan
    $byRegime = $recent | Group-Object regime | ForEach-Object {
        $c = ($_.Group | Measure-Object -Sum correct).Sum
        $n = $_.Count
        $acc = $c / [math]::Max(1, $n)
        @{ regime = $_.Name; n = $n; correct = $c; accuracy = $acc }
    }

    $byRegime | Sort-Object accuracy -Descending | ForEach-Object {
        $flag = if ($_.accuracy -lt 0.45 -and $_.n -ge 15) { " ⚠️ PASSIVIZE" } else { "" }
        "  {0,-18} n={1,3} acc={2:P1}{3}" -f $_.regime, $_.n, $_.accuracy, $flag
    }
}

