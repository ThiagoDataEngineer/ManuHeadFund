# lib_trailing_origin_backfill.ps1 -- decisao PURA de backfill de origin.
#
# 2026-08-06: achado real em producao -- ARBUSDT/NEARUSDT/OPUSDT (abertas
# via regime_surf ANTES do fix de Register-PositionTrailing/-Origin, commit
# c0f9f6e) tem origin.asset_class="UNKNOWN" gravado no trailing_state.
# trailing_stop_monitor.ps1 usa $tuIsFutures = (origin.asset_class -eq
# "FUTURES") pra decidir se chama CoinEx-ModifyPositionStopLoss (push real)
# ou so atualiza o journal -- com UNKNOWN, o motor CALCULA o novo stop
# corretamente (journal.stopCurrent "avanca"), mas NUNCA envia pra
# corretora de verdade. A posicao fica com a aparencia de progresso
# (trailing "ativo") sem a protecao real ter mudado na CoinEx.
#
# Fix: corrigir origin.asset_class="FUTURES" nos registros que SAO FUTURES
# reais (confirmado via CoinEx-GetPendingPositions, fonte de verdade) mas
# tem origin ausente/UNKNOWN -- so escreve no journal (Supabase), nunca
# toca em ordem/posicao real na corretora.

# ─────────────────────────────────────────────────────────────────────────
# Test-OriginNeedsBackfill (PURA) -- decide se um registro precisa de
# correcao de origin, dado o estado real da posicao na corretora.
# ─────────────────────────────────────────────────────────────────────────
function Test-OriginNeedsBackfill {
    <#
    .SYNOPSIS
    Decide (pura, sem I/O) se um registro trailing_state precisa ter
    origin.asset_class corrigido pra FUTURES.

    .PARAMETER JournalOrigin
    Objeto origin cru do registro (pode ser $null, string, ou hashtable/
    PSCustomObject com .asset_class/.trade_style).

    .PARAMETER IsRealFutures
    $true se CoinEx-GetPendingPositions confirma que esta posicao existe
    como FUTURES real agora (fonte de verdade -- nunca adivinha).

    .OUTPUTS
    [bool] $true = precisa backfill (origin.asset_class virar FUTURES)
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        $JournalOrigin,
        [Parameter(Mandatory)] [bool] $IsRealFutures
    )

    if (-not $IsRealFutures) { return $false }  # so corrige o que e FUTURES real confirmado

    if ($null -eq $JournalOrigin) { return $true }  # origin=null (SOONUSDT/PIPPINUSDT case)

    $assetClass = $null
    if ($JournalOrigin -is [string]) {
        try { $assetClass = ($JournalOrigin | ConvertFrom-Json).asset_class } catch { return $true }
    } elseif ($JournalOrigin.PSObject.Properties['asset_class']) {
        $assetClass = $JournalOrigin.asset_class
    }

    if (-not $assetClass -or "$assetClass".ToUpper() -eq "UNKNOWN") { return $true }
    if ("$assetClass".ToUpper() -eq "FUTURES") { return $false }  # ja correto, nao mexe

    # asset_class diverge (ex: diz "SPOT" mas e FUTURES real) -- corrige,
    # nao confia em dado que contradiz a fonte de verdade da corretora.
    return $true
}

# ─────────────────────────────────────────────────────────────────────────
# Resolve-BackfilledOrigin (PURA) -- monta o novo objeto origin, preservando
# trade_style existente se ja for valido (SCALP|SWING), senao default SWING.
# ─────────────────────────────────────────────────────────────────────────
function Resolve-BackfilledOrigin {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param($JournalOrigin)

    $tradeStyle = "SWING"
    if ($JournalOrigin) {
        $existing = $null
        if ($JournalOrigin -is [string]) {
            try { $existing = ($JournalOrigin | ConvertFrom-Json).trade_style } catch {}
        } elseif ($JournalOrigin.PSObject.Properties['trade_style']) {
            $existing = $JournalOrigin.trade_style
        }
        if ($existing -and "$existing".ToUpper() -in @("SCALP","SWING")) {
            $tradeStyle = "$existing".ToUpper()
        }
    }

    return @{ asset_class = "FUTURES"; trade_style = $tradeStyle }
}
