# gem_cache_bypass.Tests.ps1 -- TDD do bypass de cache p/ gate de conviction
# Problema: gems cacheados como tori_skip nunca re-chegam ao executor -> gate de
# conviction (override Tori) fica decorativo. Fix: -BypassReasons deixa tori_skip
# re-passar, mas conviction_low/sizing/etc continuam bloqueando (sem loop).
# Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\lib_gem_decision_cache.ps1"

Describe "Test-GemRecentlyRejected -BypassReasons" {

    BeforeEach {
        $script:cache = Join-Path $env:TEMP "gemcache_$([guid]::NewGuid().ToString('N').Substring(0,8)).json"
    }
    AfterEach {
        if (Test-Path $script:cache) { Remove-Item $script:cache -Force }
    }

    Context "Bypass deixa tori_skip re-passar" {

        It "tori_skip cacheado + bypass tori_skip = NAO bloqueia (re-avalia)" {
            Add-GemRejection -Path $script:cache -Market "XRPUSDT" -Reason "tori_skip"
            $blocked = Test-GemRecentlyRejected -Path $script:cache -Market "XRPUSDT" -TtlMinutes 60 -BypassReasons @("tori_skip","tori_wait")
            $blocked | Should Be $false
        }

        It "tori_wait cacheado + bypass = NAO bloqueia" {
            Add-GemRejection -Path $script:cache -Market "ZECUSDT" -Reason "tori_wait"
            $blocked = Test-GemRecentlyRejected -Path $script:cache -Market "ZECUSDT" -TtlMinutes 60 -BypassReasons @("tori_skip","tori_wait")
            $blocked | Should Be $false
        }
    }

    Context "Sem bypass = comportamento antigo (bloqueia)" {

        It "tori_skip cacheado SEM bypass = bloqueia" {
            Add-GemRejection -Path $script:cache -Market "XRPUSDT" -Reason "tori_skip"
            $blocked = Test-GemRecentlyRejected -Path $script:cache -Market "XRPUSDT" -TtlMinutes 60
            $blocked | Should Be $true
        }
    }

    Context "Outras razoes continuam bloqueando (sem loop)" {

        It "conviction_low cacheado + bypass tori_skip = AINDA bloqueia (evita loop)" {
            Add-GemRejection -Path $script:cache -Market "XRPUSDT" -Reason "conviction_low_skip"
            $blocked = Test-GemRecentlyRejected -Path $script:cache -Market "XRPUSDT" -TtlMinutes 60 -BypassReasons @("tori_skip","tori_wait")
            $blocked | Should Be $true
        }

        It "sizing_invalido cacheado + bypass tori_skip = AINDA bloqueia" {
            Add-GemRejection -Path $script:cache -Market "AAAUSDT" -Reason "sizing_invalido"
            $blocked = Test-GemRecentlyRejected -Path $script:cache -Market "AAAUSDT" -TtlMinutes 60 -BypassReasons @("tori_skip","tori_wait")
            $blocked | Should Be $true
        }

        It "market com tori_skip E conviction_low = bloqueia (a razao bloqueante vence)" {
            Add-GemRejection -Path $script:cache -Market "XRPUSDT" -Reason "tori_skip"
            Add-GemRejection -Path $script:cache -Market "XRPUSDT" -Reason "conviction_low_skip"
            $blocked = Test-GemRecentlyRejected -Path $script:cache -Market "XRPUSDT" -TtlMinutes 60 -BypassReasons @("tori_skip","tori_wait")
            $blocked | Should Be $true
        }
    }

    Context "Robustez" {

        It "bypass vazio = comportamento padrao" {
            Add-GemRejection -Path $script:cache -Market "XRPUSDT" -Reason "tori_skip"
            $blocked = Test-GemRecentlyRejected -Path $script:cache -Market "XRPUSDT" -TtlMinutes 60 -BypassReasons @()
            $blocked | Should Be $true
        }
    }
}
