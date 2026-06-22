# TDD da resolucao do universo SHORT (whitelist journal -> fallback config git-tracked).
$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_short_universe.ps1")

function _wl($obj) { [PSCustomObject]$obj }

Describe "Resolve-ShortUniverse -- prioriza whitelist" {
    It "whitelist com SHORT tiers -> usa whitelist (ignora fallback)" {
        $wl = _wl @{ SHORT_TIER_B_PAPER = @([PSCustomObject]@{market='BTCUSDT'}, [PSCustomObject]@{market='ETHUSDT'}) }
        $cfg = _wl @{ markets = @([PSCustomObject]@{market='ZZZUSDT'}) }
        $r = Resolve-ShortUniverse -Whitelist $wl -ConfigFallback $cfg
        $r.Count | Should Be 2
        ($r -contains 'BTCUSDT') | Should Be $true
        ($r -contains 'ZZZUSDT') | Should Be $false
    }
    It "junta A_LIVE + B_PAPER e dedup" {
        $wl = _wl @{
            SHORT_TIER_A_LIVE  = @([PSCustomObject]@{market='SOLUSDT'})
            SHORT_TIER_B_PAPER = @([PSCustomObject]@{market='SOLUSDT'}, [PSCustomObject]@{market='XRPUSDT'})
        }
        $r = Resolve-ShortUniverse -Whitelist $wl
        $r.Count | Should Be 2
    }
}

Describe "Resolve-ShortUniverse -- fallback config (caso cloud)" {
    It "whitelist sem SHORT tiers -> usa fallback config" {
        $wl = _wl @{ TIER_A_LIVE = @([PSCustomObject]@{market='LONGUSDT'}) }  # so LONG
        $cfg = _wl @{ markets = @([PSCustomObject]@{market='BTCUSDT'}, [PSCustomObject]@{market='ETHUSDT'}) }
        $r = Resolve-ShortUniverse -Whitelist $wl -ConfigFallback $cfg
        $r.Count | Should Be 2
        ($r -contains 'BTCUSDT') | Should Be $true
    }
    It "whitelist null + fallback -> usa fallback" {
        $cfg = _wl @{ markets = @([PSCustomObject]@{market='INJUSDT'}) }
        $r = Resolve-ShortUniverse -Whitelist $null -ConfigFallback $cfg
        ($r -contains 'INJUSDT') | Should Be $true
    }
    It "fallback aceita markets como strings simples" {
        $cfg = _wl @{ markets = @('BTCUSDT','ETHUSDT') }
        $r = Resolve-ShortUniverse -Whitelist $null -ConfigFallback $cfg
        $r.Count | Should Be 2
    }
}

Describe "Resolve-ShortUniverse -- vazio" {
    It "tudo null/vazio -> array vazio (nao quebra)" {
        $r = Resolve-ShortUniverse -Whitelist $null -ConfigFallback $null
        @($r).Count | Should Be 0
    }
}

Describe "Resolve-TierUniverse -- generico (LONG tiers)" {
    It "le tiers LONG do whitelist" {
        $wl = _wl @{ TIER_A_LIVE = @([PSCustomObject]@{market='BTCUSDT'}); TIER_B_PAPER = @([PSCustomObject]@{market='XRPUSDT'}) }
        $r = Resolve-TierUniverse -Whitelist $wl -TierKeys @('TIER_A_LIVE','TIER_B_PAPER')
        $r.Count | Should Be 2
    }
    It "whitelist sem os tiers LONG -> fallback config" {
        $wl = _wl @{ SHORT_TIER_B_PAPER = @([PSCustomObject]@{market='SOLUSDT'}) }  # so SHORT
        $cfg = _wl @{ markets = @([PSCustomObject]@{market='RENDERUSDT'}) }
        $r = Resolve-TierUniverse -Whitelist $wl -TierKeys @('TIER_A_LIVE','TIER_B_PAPER') -ConfigFallback $cfg
        ($r -contains 'RENDERUSDT') | Should Be $true
    }
}
