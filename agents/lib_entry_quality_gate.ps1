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
#
# 2026-08-14 FIX (achado real, auditoria de volume de entradas): Regra 1
# tratava o veredito do FALLBACK deterministico (Invoke-TechFallback, score
# generico multi-indicador SEM piso de confluencia) com o mesmo peso de um
# veredito real do LLM. Producao real: LINKUSDT SHORT bloqueado 14x
# seguidas (varios ciclos, ~3h) com TORI conviction=80-100 (>=3 fatores de
# confluencia real medida, Regra de Ouro #4) contra tech=LONG vindo do
# fallback (Claude indisponivel na sessao) -- nunca um LLM real opinando,
# so a soma ponderada crua de scripts/tech_agent.ps1, que nao exige NENHUMA
# confluencia minima pra dar um veredito. Contradicao de direcao contra um
# LLM real continua bloqueando (mantém fail-closed onde ha 2 opinioes
# genuinamente qualificadas); contra o fallback, so bloqueia quando o
# proprio trade tem conviction baixa (<70) -- ou seja, quando NENHUM dos
# dois lados tem sinal forte, mantém cautela; quando o trade ja tem
# confluencia forte medida, o fallback generico deixa de ter poder de veto.

function Test-EntryQualityGate {
    [CmdletBinding()]
    param(
        [string] $TradeDirection = "LONG",
        [string] $TechConsensus  = "",      # LONG / SHORT / NEUTRO / LONG-FORTE / SHORT-FORTE...
        [bool]   $LlmFallback    = $false,  # true = LLM caiu, decisao sem cerebro
        [int]    $Conviction     = 0,
        [int]    $MesaScore      = 0,
        [string] $ChartStatus    = "",
        [int]    $FallbackContradictionConvictionFloor = 70
    )
    $reasons = New-Object System.Collections.ArrayList
    $td = "$TradeDirection".ToUpper()
    $tc = "$TechConsensus".ToUpper()
    $tcLong  = ($tc -match 'LONG')
    $tcShort = ($tc -match 'SHORT')

    # Regra 1: contradicao de direcao (so bloqueia quando o consenso tem direcao OPOSTA clara).
    # Se a fonte do consenso e o FALLBACK deterministico (nao LLM real), so
    # bloqueia quando o proprio trade tem conviction abaixo do piso -- um
    # trade com confluencia forte ja medida (>=70) nao deve ser vetado por
    # um score generico sem confluencia nenhuma.
    $directionContradicts = (($td -eq "LONG" -and $tcShort -and -not $tcLong) -or ($td -eq "SHORT" -and $tcLong -and -not $tcShort))
    if ($directionContradicts -and (-not $LlmFallback -or $Conviction -lt $FallbackContradictionConvictionFloor)) {
        if ($td -eq "LONG")  { [void]$reasons.Add("direction_contradiction_tech_SHORT_vs_trade_LONG") }
        if ($td -eq "SHORT") { [void]$reasons.Add("direction_contradiction_tech_LONG_vs_trade_SHORT") }
    }

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
