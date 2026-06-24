# lib_futures_stop_guard.ps1 -- Fix 2026-06-23: futures fail-closed (analogo ao spot).
#
# Futures SL = exchange-side (mark_price, fecha a mercado via set-position-stop-loss) =
# SOLIDO quando setado (melhor que o stop-limit do spot). Mas dois furos:
#   1. Posicao NUA (sem SL) que nao esta no journal -> Sync-TrailingToExchange nao toca.
#   2. Sem fallback de fechar a mercado se ja furou o stop e esta nua.
# Resolve-FuturesStopGuard (PURO) cobre os dois. So age quando NAO ha protecao na
# corretora (nao duplica o Sync, que so MELHORA SL existente). PS 5.1 / UTF-8 BOM.

function Resolve-FuturesStopGuard {
    <#
      Decide protecao de uma posicao FUTURES:
        NONE            -> sem posicao / dados invalidos (nunca chuta stop)
        OK              -> ja protegida (Sync cuida do trailing)
        SET             -> nua, ainda nao furou -> setar SL exchange-side
        CLOSE_FALLBACK  -> nua E ja furou o planejado -> fechar a mercado (deveria ter parado)
    #>
    param(
        [string]$Side = "LONG",
        [double]$MarkPrice,
        [double]$ExchangeStop,
        [double]$PlannedStop,
        [bool]$HasPosition
    )
    if (-not $HasPosition -or $MarkPrice -le 0 -or $PlannedStop -le 0) {
        return @{ action="NONE"; stop=$PlannedStop; reason="sem posicao ou dados invalidos" }
    }
    $isShort = ("$Side".ToUpper() -eq "SHORT")
    $protected = ($ExchangeStop -gt 0)
    $breached = if ($isShort) { $MarkPrice -ge $PlannedStop } else { $MarkPrice -le $PlannedStop }

    if ($protected) {
        return @{ action="OK"; stop=$ExchangeStop; reason="ja tem SL na corretora" }
    }
    if ($breached) {
        return @{ action="CLOSE_FALLBACK"; stop=$PlannedStop; reason="nua e ja furou planejado ($MarkPrice vs $PlannedStop) -> fecha a mercado" }
    }
    return @{ action="SET"; stop=$PlannedStop; reason="nua -> seta SL exchange-side em $PlannedStop" }
}
