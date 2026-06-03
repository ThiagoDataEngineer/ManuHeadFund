param([string] $ModulePath = "$PSScriptRoot\..\agents")

Describe "lib_cycle_memory_decision — Reflection cache to reduce LLM calls" {
    . "$ModulePath\lib_cycle_memory_decision.ps1"

    Context "Cache storage and retrieval" {
        BeforeEach {
            $testPath = "$env:TEMP\refl_cache_$(Get-Random).jsonl"
        }

        AfterEach {
            if (Test-Path $testPath) { Remove-Item $testPath -Force }
        }

        It "Saves reflection decision to cache" {
            Save-ReflectionCache -Path $testPath `
                -Market "ETHUSDT" `
                -Regime "BEAR_WEAK" `
                -Decision "VETO" `
                -VetoReason "MACRO_UNFAVORABLE" `
                -Timestamp (Get-Date)

            (Test-Path $testPath) | Should Be $true
        }

        It "Retrieves last decision for market" {
            $now = Get-Date

            Save-ReflectionCache -Path $testPath `
                -Market "ETHUSDT" `
                -Regime "BEAR_WEAK" `
                -Decision "VETO" `
                -VetoReason "MACRO_UNFAVORABLE" `
                -Timestamp $now

            $cached = Get-ReflectionCache -Path $testPath -Market "ETHUSDT"
            $cached | Should Not Be $null
            $cached.decision | Should Be "VETO"
            $cached.veto_reason | Should Be "MACRO_UNFAVORABLE"
        }

        It "Cache miss: return null" {
            $cached = Get-ReflectionCache -Path $testPath -Market "NONEXISTENT"
            $cached | Should Be $null
        }

        It "Appends multiple entries for different markets" {
            Save-ReflectionCache -Path $testPath -Market "ETHUSDT" -Regime "BEAR_WEAK" `
                -Decision "VETO" -VetoReason "MACRO_UNFAVORABLE" -Timestamp (Get-Date)

            Start-Sleep -Milliseconds 10

            Save-ReflectionCache -Path $testPath -Market "PENDLE" -Regime "BEAR_WEAK" `
                -Decision "APPROVE" -VetoReason $null -Timestamp (Get-Date)

            $lines = @(Get-Content $testPath)
            $lines.Count | Should Be 2
        }

        It "Latest entry for market returned (multiple cached)" {
            Save-ReflectionCache -Path $testPath -Market "ETHUSDT" -Regime "BEAR_WEAK" `
                -Decision "VETO" -VetoReason "MACRO_UNFAVORABLE" -Timestamp (Get-Date)

            Start-Sleep -Milliseconds 10

            Save-ReflectionCache -Path $testPath -Market "ETHUSDT" -Regime "BEAR_WEAK" `
                -Decision "APPROVE" -VetoReason $null -Timestamp (Get-Date)

            $cached = Get-ReflectionCache -Path $testPath -Market "ETHUSDT"
            $cached.decision | Should Be "APPROVE"
        }
    }

    Context "Cycle memory decision logic" {
        BeforeEach {
            $testPath = "$env:TEMP\cycle_mem_$(Get-Random).jsonl"
        }

        AfterEach {
            if (Test-Path $testPath) { Remove-Item $testPath -Force }
        }

        It "No cache: return null (proceed with normal reflection)" {
            $decision = Get-CycleMemoryDecision -Path $testPath -Market "ETHUSDT" -CurrentRegime "BEAR_WEAK"
            $decision | Should Be $null
        }

        It "Cache hit + same regime + veto reason: return cached veto (no LLM needed)" {
            Save-ReflectionCache -Path $testPath -Market "ETHUSDT" -Regime "BEAR_WEAK" `
                -Decision "VETO" -VetoReason "MACRO_UNFAVORABLE" -Timestamp (Get-Date)

            $decision = Get-CycleMemoryDecision -Path $testPath -Market "ETHUSDT" -CurrentRegime "BEAR_WEAK"

            $decision | Should Not Be $null
            $decision.decision | Should Be "VETO"
            $decision.from_cache | Should Be $true
            $decision.reason | Should Be "MACRO_UNFAVORABLE"
        }

        It "Cache hit + DIFFERENT regime: ignore cache (proceed with LLM)" {
            Save-ReflectionCache -Path $testPath -Market "ETHUSDT" -Regime "BEAR_WEAK" `
                -Decision "VETO" -VetoReason "MACRO_UNFAVORABLE" -Timestamp (Get-Date)

            $decision = Get-CycleMemoryDecision -Path $testPath -Market "ETHUSDT" -CurrentRegime "BULL_WEAK"

            $decision | Should Be $null
        }

        It "Cache has APPROVE decision: return null (skip cache for approved)" {
            Save-ReflectionCache -Path $testPath -Market "ETHUSDT" -Regime "BEAR_WEAK" `
                -Decision "APPROVE" -VetoReason $null -Timestamp (Get-Date)

            $decision = Get-CycleMemoryDecision -Path $testPath -Market "ETHUSDT" -CurrentRegime "BEAR_WEAK"

            $decision | Should Be $null
        }

        It "Cache expired (>7 days): return null" {
            $oldTime = (Get-Date).ToUniversalTime().AddDays(-8)
            Save-ReflectionCache -Path $testPath -Market "ETHUSDT" -Regime "BEAR_WEAK" `
                -Decision "VETO" -VetoReason "MACRO_UNFAVORABLE" -Timestamp $oldTime

            $decision = Get-CycleMemoryDecision -Path $testPath -Market "ETHUSDT" -CurrentRegime "BEAR_WEAK"

            $decision | Should Be $null
        }
    }

    Context "Cost savings verification" {
        BeforeEach {
            $testPath = "$env:TEMP\cost_save_$(Get-Random).jsonl"
        }

        AfterEach {
            if (Test-Path $testPath) { Remove-Item $testPath -Force }
        }

        It "Cached veto avoids LLM call (cost_savings=true)" {
            Save-ReflectionCache -Path $testPath -Market "ETHUSDT" -Regime "BEAR_WEAK" `
                -Decision "VETO" -VetoReason "MACRO_UNFAVORABLE" -Timestamp (Get-Date)

            $decision = Get-CycleMemoryDecision -Path $testPath -Market "ETHUSDT" -CurrentRegime "BEAR_WEAK"

            $decision.from_cache | Should Be $true
            # LLM call NOT made (savings = 1 API call = ~$0.002)
        }

        It "Multiple macro vetos cached: 5+ LLM calls saved per cycle" {
            $markets = "ETHUSDT", "PENDLE", "UNI", "LINK", "AAVE"
            foreach ($m in $markets) {
                Save-ReflectionCache -Path $testPath -Market $m -Regime "BEAR_WEAK" `
                    -Decision "VETO" -VetoReason "MACRO_UNFAVORABLE" -Timestamp (Get-Date)
                Start-Sleep -Milliseconds 5
            }

            $cachedCount = 0
            foreach ($m in $markets) {
                $d = Get-CycleMemoryDecision -Path $testPath -Market $m -CurrentRegime "BEAR_WEAK"
                if ($d -and $d.from_cache) { $cachedCount++ }
            }

            $cachedCount | Should Be 5
            # 5 LLM calls saved (~$0.01 per cycle)
        }
    }

    Context "Integration: when to skip LLM" {
        BeforeEach {
            $testPath = "$env:TEMP\integration_$(Get-Random).jsonl"
        }

        AfterEach {
            if (Test-Path $testPath) { Remove-Item $testPath -Force }
        }

        It "Flow: gem approved → no cache, LLM called" {
            $decision = Get-CycleMemoryDecision -Path $testPath -Market "ETHUSDT" -CurrentRegime "BEAR_WEAK"
            $decision | Should Be $null
            # LLM WILL be called
        }

        It "Flow: gem veto'd by MACRO → cache it" {
            Save-ReflectionCache -Path $testPath -Market "ETHUSDT" -Regime "BEAR_WEAK" `
                -Decision "VETO" -VetoReason "MACRO_UNFAVORABLE" -Timestamp (Get-Date)

            # Next cycle, same regime
            $decision = Get-CycleMemoryDecision -Path $testPath -Market "ETHUSDT" -CurrentRegime "BEAR_WEAK"
            $decision.from_cache | Should Be $true
            # LLM NOT called (saved cost)
        }

        It "Flow: regime changes → ignore cache, LLM called (maybe different decision)" {
            Save-ReflectionCache -Path $testPath -Market "ETHUSDT" -Regime "BEAR_WEAK" `
                -Decision "VETO" -VetoReason "MACRO_UNFAVORABLE" -Timestamp (Get-Date)

            # Market rallies to BULL_WEAK
            $decision = Get-CycleMemoryDecision -Path $testPath -Market "ETHUSDT" -CurrentRegime "BULL_WEAK"
            $decision | Should Be $null
            # LLM WILL be called (regime changed, decision might change)
        }
    }
}
