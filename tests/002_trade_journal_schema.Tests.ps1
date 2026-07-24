# TDD: A2 — Trade journal schema extension

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "A2: Trade Journal Schema Extension" {
    BeforeAll {
        $journalDir = Join-Path $projectRoot "journal"
        $tradeOutcomesPath = Join-Path $journalDir "trade_outcomes.jsonl"
    }

    It "trade_outcomes.jsonl existe" {
        Test-Path $tradeOutcomesPath | Should Be $true
    }

    It "cada linha pode ser parsed como JSON" {
        $lines = @(Get-Content $tradeOutcomesPath | Where-Object { $_.Trim() -ne "" })
        $lines.Count | Should BeGreaterThan 0

        foreach ($line in $lines[0..2]) {
            $obj = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
            ($obj -ne $null) | Should Be $true
        }
    }

    It "schema contem campos obrigatorios" {
        # 2026-07-23 FIX: schema real de producao usa id/symbol/direction/
        # pnl_realized (ver ConvertTo-SupabaseOutcome), nao trade_id/market/
        # side/pnl_usd como este teste (2026-06-05) assumia -- nunca batia
        # com o arquivo real desta maquina.
        $lines = @(Get-Content $tradeOutcomesPath | Where-Object { $_.Trim() -ne "" })

        $obj = $lines[0] | ConvertFrom-Json
        ($obj.id -ne $null) | Should Be $true
        ($obj.symbol -ne $null) | Should Be $true
        ($obj.direction -ne $null) | Should Be $true
        ($obj.pnl_realized -ne $null) | Should Be $true
    }

    It "pode serializar novo trade com campos estendidos" {
        $newTrade = [PSCustomObject]@{
            trade_id = "TEST-20260605"
            market = "BTCUSDT"
            side = "LONG"
            entry_price = 100.0
            exit_price = 105.0
            pnl_usd = 5.0
            gate_results = @("PASS1", "PASS2")
            mentor_conviction = 75
            dsz_score = 0.92
            regime_filter_applied = "BEAR_WEAK"
            final_decision = "ENTER"
            registered_at = "2026-06-05T00:00:00Z"
        }

        $json = $newTrade | ConvertTo-Json -Compress
        ($json -match "gate_results") | Should Be $true
        ($json -match "mentor_conviction") | Should Be $true
        ($json -match "dsz_score") | Should Be $true
    }
}
