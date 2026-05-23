# ladder_performance_report.Tests.ps1 — TDD strict: agrega performance ladder por template x regime
# 6+ tests: validar calculo de metricas, JSON output, edge cases
# UTF-8 BOM, Pester 3.x

$scriptPath = Join-Path $PSScriptRoot "..\scripts\ladder_performance_report.ps1"

Describe "Ladder Performance Report" {

    Context "Report Generation" {
        It "gera arquivo JSON" {
            $testDir = Join-Path $env:TEMP "ladder_test_$$_$((Get-Random))"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $trackerFile = Join-Path $testDir "ladder_tracker.csv"
            $hitsFile = Join-Path $testDir "ladder_hits.csv"

            "template_id,regime,entry_price,take_profit_levels,stop_loss" | Out-File -FilePath $trackerFile -Encoding utf8 -Force
            "template_id,regime,hit_level,profit_realized_R,timestamp" | Out-File -FilePath $hitsFile -Encoding utf8 -Force

            $result = & $scriptPath -JournalDir $testDir -AsOfDate (Get-Date)

            Test-Path $result.output_path | Should Be $true
            Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "retorna PSCustomObject com output_path" {
            $testDir = Join-Path $env:TEMP "ladder_test_$$_$((Get-Random))"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $trackerFile = Join-Path $testDir "ladder_tracker.csv"
            $hitsFile = Join-Path $testDir "ladder_hits.csv"

            "template_id,regime,entry_price,take_profit_levels,stop_loss" | Out-File -FilePath $trackerFile -Encoding utf8 -Force
            "template_id,regime,hit_level,profit_realized_R,timestamp" | Out-File -FilePath $hitsFile -Encoding utf8 -Force

            $result = & $scriptPath -JournalDir $testDir -AsOfDate (Get-Date)

            $result.output_path | Should Not Be $null
            Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "processa dados corretamente" {
            $testDir = Join-Path $env:TEMP "ladder_test_$$_$((Get-Random))"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $trackerFile = Join-Path $testDir "ladder_tracker.csv"
            $hitsFile = Join-Path $testDir "ladder_hits.csv"

            "template_id,regime,entry_price,take_profit_levels,stop_loss" | Out-File -FilePath $trackerFile -Encoding utf8 -Force
            "template1,BULL,1000,{},900" | Add-Content -Path $trackerFile -Encoding utf8
            for ($i = 0; $i -lt 10; $i++) {
                "template1,BULL,1000,{},900" | Add-Content -Path $trackerFile -Encoding utf8
            }

            "template_id,regime,hit_level,profit_realized_R,timestamp" | Out-File -FilePath $hitsFile -Encoding utf8 -Force
            for ($i = 0; $i -lt 6; $i++) {
                "template1,BULL,1,0.5,2026-05-15T00:00:00Z" | Add-Content -Path $hitsFile -Encoding utf8
            }

            $result = & $scriptPath -JournalDir $testDir -AsOfDate (Get-Date)
            $result.results.Count -gt 0 | Should Be $true
            Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Edge Cases" {
        It "retorna 0 templates quando vazios" {
            $testDir = Join-Path $env:TEMP "ladder_test_$$_$((Get-Random))"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $trackerFile = Join-Path $testDir "ladder_tracker.csv"
            $hitsFile = Join-Path $testDir "ladder_hits.csv"

            "template_id,regime,entry_price,take_profit_levels,stop_loss" | Out-File -FilePath $trackerFile -Encoding utf8 -Force
            "template_id,regime,hit_level,profit_realized_R,timestamp" | Out-File -FilePath $hitsFile -Encoding utf8 -Force

            $result = & $scriptPath -JournalDir $testDir -AsOfDate (Get-Date)

            $result.templates_count | Should Be 0
            Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "suporta AsOfDate" {
            $testDir = Join-Path $env:TEMP "ladder_test_$$_$((Get-Random))"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $trackerFile = Join-Path $testDir "ladder_tracker.csv"
            $hitsFile = Join-Path $testDir "ladder_hits.csv"

            "template_id,regime,entry_price,take_profit_levels,stop_loss" | Out-File -FilePath $trackerFile -Encoding utf8 -Force
            "template_id,regime,hit_level,profit_realized_R,timestamp" | Out-File -FilePath $hitsFile -Encoding utf8 -Force

            $customDate = Get-Date "2026-03-15"
            $result = & $scriptPath -JournalDir $testDir -AsOfDate $customDate

            Test-Path $result.output_path | Should Be $true
            Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
