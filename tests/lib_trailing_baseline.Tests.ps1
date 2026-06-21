# lib_trailing_baseline.Tests.ps1 -- TDD do baseline runner (comparar ATUAL vs NOVAS).
# Carrega dados reais de journal/candles_coinex/, simula entradas hipoteticas,
# roda Invoke-ExitReplay com politica ATUAL vs NOVAS, compara metricas.
# Disciplina: baseline ATUAL é hipótese (a política que vem rodando hoje),
# não é verdade revelada — pode ser melhorado.

$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_exit_backtest.ps1")
. (Join-Path $agentsDir "lib_trailing_policy.ps1")
. (Join-Path $agentsDir "lib_trailing_baseline.ps1")

Describe "Get-CurrentTrailingPolicy -- codifica o ATUAL" {

    It "Retorna hashtable com strategy proxima do que roda hoje" {
        $p = Get-CurrentTrailingPolicy
        $p | Should Not BeNullOrEmpty
        $p.breakeven_at_r | Should Be 1.0
        $p.trail_atr_mult | Should BeGreaterThan 2.0
    }
}

Describe "Invoke-BaselineComparison -- roda ATUAL vs NOVAS sobre dados reais" {

    It "BTCUSDT 1 entrada a cada 100 barras: ATUAL vs swing LONG >= 5 comparacoes" {
        $candles = Get-CandlesFromFile -Ticker "BTCUSDT"
        $result = Invoke-BaselineComparison -Candles $candles -EntryFrequency 100 -MaxEntries 5

        $result | Should Not BeNullOrEmpty
        $result.atual | Should Not BeNullOrEmpty
        $result.swing_long | Should Not BeNullOrEmpty

        $result.atual | Where-Object { $_ } | Measure-Object | ForEach-Object { $_.Count } | Should BeGreaterThan 0
    }

    It "Stats: ATUAL win_rate + capture visivel (nao nulos)" {
        $candles = Get-CandlesFromFile -Ticker "BTCUSDT"
        $result = Invoke-BaselineComparison -Candles $candles -EntryFrequency 100 -MaxEntries 5

        $stats_atual = Get-ExitReplayStats -Outcomes $result.atual
        $stats_atual.n | Should BeGreaterThan 0
        $stats_atual.win_rate | Should Not BeNullOrEmpty
        $stats_atual.avg_capture | Should Not BeNullOrEmpty
    }
}

Describe "Format-BaselineReport -- formatação pra saida" {

    It "Agrupa stats por politica, mostra delta" {
        $stats = @{
            atual = Get-ExitReplayStats -Outcomes @(
                [PSCustomObject]@{ r=1.0; mfe_r=2.0; capture_ratio=0.5 },
                [PSCustomObject]@{ r=2.0; mfe_r=2.5; capture_ratio=0.8 }
            )
            swing_long = Get-ExitReplayStats -Outcomes @(
                [PSCustomObject]@{ r=1.5; mfe_r=2.0; capture_ratio=0.75 },
                [PSCustomObject]@{ r=2.5; mfe_r=3.0; capture_ratio=0.83 }
            )
        }

        $fmt = Format-BaselineReport -Stats $stats
        $fmt | Should Match "ATUAL"
        $fmt | Should Match "swing_long"
        $fmt | Should Match "avg_r|capture"
    }
}
