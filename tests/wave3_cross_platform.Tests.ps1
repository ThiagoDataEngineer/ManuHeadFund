# wave3_cross_platform.Tests.ps1
# TDD para Onda 3: scripts com dependencias LLM

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptsDir = Join-Path $projectRoot "scripts"

Describe "Wave 3: Cross-Platform Scripts (with LLM)" {
    
    $wave3Scripts = @(
        "promotion_weekly_cron.ps1",
        "weekly_provider_cost_report.ps1"
    )
    
    Context "Script files exist" {
        foreach ($script in $wave3Scripts) {
            It "$script should exist in scripts/" {
                $path = Join-Path $scriptsDir $script
                Test-Path $path | Should Be $true
            }
        }
    }
    
    Context "No reserved variable assignments" {
        foreach ($script in $wave3Scripts) {
            It "$script should not assign to reserved \$env" {
                $path = Join-Path $scriptsDir $script
                $content = Get-Content $path -Raw
                $hasEnvAssign = $content -match '\$env\s*=\s*[^:]'
                $hasEnvAssign | Should Be $false
            }
        }
    }
    
    Context "Compatible Join-Path syntax" {
        foreach ($script in $wave3Scripts) {
            It "$script should not use Join-Path with 3+ args" {
                $path = Join-Path $scriptsDir $script
                $content = Get-Content $path -Raw
                $invalid = [regex]::Matches($content, 'Join-Path\s+\$\w+\s+"[^"]+"\s+"[^"]+"')
                $invalid.Count | Should Be 0
            }
        }
    }
    
    Context "Workflow has all 3 wave jobs" {
        $workflowPath = Join-Path $projectRoot ".github\workflows\trading-pipeline.yml"
        $workflowContent = Get-Content $workflowPath -Raw
        
        It "should have promotion-weekly job" {
            $workflowContent -match 'promotion-weekly:' | Should Be $true
        }
        
        It "should have weekly-cost-report job" {
            $workflowContent -match 'weekly-cost-report:' | Should Be $true
        }
        
        It "should have weekly-data-refresh job" {
            $workflowContent -match 'weekly-data-refresh:' | Should Be $true
        }
    }
}
