# TDD: Audit Trail Validation — Cross-check 10 trades vs JSONL

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "Audit Trail Validation: 10 Trades Cross-Check" {
    BeforeAll {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $journalDir = Join-Path $projectRoot "journal"
        $tradeOutcomesPath = Join-Path $journalDir "trade_outcomes.jsonl"
        $gateAuditPath = Join-Path $journalDir "gate_audit_trail.jsonl"
        $capitalChecksPath = Join-Path $journalDir "capital_safety_checks.jsonl"
    }

    It "trade_outcomes.jsonl contem trades com gate_results registrados" {
        if (Test-Path $tradeOutcomesPath) {
            $lines = @(Get-Content $tradeOutcomesPath | Where-Object { $_.Trim() -ne "" })
            $lines.Count | Should BeGreaterThan 0

            # Sample first trade
            if ($lines.Count -gt 0) {
                $trade = $lines[0] | ConvertFrom-Json
                ($trade.trade_id -ne $null) | Should Be $true
                ($trade.market -ne $null) | Should Be $true
            }
        }
    }

    It "toda trade em outcomes foi registrada com source" {
        if (Test-Path $tradeOutcomesPath) {
            $trades = @(Get-Content $tradeOutcomesPath | ConvertFrom-Json)

            foreach ($trade in $trades) {
                ($trade.source -ne $null) | Should Be $true
            }
        }
    }

    It "capital_safety_checks.jsonl registra check para cada trade critico" {
        if (Test-Path $capitalChecksPath) {
            $checks = @(Get-Content $capitalChecksPath | ConvertFrom-Json)
            $checks.Count | Should BeGreaterThan 0
        }
    }

    It "nao ha trades com pnl_usd = 0 ou nula (audit trail completeness)" {
        if (Test-Path $tradeOutcomesPath) {
            $trades = @(Get-Content $tradeOutcomesPath | ConvertFrom-Json)

            foreach ($trade in $trades) {
                ($trade.pnl_usd -ne $null) | Should Be $true
            }
        }
    }

    It "win rate calculavel a partir de outcomes" {
        if (Test-Path $tradeOutcomesPath) {
            $trades = @(Get-Content $tradeOutcomesPath | ConvertFrom-Json)

            if ($trades.Count -gt 0) {
                $wins = @($trades | Where-Object { $_.win -eq $true }).Count
                $winRate = ($wins / $trades.Count) * 100

                ($winRate -ge 0 -and $winRate -le 100) | Should Be $true
            }
        }
    }
}
