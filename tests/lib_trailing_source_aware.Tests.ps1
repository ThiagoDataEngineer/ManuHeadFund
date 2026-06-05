# lib_trailing_source_aware.Tests.ps1 -- Pester 3.x
# TDD pra ONDA 1: source-aware fields (mode, max_days, dd_threshold_pct) + max_days enforcement.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"

# Isolar storage por test run (override TRAILING_FILE)
$script:tmpDir = Join-Path $env:TEMP ("trail_$([guid]::NewGuid())")
New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null

# Stubs pra evitar I/O CoinEx + Telegram durante test
function CoinEx-GetTicker { param($m) return @{ last = 100 } }
function Send-TelegramAlert { param($Message) }
function Format-TgTrailStopHit { param($Pos, $CurrentPrice) return "stop $($Pos.market)" }
function Format-TgTrailPhase { param($Pos, $OldStop, $OldPhase, $CurrentPrice) return "phase $($Pos.market)" }

# Carrega lib_feedback_loop pra Add-TradeOutcome estar disponivel
. (Join-Path $agentsDir "lib_feedback_loop.ps1")

# Dot-source direto do lib_trailing (stubs CoinEx/Telegram ja definidos acima).
# $global:TRAILING_FILE isola storage; state_store desabilitado via flag.
$global:TRAILING_FILE = Join-Path $script:tmpDir "trailing_positions.json"
$global:TRAILING_USE_STATE_STORE = $false
$env:TRAILING_USE_STATE_STORE = "0"
. (Join-Path $agentsDir "lib_trailing.ps1")


Describe "Add-TrailingPosition - source-aware fields" {
    It "Mode auto-derived from Source gem -> GEM + defaults" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "GEMUSDT" -Side "LONG" -Entry 100 -Stop 90 -Target 130 -Source "gem"
        $p = (Get-TrailingPositions | Where-Object { $_.market -eq "GEMUSDT" })
        $p.mode | Should Be "GEM"
        $p.max_days | Should Be 14
        $p.dd_threshold_pct | Should Be 40.0
    }
    It "Mode auto-derived from Source tier_a -> TIER_A + DD 25%" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "BTCUSDT" -Side "LONG" -Entry 100 -Stop 95 -Target 120 -Source "tier_a"
        $p = (Get-TrailingPositions | Where-Object { $_.market -eq "BTCUSDT" })
        $p.mode | Should Be "TIER_A"
        $p.dd_threshold_pct | Should Be 25.0
    }
    It "MaxDays explicit override default" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "ABC" -Side "LONG" -Entry 1 -Stop 0.9 -Target 1.3 -Source "gem" -MaxDays 30
        $p = (Get-TrailingPositions | Where-Object { $_.market -eq "ABC" })
        $p.max_days | Should Be 30
    }
    It "STANDARD mode (orchestrator legacy) sem max_days" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "STD" -Side "LONG" -Entry 1 -Stop 0.9 -Target 1.3 -Source "orchestrator"
        $p = (Get-TrailingPositions | Where-Object { $_.market -eq "STD" })
        $p.mode | Should Be "STANDARD"
        $p.max_days | Should Be 0
        $p.dd_threshold_pct | Should Be 30.0
    }
}


Describe "Test-MaxDaysExceeded" {
    It "posicao com max_days=0 retorna false (sem limite)" {
        $pos = [PSCustomObject]@{ openedAt = "2026-01-01 00:00:00"; max_days = 0 }
        Test-MaxDaysExceeded -Pos $pos -Now ([DateTime]"2026-12-01 00:00:00") | Should Be $false
    }
    It "posicao recent com max_days=14 retorna false" {
        $opened = (Get-Date).AddDays(-5).ToString("yyyy-MM-dd HH:mm:ss")
        $pos = [PSCustomObject]@{ openedAt = $opened; max_days = 14 }
        Test-MaxDaysExceeded -Pos $pos | Should Be $false
    }
    It "posicao old com max_days=14 retorna true" {
        $opened = (Get-Date).AddDays(-20).ToString("yyyy-MM-dd HH:mm:ss")
        $pos = [PSCustomObject]@{ openedAt = $opened; max_days = 14 }
        Test-MaxDaysExceeded -Pos $pos | Should Be $true
    }
    It "posicao no limite exato (14 dias) retorna true" {
        $opened = (Get-Date).AddDays(-14).AddMinutes(-5).ToString("yyyy-MM-dd HH:mm:ss")
        $pos = [PSCustomObject]@{ openedAt = $opened; max_days = 14 }
        Test-MaxDaysExceeded -Pos $pos | Should Be $true
    }
    It "openedAt invalido retorna false (defensive)" {
        $pos = [PSCustomObject]@{ openedAt = "garbage"; max_days = 14 }
        Test-MaxDaysExceeded -Pos $pos | Should Be $false
    }
}

Describe "Close-TrailingPosition - emits feedback outcome" {
    # 2026-05-19 PM: ao fechar posicao, registra outcome em journal/trade_outcomes.jsonl
    # via Add-TradeOutcome (lib_feedback_loop). Disponibiliza dados pra learning loop.
    BeforeEach {
        $script:outcomeFile = Join-Path $script:tmpDir "trade_outcomes.jsonl"
        Remove-Item $outcomeFile -ErrorAction SilentlyContinue
    }
    It "Close-TrailingPosition de stop hit registra R-multiple negativo + exit_reason stop_atingido" {
        # Setup: open + close
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "ZUSDT" -Side "LONG" -Entry 100 -Stop 95 -Target 120 `
                             -Source "tier_a" -OrderId "OID1"
        # Simula close
        Close-TrailingPosition -Market "ZUSDT" -Reason "stop_atingido" -ExitPrice 95 -OutcomePath $outcomeFile
        Test-Path $outcomeFile | Should Be $true
        $line = Get-Content $outcomeFile -Encoding UTF8 | Select-Object -Last 1
        $obj = $line | ConvertFrom-Json
        $obj.market | Should Be "ZUSDT"
        $obj.exit_reason | Should Be "stop_atingido"
        $obj.r | Should Be -1   # entry 100 stop 95 = risk 5; exit 95 = -1R
    }
    It "Close de target hit registra R positivo" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "YUSDT" -Side "LONG" -Entry 100 -Stop 95 -Target 120 -Source "tier_a"
        Close-TrailingPosition -Market "YUSDT" -Reason "target" -ExitPrice 120 -OutcomePath $outcomeFile
        $line = Get-Content $outcomeFile -Encoding UTF8 | Select-Object -Last 1
        $obj = $line | ConvertFrom-Json
        $obj.r | Should Be 4   # entry 100 stop 95 risk 5; exit 120 gain 20 = +4R
        $obj.exit_reason | Should Be "target"
    }
    It "SHORT close: R calc espelhado" {
        Remove-Item "$script:tmpDir\trailing_positions.json" -ErrorAction SilentlyContinue
        Add-TrailingPosition -Market "SUSDT" -Side "SHORT" -Entry 100 -Stop 105 -Target 80 -Source "tier_a"
        Close-TrailingPosition -Market "SUSDT" -Reason "target" -ExitPrice 80 -OutcomePath $outcomeFile
        $line = Get-Content $outcomeFile -Encoding UTF8 | Select-Object -Last 1
        $obj = $line | ConvertFrom-Json
        # SHORT entry 100, exit 80, gain 20; risk = |100-105| = 5; R = 20/5 = 4
        $obj.r | Should Be 4
    }
}

Remove-Item $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue
