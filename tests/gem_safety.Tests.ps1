# gem_safety.Tests.ps1 -- TDD para GEM Safety Guards (Pester 3.x)
# Defaults loose (learning phase): exposure 15%, daily 10, weekly 40, breaker 5, double-confirm 10%

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_gem_safety.ps1")

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

$script:TestStateDir  = Join-Path $env:TEMP "gem_safety_tests"
$script:TestStateFile = Join-Path $script:TestStateDir "gem_safety_state.json"

function New-TestState {
    param(
        [array]    $OpenPositions    = @(),
        [int]      $DailyCount       = 0,
        [string]   $DailyResetDate   = (Get-Date).ToString("yyyy-MM-dd"),
        [int]      $WeeklyCount      = 0,
        [string]   $WeeklyResetDate  = $null,
        [int]      $ConsecutiveStops = 0
    )
    if (-not (Test-Path $script:TestStateDir)) {
        New-Item -ItemType Directory -Path $script:TestStateDir -Force | Out-Null
    }
    if (-not $WeeklyResetDate) {
        # Monday of the current week (BRT)
        $today = (Get-Date).Date
        $dow   = [int]$today.DayOfWeek            # Sunday=0 ... Monday=1
        $diff  = if ($dow -eq 0) { -6 } else { 1 - $dow }
        $WeeklyResetDate = $today.AddDays($diff).ToString("yyyy-MM-dd")
    }
    $state = @{
        open_positions     = $OpenPositions
        daily_count        = $DailyCount
        daily_reset_date   = $DailyResetDate
        weekly_count       = $WeeklyCount
        weekly_reset_date  = $WeeklyResetDate
        consecutive_stops  = $ConsecutiveStops
        last_trade_result  = $null
        last_updated       = (Get-Date).ToString("o")
    }
    ($state | ConvertTo-Json -Depth 6) | Out-File -FilePath $script:TestStateFile -Encoding utf8 -Force
}

function Remove-TestState {
    if (Test-Path $script:TestStateFile) {
        Remove-Item $script:TestStateFile -Force -ErrorAction SilentlyContinue
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Bloco A — Hard cap exposure (5)
# ─────────────────────────────────────────────────────────────────────────────

Describe "Bloco A - Hard cap exposure" {

    It "permite quando exposure_pct + new_trade < 15%" {
        New-TestState -OpenPositions @(@{ market="A"; size_usdt=50.0; entry_ts="x" })
        $r = Test-GemSafetyGuards -TradeSizeUsdt 50.0 -TotalCapitalUsdt 1000.0 -StateFilePath $script:TestStateFile
        $r.allowed | Should Be $true
    }

    It "BLOQUEIA quando exposure_pct + new_trade > 15%" {
        New-TestState -OpenPositions @(@{ market="A"; size_usdt=140.0; entry_ts="x" })
        $r = Test-GemSafetyGuards -TradeSizeUsdt 30.0 -TotalCapitalUsdt 1000.0 -StateFilePath $script:TestStateFile
        $r.allowed | Should Be $false
        $r.reason  | Should Be "cap_exposure"
    }

    It "BLOQUEIA quando projected exato == 15%" {
        New-TestState -OpenPositions @(@{ market="A"; size_usdt=100.0; entry_ts="x" })
        $r = Test-GemSafetyGuards -TradeSizeUsdt 50.0 -TotalCapitalUsdt 1000.0 -StateFilePath $script:TestStateFile
        $r.allowed | Should Be $false
        $r.reason  | Should Be "cap_exposure"
    }

    It "retorna razao cap_exposure com pct atual e projecao" {
        New-TestState -OpenPositions @(@{ market="A"; size_usdt=140.0; entry_ts="x" })
        $r = Test-GemSafetyGuards -TradeSizeUsdt 30.0 -TotalCapitalUsdt 1000.0 -StateFilePath $script:TestStateFile
        $r.reason | Should Be "cap_exposure"
        $r.current_exposure_pct   | Should Be 14.0
        $r.projected_exposure_pct | Should Be 17.0
    }

    It "Get-OpenGemExposurePct calcula soma corretamente" {
        New-TestState -OpenPositions @(
            @{ market="A"; size_usdt=20.0; entry_ts="x" },
            @{ market="B"; size_usdt=30.0; entry_ts="y" }
        )
        $pct = Get-OpenGemExposurePct -StateFilePath $script:TestStateFile -TotalCapitalUsdt 1000.0
        $pct | Should Be 5.0
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Bloco B — Daily throttle (4)
# ─────────────────────────────────────────────────────────────────────────────

Describe "Bloco B - Daily throttle" {

    It "permite quando daily_count < 10" {
        New-TestState -DailyCount 5
        $r = Test-GemSafetyGuards -TradeSizeUsdt 5.0 -TotalCapitalUsdt 1000.0 -StateFilePath $script:TestStateFile
        $r.allowed | Should Be $true
    }

    It "BLOQUEIA quando daily_count >= 10" {
        New-TestState -DailyCount 10
        $r = Test-GemSafetyGuards -TradeSizeUsdt 5.0 -TotalCapitalUsdt 1000.0 -StateFilePath $script:TestStateFile
        $r.allowed | Should Be $false
        $r.reason  | Should Be "daily_limit"
    }

    It "reset daily_count quando data BRT muda" {
        $ontem = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
        New-TestState -DailyCount 10 -DailyResetDate $ontem
        $r = Test-GemSafetyGuards -TradeSizeUsdt 5.0 -TotalCapitalUsdt 1000.0 -StateFilePath $script:TestStateFile
        $r.allowed     | Should Be $true
        $r.daily_count | Should Be 0
    }

    It "razao daily_limit inclui count e max" {
        New-TestState -DailyCount 10
        $r = Test-GemSafetyGuards -TradeSizeUsdt 5.0 -TotalCapitalUsdt 1000.0 -StateFilePath $script:TestStateFile
        $r.reason           | Should Be "daily_limit"
        $r.daily_count      | Should Be 10
        $r.telegram_message.Contains("10") | Should Be $true
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Bloco C — Weekly throttle (3)
# ─────────────────────────────────────────────────────────────────────────────

Describe "Bloco C - Weekly throttle" {

    It "permite quando weekly_count < 40" {
        New-TestState -WeeklyCount 20
        $r = Test-GemSafetyGuards -TradeSizeUsdt 5.0 -TotalCapitalUsdt 1000.0 -StateFilePath $script:TestStateFile
        $r.allowed | Should Be $true
    }

    It "BLOQUEIA quando weekly_count >= 40" {
        New-TestState -WeeklyCount 40
        $r = Test-GemSafetyGuards -TradeSizeUsdt 5.0 -TotalCapitalUsdt 1000.0 -StateFilePath $script:TestStateFile
        $r.allowed | Should Be $false
        $r.reason  | Should Be "weekly_limit"
    }

    It "reset weekly_count na segunda-feira (data anterior a esta semana)" {
        $semanaPassada = (Get-Date).AddDays(-8).ToString("yyyy-MM-dd")
        New-TestState -WeeklyCount 40 -WeeklyResetDate $semanaPassada
        $r = Test-GemSafetyGuards -TradeSizeUsdt 5.0 -TotalCapitalUsdt 1000.0 -StateFilePath $script:TestStateFile
        $r.allowed      | Should Be $true
        $r.weekly_count | Should Be 0
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Bloco D — Circuit breaker (4)
# ─────────────────────────────────────────────────────────────────────────────

Describe "Bloco D - Circuit breaker" {

    It "permite quando consecutive_stops < 5" {
        New-TestState -ConsecutiveStops 3
        $r = Test-GemSafetyGuards -TradeSizeUsdt 5.0 -TotalCapitalUsdt 1000.0 -StateFilePath $script:TestStateFile
        $r.allowed | Should Be $true
    }

    It "BLOQUEIA quando consecutive_stops >= 5" {
        New-TestState -ConsecutiveStops 5
        $r = Test-GemSafetyGuards -TradeSizeUsdt 5.0 -TotalCapitalUsdt 1000.0 -StateFilePath $script:TestStateFile
        $r.allowed | Should Be $false
        $r.reason  | Should Be "circuit_breaker"
    }

    It "Add-GemTradeResult result=STOP incrementa consecutive_stops" {
        New-TestState -ConsecutiveStops 2
        Add-GemTradeResult -Market "X" -Result "STOP" -PnlUsdt -10.0 -StateFilePath $script:TestStateFile
        $s = Get-GemSafetyState -StateFilePath $script:TestStateFile
        $s.consecutive_stops | Should Be 3
    }

    It "Add-GemTradeResult result=WIN reseta consecutive_stops a zero" {
        New-TestState -ConsecutiveStops 4
        Add-GemTradeResult -Market "X" -Result "WIN" -PnlUsdt 20.0 -StateFilePath $script:TestStateFile
        $s = Get-GemSafetyState -StateFilePath $script:TestStateFile
        $s.consecutive_stops | Should Be 0
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Bloco E — Double confirmation (3)
# ─────────────────────────────────────────────────────────────────────────────

Describe "Bloco E - Double confirmation" {

    It "requires_confirmation=true quando exposure projected > 10%" {
        New-TestState -OpenPositions @(@{ market="A"; size_usdt=80.0; entry_ts="x" })
        # current=8%; trade 5% => projected 13% (>10 e <15)
        $r = Test-GemSafetyGuards -TradeSizeUsdt 50.0 -TotalCapitalUsdt 1000.0 -StateFilePath $script:TestStateFile
        $r.allowed               | Should Be $true
        $r.requires_confirmation | Should Be $true
    }

    It "requires_confirmation=false quando exposure projected <= 10%" {
        New-TestState -OpenPositions @(@{ market="A"; size_usdt=40.0; entry_ts="x" })
        # current=4%; trade 5% => projected 9% (<10)
        $r = Test-GemSafetyGuards -TradeSizeUsdt 50.0 -TotalCapitalUsdt 1000.0 -StateFilePath $script:TestStateFile
        $r.allowed               | Should Be $true
        $r.requires_confirmation | Should Be $false
    }

    It "telegram_message inclui pct atual e projecao quando requires_confirmation" {
        New-TestState -OpenPositions @(@{ market="A"; size_usdt=80.0; entry_ts="x" })
        $r = Test-GemSafetyGuards -TradeSizeUsdt 50.0 -TotalCapitalUsdt 1000.0 -StateFilePath $script:TestStateFile
        $r.telegram_message.Contains("8")  | Should Be $true   # current
        $r.telegram_message.Contains("13") | Should Be $true   # projected
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Bloco F — State persistence + edge cases (3)
# ─────────────────────────────────────────────────────────────────────────────

Describe "Bloco F - State persistence" {

    It "Get-GemSafetyState le do journal/gem_safety_state.json" {
        New-TestState -DailyCount 7
        $s = Get-GemSafetyState -StateFilePath $script:TestStateFile
        $s.daily_count | Should Be 7
    }

    It "Update-GemSafetyState persiste mudancas" {
        New-TestState -DailyCount 0
        $s = Get-GemSafetyState -StateFilePath $script:TestStateFile
        $s.daily_count = 9
        Update-GemSafetyState -State $s -StateFilePath $script:TestStateFile
        $s2 = Get-GemSafetyState -StateFilePath $script:TestStateFile
        $s2.daily_count | Should Be 9
    }

    It "Test-GemSafetyGuards retorna allowed=false motivo claro quando state corrompido" {
        if (-not (Test-Path $script:TestStateDir)) {
            New-Item -ItemType Directory -Path $script:TestStateDir -Force | Out-Null
        }
        "{ not valid json" | Out-File -FilePath $script:TestStateFile -Encoding utf8 -Force
        $r = Test-GemSafetyGuards -TradeSizeUsdt 5.0 -TotalCapitalUsdt 1000.0 -StateFilePath $script:TestStateFile
        $r.allowed | Should Be $false
        $r.reason  | Should Be "state_corrupted"
    }
}

# Cleanup
Remove-TestState
