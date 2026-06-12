# lib_position_price.ps1 -- Resolucao de preco de posicao.
# Problema: CoinEx retorna mark_price=0 pra muitos micro-caps (MON/BABY/ENA...).
# O watcher pulava a gestao (continue) -> posicao SEM stop/trailing = capital cego.
# Aqui: fallback determinístico pro ticker 'last' + pnl price-based. PS 5.1. UTF-8 BOM.

function Test-PriceUsable {
    # $true se o preco e um numero utilizavel (> 0).
    param([Parameter(Mandatory)] [double] $Price)
    return ($Price -gt 0)
}

function Resolve-MarkPrice {
    # Retorna o preco efetivo a usar: mark se valido (>0), senao o ticker last se
    # valido, senao 0 (caller deve pular o ciclo). Resolve o bug mark_price=0.
    param(
        [Parameter(Mandatory)] [double] $Mark,
        [Parameter(Mandatory)] [double] $TickerLast
    )
    if ($Mark -gt 0)       { return $Mark }
    if ($TickerLast -gt 0) { return $TickerLast }
    return 0
}

function Get-PositionPnlPct {
    # PnL percentual baseado em PRECO (sem leverage). LONG: (price-entry)/entry.
    # SHORT: (entry-price)/entry. Retorna 0 se entry ou price invalidos.
    param(
        [Parameter(Mandatory)] [double] $Price,
        [Parameter(Mandatory)] [double] $Entry,
        [Parameter(Mandatory=$false)] [string] $Side = "long"
    )
    if ($Entry -le 0 -or $Price -le 0) { return 0 }
    $raw = (($Price - $Entry) / $Entry) * 100
    if ($Side -and $Side.ToLower() -eq "short") { return (-1 * $raw) }
    return $raw
}
