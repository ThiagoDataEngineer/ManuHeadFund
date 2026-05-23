# lib_mentor_invariants.ps1 -- B4 prevention pre-LLM 2026-05-20 PM6+260min.
#
# Defense in depth: mesmo apos PM6 fix de 4 modes ortogonais, payload corrompido
# (ex: vindo de replay, recovery, ou bug futuro no mapper) deve falhar fast SEM
# queimar 1 LLM call ($0.006/eventos).
#
# Invariantes (tier=triagem quality, mode=autorizacao regime):
#   A + TIER_A_LIVE  ✓  (high quality + regime ok)
#   A + TIER_A_PAPER ✓  (high quality + regime defensivo)
#   B + TIER_B_PAPER ✓  (paper validation)
#   B + TIER_A_LIVE  ✗  (qualidade insuficiente pra LIVE)
#   C + qualquer     ✗  (exceto GEM)
#   D + qualquer     ✗  (skip absoluto, exceto GEM)
#   *  + GEM         ✓  (path separado, sem invariante)
#
# PS 5.1, UTF-8 BOM.

function Test-MentorPayloadInvariant {
    [CmdletBinding()]
    param(
        [Parameter()] [AllowEmptyString()] [string] $TriagemTier = "",
        [Parameter()] [AllowEmptyString()] [string] $MentorMode  = ""
    )

    # GEM path: mode separado, sem invariante de tier
    if ($MentorMode -eq "GEM") {
        return [PSCustomObject]@{ valid = $true; reason = "gem_path_no_invariant" }
    }

    # Payload incompleto
    if ([string]::IsNullOrEmpty($TriagemTier)) {
        return [PSCustomObject]@{ valid = $false; reason = "payload_incompleto_tier_vazio" }
    }
    if ([string]::IsNullOrEmpty($MentorMode)) {
        return [PSCustomObject]@{ valid = $false; reason = "payload_incompleto_mode_vazio" }
    }

    $T = $TriagemTier.ToUpper()
    $M = $MentorMode.ToUpper()

    # Matrix coerente
    switch ("$T|$M") {
        "A|TIER_A_LIVE"  { return [PSCustomObject]@{ valid = $true; reason = "ok" } }
        "A|TIER_A_PAPER" { return [PSCustomObject]@{ valid = $true; reason = "ok" } }
        "B|TIER_B_PAPER" { return [PSCustomObject]@{ valid = $true; reason = "ok" } }
        "B|TIER_A_PAPER" { return [PSCustomObject]@{ valid = $true; reason = "ok_b_can_promote_to_paper_a" } }
    }

    # Casos invalidos explicitos
    if ($T -eq "A" -and $M -eq "TIER_B_PAPER") {
        return [PSCustomObject]@{
            valid  = $false
            reason = "conflito_mutual_exclusion_tier_A_com_TIER_B_PAPER"
        }
    }
    if ($T -in @("C","D")) {
        return [PSCustomObject]@{
            valid  = $false
            reason = "qualidade_insuficiente_tier_${T}_para_${M}"
        }
    }
    if ($T -eq "B" -and $M -eq "TIER_A_LIVE") {
        return [PSCustomObject]@{
            valid  = $false
            reason = "tier_B_nao_pode_ir_direto_para_TIER_A_LIVE_sem_paper_validation"
        }
    }

    # Catchall — combo nao previsto = reject (fail-closed)
    return [PSCustomObject]@{
        valid  = $false
        reason = "combo_nao_previsto_tier_${T}_mode_${M}"
    }
}
