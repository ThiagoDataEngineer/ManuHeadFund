# r2_r4_drift_gem_cache.Tests.ps1 -- 2026-05-21 R2+R4 lockdown.
# Pester 3.x.
#
# R2: DriftThresholdHours bumped 1h -> 6h (default). Override via env WATCHDOG_DRIFT_THRESHOLD_H.
# R4: GEM cache check ANTES de emitir log/alert -> elimina PEAQ/PROVE detection spam.

$script:r2_here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:r2_root = Split-Path -Parent $r2_here


Describe "R2 - Watchdog drift threshold 6h" {

    It "watchdog_paper.ps1 default DriftThresholdHours = 6 (bumped de 1)" {
        $src = Get-Content (Join-Path $r2_root "scripts\watchdog_paper.ps1") -Raw -Encoding UTF8
        # Conditional default: env override OR 6
        $src | Should Match 'DriftThresholdHours\s*=\s*if\s*\(\s*\$env:WATCHDOG_DRIFT_THRESHOLD_H'
        $src | Should Match 'else\s*\{\s*6\s*\}'
    }

    It "watchdog suporta override via env var WATCHDOG_DRIFT_THRESHOLD_H" {
        $src = Get-Content (Join-Path $r2_root "scripts\watchdog_paper.ps1") -Raw -Encoding UTF8
        $src | Should Match '\$env:WATCHDOG_DRIFT_THRESHOLD_H'
    }
}


Describe "R4 - GEM cache pre-detection (filter ANTES de log/alert)" {

    It "scan_master.ps1 Invoke-GemCycle filtra gems com cache hit ANTES de emit log" {
        $src = Get-Content (Join-Path $r2_root "scripts\scan_master.ps1") -Raw -Encoding UTF8
        # Pre-fix: Write-MasterLog GemScan happened ANTES de qualquer cache check.
        # Pos-fix: cache filter happens entre Invoke-GemScan e Write-MasterLog.
        # Confirma ordem: invoke-gemscan -> test-gemrecentlyrejected -> writelog gemscan
        $invokeScanPos = $src.IndexOf('$gems = @(Invoke-GemScan -TopN $GemTopN)')
        $cacheCheckPos = $src.IndexOf('Test-GemRecentlyRejected -Path $cachePath -Market $g.market -TtlMinutes 60')
        $logPos = $src.IndexOf('Write-MasterLog "GemScan: $($gems.Count) gem(s)')
        ($invokeScanPos -gt 0) | Should Be $true
        ($cacheCheckPos -gt $invokeScanPos) | Should Be $true
        ($logPos -gt $cacheCheckPos) | Should Be $true
    }

    It "gem_loop.ps1 Invoke-GemCycle-Once filtra cache hits ANTES do encontrados log" {
        $src = Get-Content (Join-Path $r2_root "scripts\gem_loop.ps1") -Raw -Encoding UTF8
        $src | Should Match 'R4 fix 2026-05-21'
        $src | Should Match 'Test-GemRecentlyRejected'
        # Cache filter antes do log "GemScan: N gem(s) encontrados"
        $cacheCheckPos = $src.IndexOf('Test-GemRecentlyRejected')
        $logPos = $src.IndexOf('GemScan: $($gems.Count) gem(s) encontrados')
        ($cacheCheckPos -gt 0) | Should Be $true
        ($cacheCheckPos -lt $logPos) | Should Be $true
    }

    It "scan_master emite log 'skip cache' separado quando ha cached gems" {
        $src = Get-Content (Join-Path $r2_root "scripts\scan_master.ps1") -Raw -Encoding UTF8
        $src | Should Match 'gem\(s\) skip cache'
    }
}
