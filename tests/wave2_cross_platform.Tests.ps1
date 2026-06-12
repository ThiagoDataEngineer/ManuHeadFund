# wave2_cross_platform.Tests.ps1
# TDD para Onda 2 de migração: scripts médios (com scanner)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptsDir = Join-Path $projectRoot "scripts"

Describe "Wave 2: Cross-Platform Scripts" {
    
    $wave2Scripts = @(
        "cron_wss_forward_resolve.ps1",
        "weekly_data_refresh.ps1",
        "tori_proximity_scanner.ps1",
        "vol_climax_scanner.ps1"
    )
    
    Context "Script files exist" {
        foreach ($script in $wave2Scripts) {
            It "$script should exist in scripts/" {
                $path = Join-Path $scriptsDir $script
                Test-Path $path | Should Be $true
            }
        }
    }
    
    Context "No reserved variable assignments" {
        foreach ($script in $wave2Scripts) {
            It "$script should not assign to reserved \$env" {
                $path = Join-Path $scriptsDir $script
                $content = Get-Content $path -Raw
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
    
    Context "Compatible Join-Path syntax" {
        foreach ($script in $wave2Scripts) {
            It "$script should not use Join-Path with 3+ args" {
                $path = Join-Path $scriptsDir $script
                $content = Get-Content $path -Raw
                $invalid = [regex]::Matches($content, 'Join-Path\s+\$\w+\s+"[^"]+"\s+"[^"]+"')
                $invalid.Count | Should Be 0
            }
        }
    }
    
    Context "Send-TelegramAlert is defined in lib_telegram" {
        It "lib_telegram.ps1 should have Send-TelegramAlert function" {
            $libPath = Join-Path $projectRoot "agents\lib_telegram.ps1"
            $content = Get-Content $libPath -Raw
            $content -match 'function Send-TelegramAlert' | Should Be $true
        }
    }
}
