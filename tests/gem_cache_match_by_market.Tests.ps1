$script:gemtest_here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:gemtest_root = Split-Path -Parent $gemtest_here

# gem_cache_match_by_market.Tests.ps1 -- Lockdown 2026-05-21 sessao TG audit.
# Pester 3.x.
#
# Bug: Add-GemRejection escrevia reason "tori_skip" enquanto Test-GemRecentlyRejected
# checava "score=85 mode=DISCOVERY". Cache effectively dead -> PEAQUSDT re-vetada 7+ vezes
# no dia 2026-05-21, custo LLM desperdiçado, e user spam de approvals.
#
# Fix: Test-GemRecentlyRejected agora default match-by-market-only. Reason strict
# vira opt-in via -MatchReason.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_gem_decision_cache.ps1")

$script:tmp = Join-Path $env:TEMP ("gemcache_" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null


Describe "Test-GemRecentlyRejected - default match-by-market" {

    It "Sem -MatchReason: ignora reason, retorna true se market+TTL match" {
        $cache = Join-Path $tmp ("c1_" + [guid]::NewGuid().ToString("N").Substring(0,6) + ".json")
        Add-GemRejection -Path $cache -Market "PEAQUSDT" -Reason "tori_skip"
        # Check com reason completamente diferente
        $r = Test-GemRecentlyRejected -Path $cache -Market "PEAQUSDT" -Reason "score=85 mode=DISCOVERY" -TtlMinutes 60
        $r | Should Be $true
    }

    It "Sem reason: ainda funciona (match-by-market only)" {
        $cache = Join-Path $tmp ("c2_" + [guid]::NewGuid().ToString("N").Substring(0,6) + ".json")
        Add-GemRejection -Path $cache -Market "BTCUSDT" -Reason "any_thing"
        $r = Test-GemRecentlyRejected -Path $cache -Market "BTCUSDT" -TtlMinutes 60
        $r | Should Be $true
    }

    It "Different market nao matcha" {
        $cache = Join-Path $tmp ("c3_" + [guid]::NewGuid().ToString("N").Substring(0,6) + ".json")
        Add-GemRejection -Path $cache -Market "AAA" -Reason "x"
        Test-GemRecentlyRejected -Path $cache -Market "BBB" -TtlMinutes 60 | Should Be $false
    }

    It "TTL expirado: nao matcha" {
        $cache = Join-Path $tmp ("c4_" + [guid]::NewGuid().ToString("N").Substring(0,6) + ".json")
        # Entry com timestamp 2h atras
        $oldTs = (Get-Date).ToUniversalTime().AddHours(-2).ToString("yyyy-MM-ddTHH:mm:ssZ")
        '[{"market":"CCC","reason":"old","ts":"' + $oldTs + '"}]' |
            Out-File $cache -Encoding utf8
        # TTL 60min -> entry de 2h atras nao matcha
        Test-GemRecentlyRejected -Path $cache -Market "CCC" -TtlMinutes 60 | Should Be $false
        # TTL 180min -> matcha
        Test-GemRecentlyRejected -Path $cache -Market "CCC" -TtlMinutes 180 | Should Be $true
    }
}


Describe "Test-GemRecentlyRejected - opt-in MatchReason (legacy strict)" {

    It "-MatchReason: exige reason normalized identico" {
        $cache = Join-Path $tmp ("s1_" + [guid]::NewGuid().ToString("N").Substring(0,6) + ".json")
        Add-GemRejection -Path $cache -Market "DASHUSDT" -Reason "MCE_BLOCK 0.1823"
        # Match: mesmo reason
        Test-GemRecentlyRejected -Path $cache -Market "DASHUSDT" -Reason "MCE_BLOCK 0.1824" -TtlMinutes 60 -MatchReason | Should Be $true
        # NoMatch: reason diferente
        Test-GemRecentlyRejected -Path $cache -Market "DASHUSDT" -Reason "tori_skip" -TtlMinutes 60 -MatchReason | Should Be $false
    }
}


Describe "Anti-regression - gem_executor self-loads lib_gem_decision_cache" {

    It "gem_executor.ps1 dot-sources lib_gem_decision_cache (B9 cache funcional standalone)" {
        # Bug 2026-05-21: scan_master loads gem_executor mas NAO lib_gem_decision_cache.
        # Get-Command Test-GemRecentlyRejected returnava null silently -> cache check
        # nunca disparava -> Tori path sempre executava (PEAQ loop 7+ vezes).
        $src = Get-Content (Join-Path $script:gemtest_root "agents\gem_executor.ps1") -Raw -Encoding UTF8
        $src | Should Match 'lib_gem_decision_cache\.ps1'
    }
}

Describe "Anti-regression - PEAQ 2026-05-21 loop case" {

    It "Cenario real: Tori skip cached, gem_executor cache hit por (market) skip silencioso" {
        $cache = Join-Path $tmp ("peaq_" + [guid]::NewGuid().ToString("N").Substring(0,6) + ".json")
        # Step 1: Tori skip persiste reason no formato real
        Add-GemRejection -Path $cache -Market "PEAQUSDT" -Reason "tori_skip"
        # Step 2: proximo cycle, gem_executor checa com reason "score=85 mode=DISCOVERY"
        $r = Test-GemRecentlyRejected -Path $cache -Market "PEAQUSDT" -Reason "score=85 mode=DISCOVERY" -TtlMinutes 60
        $r | Should Be $true
    }
}


# Cleanup
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
