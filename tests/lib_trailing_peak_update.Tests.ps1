# lib_trailing_peak_update.Tests.ps1 — 3 TDD happy path

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_trailing_peak_update.ps1")

$global:JOURNAL_DIR = Join-Path $PSScriptRoot "test_journal"

Describe "TrailingPeakUpdate: Update-TrailingPeakLive" {
    It "atualiza peak se price > old peak" {
        $file = Join-Path $global:JOURNAL_DIR "trailing_test.json"
        @(
            @{ market="MONUSDT"; entry=0.02146; peak=0.02341; stopCurrent=0.01047; phase=0 }
        ) | ConvertTo-Json | Set-Content $file

        $result = Update-TrailingPeakLive -Market "MONUSDT" -CurrentPrice 0.03000 -TrailingFile $file
        $result.updated | Should Be $true
        $result.new_peak | Should Be 0.03000

        $updated = Get-Content $file | ConvertFrom-Json
        $updated[0].peak | Should Be 0.03000
        Remove-Item $file
    }

}

Describe "TrailingPeakUpdate: Get-MonusdtPeakStatus" {
    It "retorna status de MONUSDT" {
        $file = Join-Path $global:JOURNAL_DIR "trailing_test.json"
        @(
            @{ market="MONUSDT"; peak=0.02341; phase=0 }
        ) | ConvertTo-Json | Set-Content $file

        $status = Get-MonusdtPeakStatus -TrailingFile $file
        $status.market | Should Be "MONUSDT"
        $status.peak | Should Be 0.02341
        Remove-Item $file
    }

    It "retorna null se MONUSDT não existe" {
        $file = Join-Path $global:JOURNAL_DIR "trailing_test.json"
        @(
            @{ market="OTHERTOKEN"; peak=0.05 }
        ) | ConvertTo-Json | Set-Content $file

        $status = Get-MonusdtPeakStatus -TrailingFile $file
        $status | Should Be $null
        Remove-Item $file
    }
}
