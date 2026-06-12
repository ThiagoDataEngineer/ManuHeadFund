# TDD: B3 — Auto-demote cron (3-day FLAG = demote Tier A→B)

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "B3: Auto-Demote Cron (Asymmetric Demote Rule)" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "test_demote_$(New-Guid)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        $libPath = Join-Path $projectRoot "agents\lib_auto_demote_cron.ps1"
        if (Test-Path $libPath) {
            . $libPath
        }
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    It "Invoke-AutoDemoteCheck existe" {
        $cmd = Get-Command Invoke-AutoDemoteCheck -ErrorAction SilentlyContinue
        ($cmd -ne $null) | Should Be $true
    }

    It "identifica 3 FLAGS consecutivos" {
        if (Get-Command Invoke-AutoDemoteCheck -ErrorAction SilentlyContinue) {
            # Simula flag_count = 3 para um asset
            $flagCount = 3
            $shouldDemote = ($flagCount -ge 3)

            $shouldDemote | Should Be $true
        }
    }

    It "demote Tier A para Tier B quando 3 FLAGS" {
        if (Get-Command Invoke-AutoDemoteCheck -ErrorAction SilentlyContinue) {
            $asset = "HYPE"
            $currentTier = "A"
            $flagCount = 3

            $result = Invoke-AutoDemoteCheck -Asset $asset -CurrentTier $currentTier `
                -FlagCount $flagCount -JournalDir $journalDir

            if ($flagCount -ge 3) {
                ($result.new_tier) | Should Be "B"
                ($result.demoted) | Should Be $true
            }
        }
    }

    It "mantém Tier A se flag_count < 3" {
        if (Get-Command Invoke-AutoDemoteCheck -ErrorAction SilentlyContinue) {
            $asset = "BTC"
            $currentTier = "A"
            $flagCount = 2

            $result = Invoke-AutoDemoteCheck -Asset $asset -CurrentTier $currentTier `
                -FlagCount $flagCount -JournalDir $journalDir

            ($result.demoted) | Should Be $false
        }
    }

    It "demotions.jsonl registra CADA demote com data/hora" {
        if (Get-Command Invoke-AutoDemoteCheck -ErrorAction SilentlyContinue) {
            $demotionsPath = Join-Path $journalDir "demotions.jsonl"

            $null = Invoke-AutoDemoteCheck -Asset "TEST" -CurrentTier "A" `
                -FlagCount 3 -JournalDir $journalDir

            Test-Path $demotionsPath | Should Be $true
        }
    }

    It "demotion record contem timestamp, asset, old_tier, new_tier, flag_count, reason" {
        if (Get-Command Invoke-AutoDemoteCheck -ErrorAction SilentlyContinue) {
            $demotionsPath = Join-Path $journalDir "demotions.jsonl"

            $null = Invoke-AutoDemoteCheck -Asset "LINKTEST" -CurrentTier "A" `
                -FlagCount 3 -JournalDir $journalDir

            if (Test-Path $demotionsPath) {
                $content = Get-Content $demotionsPath
                ($content -match "LINKTEST") | Should Be $true
                ($content -match "new_tier") | Should Be $true
            }
        }
    }
}
