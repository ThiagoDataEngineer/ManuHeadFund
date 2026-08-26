# lib_no_fundamental_sizing.ps1 -- Penalidade de sizing quando NAO ha
# nenhum fundamental (nem curado, nem CoinGecko) para o market.
#
# 2026-08-26: achado real (owner pediu estudo tecnico de HUMAUSDT). Sistema
# abriu LONG SPOT real em HUMAUSDT (descoberto via radar dinamico, nunca
# curado) com fqs=UNKNOWN -- Invoke-FqsLazyEnrich falhou porque o market
# nem esta mapeado em MARKET_TO_CG (backtest/coingecko_enrichment.py), e
# esse "nao consegui nem avaliar" virava bonus=0 (neutro) no calculo de
# birth_score (gem_executor.ps1:2707-2711) -- so afeta o SCORE DE REGISTRO
# pos-fato, nunca o sizing/gate real da entrada. Resultado: token sem
# NENHUMA curadoria fundamentalista (nao sabemos supply/utility/concentracao/
# eventos como unlock de token) entra com o MESMO peso de risco que um
# token bem avaliado como QUALITY/BLUE_CHIP.
#
# Get-FundamentalScore (lib_fundamental_quality.ps1) ja retorna
# category="AVOID" reason="market_not_in_registry" pra esse caso -- mas
# so e chamada no roteamento SPOT-vs-FUTURES (linha ~1866), nunca no
# sizing. Este modulo fecha esse gap: reduz sizing (nao bloqueia --
# ausencia de dado nao e prova de token ruim, so falta de informacao)
# quando a razao de falha do lazy-enrich e "nunca ouvimos falar deste
# token" (not_in_MARKET_TO_CG), distinto de falha temporaria (rate_limit,
# timeout, erro de rede) -- essas nao penalizam, sao apenas "nao deu tempo
# de tentar", nao "nao ha curadoria nenhuma".

function Resolve-NoFundamentalSizingPenalty {
    <#
    .SYNOPSIS
    Decide se e quanto reduzir o sizing quando o market nao tem NENHUM
    fundamental disponivel (nem curado, nem CoinGecko mapeado).

    .PARAMETER FqsLazyEnrichResult
    Objeto retornado por Invoke-FqsLazyEnrich (.success, .reason).

    .PARAMETER PenaltyFraction
    Fracao do sizing MANTIDA quando a penalidade se aplica (default 0.5,
    mesmo piso ja usado pelo gate de liquidez fina "STRUCTURAL CAUTION" --
    consistencia de escala entre os 2 gates de cautela por dado incompleto).

    .OUTPUTS
    PSCustomObject { apply_penalty, reason }
    apply_penalty=$true so quando a causa e ausencia real de curadoria
    (not_in_MARKET_TO_CG) -- nunca por falha temporaria/rede/rate-limit.
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject] $FqsLazyEnrichResult,
        [double] $PenaltyFraction = 0.5
    )

    if (-not $FqsLazyEnrichResult) {
        return [PSCustomObject]@{ apply_penalty = $false; reason = "sem_resultado_lazy_enrich" }
    }
    if ($FqsLazyEnrichResult.success -eq $true) {
        return [PSCustomObject]@{ apply_penalty = $false; reason = "enrich_teve_sucesso" }
    }

    $reasonText = "$($FqsLazyEnrichResult.reason)"
    # "not_eligible: not_in_MARKET_TO_CG" (Test-FqsLazyEnrichEligible) =
    # nunca ouvimos falar deste token, nao e falha temporaria.
    $isRealAbsence = $reasonText -like "*not_in_MARKET_TO_CG*"

    if (-not $isRealAbsence) {
        return [PSCustomObject]@{ apply_penalty = $false; reason = "falha_temporaria_nao_ausencia_real: $reasonText" }
    }

    return [PSCustomObject]@{
        apply_penalty  = $true
        reason         = "sem_fundamental_algum_market_desconhecido"
        penalty_fraction = $PenaltyFraction
    }
}
