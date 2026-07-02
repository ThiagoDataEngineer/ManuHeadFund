# lib_entry_quality_gate.ps1 -- Gate FAIL-CLOSED de qualidade de entrada.
#
# Regra de Ouro #5: erro/ausencia = BLOCK, nunca passa por default. Hoje o executor
# e fail-OPEN (conviction=0 passa, chart insufficient passa, LLM caido entra). Este
# gate fecha as duas brechas mais perigosas vistas em producao (run #677):
#  1. CONTRADICAO DE DIRECAO: comprar LONG quando o unico sinal tecnico diz SHORT
#     (ou vender SHORT quando diz LONG) -> trade contra o proprio sinal -> BLOCK.
#  2. ENTRADA CEGA: LLM indisponivel (fallback) E conviction=0 E mesa=0 E chart
#     sem dados -> nenhuma analise real -> BLOCK.
# Caso contrario: ALLOW (nao paralisa o pipeline quando ha QUALQUER sinal real).
# PURO, sem I/O. 100% TDD-able. PS 5.1 safe.

function Test-EntryQualityGate {
    [CmdletBinding()]
    param(
        [string] $TradeDirection = "LONG",
        [string] $TechConsensus  = "",      # LONG / SHORT / NEUTRO / LONG-FORTE / SHORT-FORTE...
        [bool]   $LlmFallback    = $false,  # true = LLM caiu, decisao sem cerebro
        [int]    $Conviction     = 0,
        [int]    $MesaScore      = 0,
        [string] $ChartStatus    = ""
    )
    $reasons = New-Object System.Collections.ArrayList
    $td = "$TradeDirection".ToUpper()
    $tc = "$TechConsensus".ToUpper()
    $tcLong  = ($tc -match 'LONG')
    $tcShort = ($tc -match 'SHORT')

    # Regra 1: contradicao de direcao (so bloqueia quando o consenso tem direcao OPOSTA clara)
    if ($td -eq "LONG"  -and $tcShort -and -not $tcLong) { [void]$reasons.Add("direction_contradiction_tech_SHORT_vs_trade_LONG") }
    if ($td -eq "SHORT" -and $tcLong  -and -not $tcShort) { [void]$reasons.Add("direction_contradiction_tech_LONG_vs_trade_SHORT") }

    # Regra 2: entrada cega (sem nenhuma fonte de sinal real)
    $chartBlind = ([string]::IsNullOrWhiteSpace($ChartStatus)) -or ($ChartStatus -match 'insufficient|n/?a|absent|sem dados|null|no_data')
    if ($LlmFallback -and $Conviction -le 0 -and $MesaScore -le 0 -and $chartBlind) {
        [void]$reasons.Add("blind_entry_no_llm_no_conviction_no_chart")
    }

    $allow = ($reasons.Count -eq 0)
    return [PSCustomObject]@{
        allow   = $allow
        blocked = (-not $allow)
        reasons = @($reasons)
    }
}
