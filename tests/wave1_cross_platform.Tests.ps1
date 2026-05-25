# wave1_cross_platform.Tests.ps1
# TDD para Onda 1 de migração: scripts standalone simples
# Critérios: cada script deve carregar sem erro em PS 5.1 e ser cross-platform

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptsDir = Join-Path $projectRoot "scripts"
$agentsDir = Join-Path $projectRoot "agents"

Describe "Wave 1: Cross-Platform Scripts" {
    
    $wave1Scripts = @(
        "daily_kelly_audit.ps1",
        "cron_staleness_audit.ps1",
        "whale_watcher_cron.ps1",
        "daily_summary_digest.ps1"
    )
    
    Context "Script files exist" {
        foreach ($script in $wave1Scripts) {
            It "$script should exist in scripts/" {
                $path = Join-Path $scriptsDir $script
                Test-Path $path | Should Be $true
            }
        }
    }
    
    Context "No backslash paths (cross-platform)" {
        foreach ($script in $wave1Scripts) {
            It "$script should not have backslash paths" {
                $path = Join-Path $scriptsDir $script
                $content = Get-Content $path -Raw
                # Não deve ter "..\\" em strings (ignorando comentários)
                $hasBackslashPath = $content -match '"\.\.\\\\\w+"' -or $content -match "'\.\.\\\\\w+'"
                $hasBackslashPath | Should Be $false
            }
        }
    }
    
    Context "No reserved variable names" {
        foreach ($script in $wave1Scripts) {
            It "$script should not assign to reserved \$env" {
                $path = Join-Path $scriptsDir $script
                $content = Get-Content $path -Raw
                # Não deve ter "$env =" (sobrescreve var reservada)
                $hasEnvAssign = $content -match '\$env\s*=\s*[^:]'
                $hasEnvAssign | Should Be $false
            }
            
            It "$script should not assign to reserved \$IsLinux" {
                $path = Join-Path $scriptsDir $script
                $content = Get-Content $path -Raw
                $hasIsLinuxAssign = $content -match '\$IsLinux\s*=' -and $content -notmatch '\$IsLinuxOS'
                $hasIsLinuxAssign | Should Be $false
            }
        }
    }
    
    Context "Compatible Join-Path syntax (PS 5.1 + 7+)" {
        foreach ($script in $wave1Scripts) {
            It "$script should not use Join-Path with 3+ args (PS 5.1 incompatible)" {
                $path = Join-Path $scriptsDir $script
                $content = Get-Content $path -Raw
                # Não deve ter "Join-Path X Y Z" (3+ args só funciona em PS 7+)
                $invalid = [regex]::Matches($content, 'Join-Path\s+\$\w+\s+"[^"]+"\s+"[^"]+"')
                $invalid.Count | Should Be 0
            }
        }
    }
}
