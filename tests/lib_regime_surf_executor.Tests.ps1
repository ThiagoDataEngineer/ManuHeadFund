# Tests para lib_regime_surf_executor.ps1 (Pester 3.4.0)
# TDD: garante SHADOW por default (nao executa sem flag) + fail-closed.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_regime_surf_executor.ps1")

function New-BearScen { [pscustomobject]@{ scenario="BEAR"; allow_long=$false; allow_short=$true; strategy="short_ou_caixa" } }
function New-BullScen { [pscustomobject]@{ scenario="BULL"; allow_long=$true; allow_short=$false; strategy="long" } }

$tmpJournal = Join-Path $env:TEMP "regime_surf_test_$([guid]::NewGuid().ToString('N'))"

Describe "Invoke-RegimeSurfShort -- SHADOW por default (sem flag = nao executa)" {
    It "BEAR + downtrend -> SHADOW logado, executed=false, dry_run=true" {
        $r = Invoke-RegimeSurfShort -Market "AIUSDT" -Price 100 -Scenario (New-BearScen) `
            -Momentum30dPct -20 -ShortConviction 70 -Capital 5000 -JournalDir $tmpJournal
        $r.executed | Should Be $false
        $r.dry_run | Should Be $true
        $r.reason | Should Be "shadow_logged"
    }

    It "SHADOW grava no journal regime_surf_shadow.jsonl" {
        $r = Invoke-RegimeSurfShort -Market "AIUSDT" -Price 100 -Scenario (New-BearScen) `
            -Momentum30dPct -20 -ShortConviction 70 -Capital 5000 -JournalDir $tmpJournal
        (Test-Path (Join-Path $tmpJournal "regime_surf_shadow.jsonl")) | Should Be $true
    }

    It "Decisao SHORT carrega stop ACIMA da entrada (fail-closed)" {
        $r = Invoke-RegimeSurfShort -Market "AIUSDT" -Price 100 -Scenario (New-BearScen) `
            -Momentum30dPct -20 -ShortConviction 70 -Capital 5000 -StopPct 8 -JournalDir $tmpJournal
        ($r.decision.stop -gt $r.decision.entry) | Should Be $true
    }
}

Describe "Invoke-RegimeSurfShort -- nao shorta sem edge" {
    It "BULL (allow_short=false) -> no_short, nao executa nem shadow" {
        $r = Invoke-RegimeSurfShort -Market "BTCUSDT" -Price 100 -Scenario (New-BullScen) `
            -Momentum30dPct 10 -ShortConviction 90 -Capital 5000 -JournalDir $tmpJournal
        $r.executed | Should Be $false
        $r.dry_run | Should Be $false
        ($r.reason -like "no_short:*") | Should Be $true
    }

    It "BEAR mas momentum positivo (nao confirma) -> no_short" {
        $r = Invoke-RegimeSurfShort -Market "AIUSDT" -Price 100 -Scenario (New-BearScen) `
            -Momentum30dPct 5 -ShortConviction 90 -Capital 5000 -JournalDir $tmpJournal
        ($r.reason -like "no_short:*") | Should Be $true
    }

    It "ForceDryRun nunca executa mesmo com flag" {
        $r = Invoke-RegimeSurfShort -Market "AIUSDT" -Price 100 -Scenario (New-BearScen) `
            -Momentum30dPct -20 -ShortConviction 70 -Capital 5000 -JournalDir $tmpJournal -ForceDryRun
        $r.executed | Should Be $false
        $r.dry_run | Should Be $true
    }
}

# Cleanup
if (Test-Path $tmpJournal) { Remove-Item $tmpJournal -Recurse -Force -ErrorAction SilentlyContinue }
