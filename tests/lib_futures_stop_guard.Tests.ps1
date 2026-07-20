# lib_futures_stop_guard.Tests.ps1 -- Pester 3.x
# TDD 2026-06-23: evolui o futures (fail-closed) analogo ao spot.
# Futures SL e exchange-side (mark-price, fecha a mercado) = solido QUANDO setado.
# Furos: (1) posicao nua (sem SL) nao rastreada no journal; (2) sem fallback se ja furou.
# Resolve-FuturesStopGuard (PURO) cobre os dois. Nao duplica Sync-TrailingToExchange
# (que so MELHORA SL existente); aqui so age quando NAO ha protecao.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_futures_stop_guard.ps1")

Describe "Resolve-FuturesStopGuard - LONG" {
    It "Sem SL na corretora + nao furou -> SET (fail-closed)" {
        $r = Resolve-FuturesStopGuard -Side "LONG" -MarkPrice 100 -ExchangeStop 0 -PlannedStop 90 -HasPosition $true
        $r.action | Should Be "SET"
        $r.stop | Should Be 90
    }
    It "Sem SL + JA furou (mark <= planned) -> CLOSE_FALLBACK (deveria ter parado)" {
        $r = Resolve-FuturesStopGuard -Side "LONG" -MarkPrice 85 -ExchangeStop 0 -PlannedStop 90 -HasPosition $true
        $r.action | Should Be "CLOSE_FALLBACK"
    }
    It "Com SL na corretora -> OK (Sync cuida do trailing)" {
        $r = Resolve-FuturesStopGuard -Side "LONG" -MarkPrice 100 -ExchangeStop 90 -PlannedStop 92 -HasPosition $true
        $r.action | Should Be "OK"
    }
}

Describe "Resolve-FuturesStopGuard - SHORT (espelhado)" {
    It "Sem SL + nao furou -> SET" {
        $r = Resolve-FuturesStopGuard -Side "SHORT" -MarkPrice 100 -ExchangeStop 0 -PlannedStop 110 -HasPosition $true
        $r.action | Should Be "SET"
        $r.stop | Should Be 110
    }
    It "Sem SL + JA furou (mark >= planned) -> CLOSE_FALLBACK" {
        $r = Resolve-FuturesStopGuard -Side "SHORT" -MarkPrice 115 -ExchangeStop 0 -PlannedStop 110 -HasPosition $true
        $r.action | Should Be "CLOSE_FALLBACK"
    }
}

Describe "Resolve-FuturesStopGuard - guardas fail-safe" {
    It "Sem posicao -> NONE" {
        (Resolve-FuturesStopGuard -Side "LONG" -MarkPrice 100 -ExchangeStop 0 -PlannedStop 90 -HasPosition $false).action | Should Be "NONE"
    }
    It "PlannedStop invalido -> NONE (nunca chuta stop)" {
        (Resolve-FuturesStopGuard -Side "LONG" -MarkPrice 100 -ExchangeStop 0 -PlannedStop 0 -HasPosition $true).action | Should Be "NONE"
    }
    It "Mark <= 0 (ticker furado) -> NONE (nao fecha por dado ruim)" {
        (Resolve-FuturesStopGuard -Side "LONG" -MarkPrice 0 -ExchangeStop 0 -PlannedStop 90 -HasPosition $true).action | Should Be "NONE"
    }
}
