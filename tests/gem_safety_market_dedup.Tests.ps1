# gem_safety_market_dedup.Tests.ps1 -- TDD dedup per-market (2026-06-05)
#
# Incidente 2026-06-05: gem_loop re-entrou FIRO 4x / PEPE2 2x / BABY 4x porque
# Test-GemSafetyGuards NUNCA checava se o mercado especifico ja estava em
# open_positions. Este guard fecha o buraco: -Market ja aberto => BLOCK.
# Modo de falha seguro: skip (over-conservador) e' melhor que duplicar.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_gem_safety.ps1")

$script:TestStateDir  = Join-Path $env:TEMP "gem_safety_dedup_tests"
$script:TestStateFile = Join-Path $script:TestStateDir "gem_safety_state.json"

function New-DedupTestState {
    param([array] $OpenPositions = @())
    if (-not (Test-Path $script:TestStateDir)) {
        New-Item -ItemType Directory -Path $script:TestStateDir -Force | Out-Null
    }
    $today = (Get-Date).Date
    $dow   = [int]$today.DayOfWeek
    $diff  = if ($dow -eq 0) { -6 } else { 1 - $dow }
    $state = @{
        open_positions     = $OpenPositions
        daily_count        = 0
        daily_reset_date   = (Get-Date).ToString("yyyy-MM-dd")
        weekly_count       = 0
        weekly_reset_date  = $today.AddDays($diff).ToString("yyyy-MM-dd")
        consecutive_stops  = 0
        last_trade_result  = $null
        last_updated       = (Get-Date).ToString("o")
    }
    ($state | ConvertTo-Json -Depth 6) | Out-File -FilePath $script:TestStateFile -Encoding utf8 -Force
}

Describe "GEM dedup per-market" {

    It "BLOQUEIA re-entrada quando market ja esta em open_positions" {
        New-DedupTestState -OpenPositions @(@{ market="FIROUSDT"; size_usdt=18.0; entry_ts="x" })
        $r = Test-GemSafetyGuards -TradeSizeUsdt 18.0 -TotalCapitalUsdt 3500.0 -Market "FIROUSDT" -StateFilePath $script:TestStateFile
        $r.allowed | Should Be $false
        $r.reason  | Should Be "market_already_open"
    }

    It "PERMITE quando market NAO esta aberto (outro mercado aberto)" {
        New-DedupTestState -OpenPositions @(@{ market="OPNUSDT"; size_usdt=18.0; entry_ts="x" })
        $r = Test-GemSafetyGuards -TradeSizeUsdt 18.0 -TotalCapitalUsdt 3500.0 -Market "FIROUSDT" -StateFilePath $script:TestStateFile
        $r.allowed | Should Be $true
        $r.reason  | Should Be "ok"
    }

    It "PERMITE quando nenhum mercado aberto" {
        New-DedupTestState -OpenPositions @()
        $r = Test-GemSafetyGuards -TradeSizeUsdt 18.0 -TotalCapitalUsdt 3500.0 -Market "FIROUSDT" -StateFilePath $script:TestStateFile
        $r.allowed | Should Be $true
    }

    It "BACK-COMPAT: sem -Market, nao bloqueia por dedup (callers antigos)" {
        New-DedupTestState -OpenPositions @(@{ market="FIROUSDT"; size_usdt=18.0; entry_ts="x" })
        $r = Test-GemSafetyGuards -TradeSizeUsdt 18.0 -TotalCapitalUsdt 3500.0 -StateFilePath $script:TestStateFile
        $r.allowed | Should Be $true
    }

    It "dedup tem precedencia sobre outros blocks (reason explicito)" {
        # market aberto E exposure ja alta -> reason deve ser market_already_open
        New-DedupTestState -OpenPositions @(@{ market="FIROUSDT"; size_usdt=600.0; entry_ts="x" })
        $r = Test-GemSafetyGuards -TradeSizeUsdt 18.0 -TotalCapitalUsdt 3500.0 -Market "FIROUSDT" -StateFilePath $script:TestStateFile
        $r.allowed | Should Be $false
        $r.reason  | Should Be "market_already_open"
    }

    It "match e' case-insensitive e exato (firousdt == FIROUSDT)" {
        New-DedupTestState -OpenPositions @(@{ market="FIROUSDT"; size_usdt=18.0; entry_ts="x" })
        $r = Test-GemSafetyGuards -TradeSizeUsdt 18.0 -TotalCapitalUsdt 3500.0 -Market "firousdt" -StateFilePath $script:TestStateFile
        $r.allowed | Should Be $false
        $r.reason  | Should Be "market_already_open"
    }
}
