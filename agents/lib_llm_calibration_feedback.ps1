# lib_llm_calibration_feedback.ps1 — Placar de acerto do LLM injetado no prompt
# 2026-07-04: AUTO-APRENDIZADO funcional. grade_llm_decisions.ps1 grada cada
# decisao (APROVAR/VETAR) 48h depois contra candles reais e agrega em
# journal/llm_calibration.json. Esta lib formata o bolso relevante
# (direction|regime atual) como bloco [CALIBRACAO] pro mentor decidir SABENDO
# onde historicamente erra. Prior bayesiano, nao ordem — a decisao segue dele.
# Bootstrap 2026-07-04 (300 decisoes): APROVAR|LONG|BULL_STRONG acc 15%;
# VETAR|SHORT|BEAR_WEAK acc 36% (n=42) — vieses reais e mensuraveis.

function Get-LlmCalibrationBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Direction,
        [Parameter(Mandatory)] [string] $Regime,
        [string] $CalibrationPath = "",
        [int] $MinN = 8
    )

    if (-not $CalibrationPath) {
        $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" }
        $CalibrationPath = Join-Path $journalDir "llm_calibration.json"
    }
    if (-not (Test-Path $CalibrationPath)) { return "" }

    $calib = $null
    try { $calib = Get-Content $CalibrationPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return "" }
    if (-not $calib) { return "" }

    $dir = $Direction.ToUpper()
    $reg = $Regime.ToUpper()
    $rows = @($calib | Where-Object { $_.direction -eq $dir -and $_.regime -eq $reg -and $_.n -ge $MinN })
    if ($rows.Count -eq 0) { return "" }

    $lines = @("[CALIBRACAO] Seu historico GRADEADO vs mercado real (D+2) neste bolso ($dir|$reg):")
    foreach ($r in ($rows | Sort-Object decision)) {
        $accPct = [math]::Round($r.accuracy * 100)
        $errPct = 100 - $accPct
        $hint = ""
        if ($r.decision -eq "VETAR" -and $r.accuracy -lt 0.45) {
            $hint = " -> voce VETA DEMAIS aqui (mercado provou o veto errado $errPct% das vezes); exija razao FORTE para vetar."
        } elseif ($r.decision -eq "APROVAR" -and $r.accuracy -lt 0.45) {
            $hint = " -> voce APROVA DEMAIS aqui (mercado foi contra $errPct% das vezes); exija confluencia extra para aprovar."
        } elseif ($r.accuracy -ge 0.6) {
            $hint = " -> historico bom; mantenha o criterio."
        }
        $lines += ("  {0}: acerto {1}% (n={2}, mercado andou {3}% na direcao proposta){4}" -f $r.decision, $accPct, $r.n, $r.avg_move_dir, $hint)
    }
    $lines += "Use como PRIOR (peso bayesiano), nao como ordem — julgue o setup atual pelos dados dele."
    return ($lines -join "`n")
}
