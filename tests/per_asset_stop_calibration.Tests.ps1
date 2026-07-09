# per_asset_stop_calibration.Tests.ps1 — TDD auditor trailing (Pester 3.4) — 2026-07-09
# Problema (audit 2026-07-08): StopPct=0.08 hardcoded p/ TODOS os assets ->
# wick de microcap vol alta estoura o stop (falso-positivo ~70% dos losses),
# e blue-chip vol baixa desperdica 8% de risco sem necessidade.
# Contrato:
#   Get-PerAssetStopPct -Candles c [-Multiplier k] [-FallbackPct 0.08]
#     -> @{ stop_pct; source='atr'|'fallback'; atr_pct }
#   - ATR%(14) * k, clamp [0.02, 0.12]
#   - Sem candles suficientes -> fallback 0.08 (comportamento legado preservado)

$here = Split-Path $PSScriptRoot -Parent
. (Join-Path $here "agents\lib_stop_loss_calibration_study.ps1")

function New-TestCandles {
    # Gera N candles com range (high-low) controlado em % do preco
    param([double]$Price = 100.0, [double]$RangePct = 0.02, [int]$N = 30)
    $candles = @()
    for ($i = 0; $i -lt $N; $i++) {
        $candles += [PSCustomObject]@{
            open  = $Price
            high  = $Price * (1 + $RangePct / 2)
            low   = $Price * (1 - $RangePct / 2)
            close = $Price
        }
    }
    return $candles
}

Describe "Get-PerAssetStopPct (calibracao per-asset via ATR)" {

    It "vol ALTA (range 6%) -> stop mais largo que vol baixa (range 1%)" {
        $hi = Get-PerAssetStopPct -Candles (New-TestCandles -RangePct 0.06)
        $lo = Get-PerAssetStopPct -Candles (New-TestCandles -RangePct 0.01)
        ($hi.stop_pct -gt $lo.stop_pct) | Should Be $true
        $hi.source | Should Be "atr"
        $lo.source | Should Be "atr"
    }

    It "clamp superior: vol extrema (range 30%) nao passa de 12%" {
        $r = Get-PerAssetStopPct -Candles (New-TestCandles -RangePct 0.30)
        $r.stop_pct | Should Be 0.12
    }

    It "clamp inferior: vol minuscula (range 0.2%) nao fica abaixo de 2%" {
        $r = Get-PerAssetStopPct -Candles (New-TestCandles -RangePct 0.002)
        $r.stop_pct | Should Be 0.02
    }

    It "sem candles -> fallback 8% legado (fail-safe, nunca quebra)" {
        $r = Get-PerAssetStopPct -Candles @()
        $r.stop_pct | Should Be 0.08
        $r.source | Should Be "fallback"
    }

    It "candles insuficientes (<15) -> fallback" {
        $r = Get-PerAssetStopPct -Candles (New-TestCandles -N 5)
        $r.source | Should Be "fallback"
    }

    It "multiplier maior -> stop proporcionalmente maior (dentro dos clamps)" {
        $k2 = Get-PerAssetStopPct -Candles (New-TestCandles -RangePct 0.02) -Multiplier 2.0
        $k3 = Get-PerAssetStopPct -Candles (New-TestCandles -RangePct 0.02) -Multiplier 3.0
        ($k3.stop_pct -gt $k2.stop_pct) | Should Be $true
    }

    It "caso wick-killer real: microcap range 5% com k=2.5 -> stop ~12% (nao 8%)" {
        # Range 5%/candle ~ ATR 5% -> 2.5*5% = 12.5% -> clamp 12%.
        # Com 8% fixo, wick normal de 1 candle ja chegava perto do stop.
        $r = Get-PerAssetStopPct -Candles (New-TestCandles -RangePct 0.05) -Multiplier 2.5
        $r.stop_pct | Should Be 0.12
    }
}
