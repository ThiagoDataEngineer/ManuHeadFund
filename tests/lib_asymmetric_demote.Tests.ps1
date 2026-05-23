# lib_asymmetric_demote.Tests.ps1 -- TDD pra fast demote vs slow promote.
# Pester 3.x.
#
# Pattern: demote rapido (3 dias FLAG = auto), promote lento (Bailey-LdP).
# Asymmetric protege contra crashes Luna-style (-99% em 72h).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_promotion_gates.ps1")
. (Join-Path $agentsDir "lib_asymmetric_demote.ps1")

$script:tmp = Join-Path $env:TEMP ("ad_$([guid]::NewGuid())")
New-Item -ItemType Directory -Path $tmp -Force | Out-Null


Describe "Test-AsymmetricDemoteCondition" {
    BeforeEach {
        $script:flagFile = Join-Path $tmp "flag_hist.jsonl"
        Remove-Item $flagFile -ErrorAction SilentlyContinue
    }

    function _AddFlagEvent {
        param($Market, $DaysAgo)
        $ts = (Get-Date).AddDays(-$DaysAgo).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $ev = @{ ts = $ts; flagged = @($Market); critical = @() } | ConvertTo-Json -Compress
        Add-Content -Path $flagFile -Value $ev -Encoding UTF8
    }

    It "Sem flags = no demote" {
        $r = Test-AsymmetricDemoteCondition -Market "X" -FlagHistoryPath $flagFile
        $r.should_demote | Should Be $false
    }

    It "1 dia FLAG: no demote ainda" {
        _AddFlagEvent "X" 0
        $r = Test-AsymmetricDemoteCondition -Market "X" -FlagHistoryPath $flagFile
        $r.should_demote | Should Be $false
        $r.streak | Should Be 1
    }

    It "2 dias FLAG consecutivos: no demote ainda (threshold 3)" {
        _AddFlagEvent "X" 1
        _AddFlagEvent "X" 0
        $r = Test-AsymmetricDemoteCondition -Market "X" -FlagHistoryPath $flagFile
        $r.should_demote | Should Be $false
        $r.streak | Should Be 2
    }

    It "3 dias FLAG consecutivos = DEMOTE AUTO-FIRED" {
        _AddFlagEvent "X" 2
        _AddFlagEvent "X" 1
        _AddFlagEvent "X" 0
        $r = Test-AsymmetricDemoteCondition -Market "X" -FlagHistoryPath $flagFile
        $r.should_demote | Should Be $true
        $r.streak | Should Be 3
        $r.reason | Should Match "3_consecutive_flags"
    }

    It "1 CRITICAL: demote IMEDIATO (skip 3-day requirement)" {
        # CRITICAL = drawdown > 25% (TIER_A) — 1 dia ja triggers
        $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $ev = @{ ts = $ts; flagged = @(); critical = @("X") } | ConvertTo-Json -Compress
        Add-Content -Path $flagFile -Value $ev -Encoding UTF8
        $r = Test-AsymmetricDemoteCondition -Market "X" -FlagHistoryPath $flagFile
        $r.should_demote | Should Be $true
        $r.reason | Should Match "critical_immediate"
    }

    It "Streak broken (gap de FLAG) = no demote" {
        _AddFlagEvent "X" 5
        _AddFlagEvent "X" 4
        # gap dia 3
        _AddFlagEvent "X" 2
        _AddFlagEvent "X" 1
        # Streak atual = 2 (so dia 2 e 1)
        $r = Test-AsymmetricDemoteCondition -Market "X" -FlagHistoryPath $flagFile
        $r.should_demote | Should Be $false
    }

    It "Threshold customizado (5 dias)" {
        _AddFlagEvent "X" 2
        _AddFlagEvent "X" 1
        _AddFlagEvent "X" 0
        $r = Test-AsymmetricDemoteCondition -Market "X" -FlagHistoryPath $flagFile -StreakThreshold 5
        $r.should_demote | Should Be $false
        $r.streak | Should Be 3
    }
}


Describe "Invoke-AutoDemoteIfNeeded - integrator" {
    It "should_demote=true cria demote event no pipeline + demote_history" {
        $tmp2 = Join-Path $env:TEMP ("ad2_$([guid]::NewGuid())")
        New-Item -ItemType Directory -Path $tmp2 -Force | Out-Null
        $flagFile = Join-Path $tmp2 "flag.jsonl"
        $demoteFile = Join-Path $tmp2 "demote.jsonl"
        $pipeline = Join-Path $tmp2 "pipeline.jsonl"

        # 3 dias FLAG
        foreach ($d in @(2,1,0)) {
            $ts = (Get-Date).AddDays(-$d).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            @{ ts=$ts; flagged=@("X"); critical=@() } | ConvertTo-Json -Compress | Add-Content -Path $flagFile -Encoding UTF8
        }

        # Setup market em Tier A (state 4)
        @{ ts=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"); event="promoted"; market="X"; tier_state=4 } |
            ConvertTo-Json -Compress | Add-Content -Path $pipeline -Encoding UTF8

        $r = Invoke-AutoDemoteIfNeeded -Market "X" `
                                       -FlagHistoryPath $flagFile `
                                       -DemoteHistoryPath $demoteFile `
                                       -PipelinePath $pipeline
        $r.demoted | Should Be $true
        Test-Path $demoteFile | Should Be $true

        Remove-Item $tmp2 -Recurse -Force -ErrorAction SilentlyContinue
    }
}


Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
