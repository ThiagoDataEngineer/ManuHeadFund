# promotion_sizing.Tests.ps1 -- TDD Resolve-PromotionSizing integration
# Pester 3.x. UTF-8 BOM.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_promotion_ladder.ps1")

$testDir = Join-Path $env:TEMP ("ps_test_" + [Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
$pipelinePath = Join-Path $testDir "promotion_pipeline.jsonl"

Describe "Resolve-PromotionSizing" {

    It "market nao registrado retorna BaseSize unchanged (compat)" {
        $r = Resolve-PromotionSizing -PipelinePath $pipelinePath -Market "UNKNOWN" -BaseSize 50
        $r.size_usd | Should Be 50
        $r.allowed | Should Be $true
        $r.source | Should Be "no_ladder_entry"
    }

    It "OBSERVATION (state 1) retorna 0 e blocked" {
        Add-PromotionEvent -Path $pipelinePath -Market "OBSUSDT" -Event "discovered" | Out-Null
        Add-PromotionEvent -Path $pipelinePath -Market "OBSUSDT" -Event "promoted" -TierState 1 | Out-Null

        $r = Resolve-PromotionSizing -PipelinePath $pipelinePath -Market "OBSUSDT" -BaseSize 100
        $r.size_usd | Should Be 0
        $r.allowed | Should Be $false
        $r.tier_state | Should Be 1
    }

    It "PAPER_C (state 2) reduz BaseSize para 25%" {
        Add-PromotionEvent -Path $pipelinePath -Market "PCUSDT" -Event "discovered" | Out-Null
        Add-PromotionEvent -Path $pipelinePath -Market "PCUSDT" -Event "promoted" -TierState 2 | Out-Null

        $r = Resolve-PromotionSizing -PipelinePath $pipelinePath -Market "PCUSDT" -BaseSize 100
        $r.size_usd | Should Be 25
        $r.allowed | Should Be $true
        $r.tier_state | Should Be 2
    }

    It "PAPER_B (state 3) reduz para 50%" {
        Add-PromotionEvent -Path $pipelinePath -Market "PBUSDT" -Event "discovered" | Out-Null
        Add-PromotionEvent -Path $pipelinePath -Market "PBUSDT" -Event "promoted" -TierState 3 | Out-Null

        $r = Resolve-PromotionSizing -PipelinePath $pipelinePath -Market "PBUSDT" -BaseSize 80
        $r.size_usd | Should Be 40
        $r.allowed | Should Be $true
    }

    It "TIER_A_LIVE (state 4) mantem 100%" {
        Add-PromotionEvent -Path $pipelinePath -Market "LIVEUSDT" -Event "discovered" | Out-Null
        Add-PromotionEvent -Path $pipelinePath -Market "LIVEUSDT" -Event "promoted" -TierState 4 | Out-Null

        $r = Resolve-PromotionSizing -PipelinePath $pipelinePath -Market "LIVEUSDT" -BaseSize 100
        $r.size_usd | Should Be 100
        $r.allowed | Should Be $true
        $r.tier_state | Should Be 4
    }
}
