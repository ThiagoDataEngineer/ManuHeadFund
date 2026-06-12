# B1 refino 2026-05-20 PM6+: distinguir veto-early (zeros = "nao computado")
# de trade real com setup completo. Quando entry+stop+target+atr todos = 0, escreve "".

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_observation_logger.ps1")

Describe "B1 refino: veto-early formatting" {
    BeforeEach {
        $script:tmp = Join-Path $env:TEMP "b1_veto_$([guid]::NewGuid()).csv"
    }
    AfterEach {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }

    It "veto-early (entry+stop+target+atr todos 0) escreve campos vazios" {
        Add-Observation -ObsFile $tmp -Market "BTC" -Regime "BULL_WEAK" -Direction "LONG" `
            -DowBrt 3 -WhitelistTier "observe" -ScannerScore 0 `
            -EntryPrice 0 -StopPrice 0 -TargetPrice 0 -AtrProxyPct 0
        $row = Import-Csv $tmp
        $row.entry_price   | Should Be ""
        $row.stop_price    | Should Be ""
        $row.target_price  | Should Be ""
        $row.atr_proxy_pct | Should Be ""
    }

    It "trade real com setup escreve numerics formatados" {
        Add-Observation -ObsFile $tmp -Market "BTC" -Regime "BULL_WEAK" -Direction "LONG" `
            -DowBrt 3 -WhitelistTier "observe" -ScannerScore 90 `
            -EntryPrice 50000.5 -StopPrice 49000 -TargetPrice 55000 -AtrProxyPct 2.5
        $row = Import-Csv $tmp
        [double]$row.entry_price  | Should Be 50000.5
        [double]$row.stop_price   | Should Be 49000
        [double]$row.target_price | Should Be 55000
        [double]$row.atr_proxy_pct | Should Be 2.5
    }

    It "trade parcial (entry preenchido + atr=0) NAO trata como veto-early" {
        Add-Observation -ObsFile $tmp -Market "BTC" -Regime "BULL_WEAK" -Direction "LONG" `
            -DowBrt 3 -WhitelistTier "observe" -ScannerScore 80 `
            -EntryPrice 50000 -StopPrice 49000 -TargetPrice 55000 -AtrProxyPct 0
        $row = Import-Csv $tmp
        [double]$row.entry_price | Should Be 50000
        # atr=0 e legitimo (sub-dollar pode ter atr_pct trivial); so 4-de-4 zeros = veto
        $row.atr_proxy_pct | Should Be "0.0000"
    }
}
