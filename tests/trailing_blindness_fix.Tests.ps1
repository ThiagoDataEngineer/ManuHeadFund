# trailing_blindness_fix.Tests.ps1 -- TDD do trailing cego (spot + futures + SHORT)
# Causa raiz: peak nao atualizava no loop vivo + thresholds grossos (+5/+10)
# matavam micro-swings (HYPE pico +3.26% travou ZERO).
# Fix: lock fino +2.5% -> breakeven; side-aware (LONG/SHORT); monotonico.
# Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\lib_trailing_peak_update.ps1"

Describe "Trailing Peak Update - side-aware + fino" {

    BeforeEach {
        $script:tf = Join-Path $env:TEMP "trail_test_$([guid]::NewGuid().ToString('N').Substring(0,8)).json"
    }
    AfterEach {
        if (Test-Path $script:tf) { Remove-Item $script:tf -Force }
    }

    function Write-TrailFile($obj) { ,@($obj) | ConvertTo-Json -Depth 5 | Set-Content $script:tf -Encoding UTF8 }
    function Read-Pos { (Get-Content $script:tf -Raw | ConvertFrom-Json) | Select-Object -First 1 }

    Context "LONG - caso HYPE (micro swing trava breakeven)" {

        It "pico +3.26pct (77.08) move SL p/ breakeven (entry)" {
            Write-TrailFile @{ market="HYPEUSDT"; side="LONG"; entry=74.65; peak=75.26; stopCurrent=68.67; phase=0; active=$true }
            $r = Update-TrailingPeakLive -Market "HYPEUSDT" -CurrentPrice 77.08 -TrailingFile $script:tf
            $r.updated | Should Be $true
            $p = Read-Pos
            $p.peak | Should Be 77.08
            $p.phase | Should Be 1
            # SL sobe p/ breakeven = entry (trava o trade risk-free)
            $p.stopCurrent | Should Be 74.65
        }

        It "pico +5pct move SL p/ lock acima de breakeven (fase 2)" {
            Write-TrailFile @{ market="ZECUSDT"; side="LONG"; entry=100.0; peak=101.0; stopCurrent=92.0; phase=0; active=$true }
            $r = Update-TrailingPeakLive -Market "ZECUSDT" -CurrentPrice 105.0 -TrailingFile $script:tf
            $p = Read-Pos
            $p.phase | Should Be 2
            ($p.stopCurrent -gt 100.0) | Should Be $true   # acima do breakeven
            ($p.stopCurrent -lt 105.0) | Should Be $true
        }

        It "pico +10pct entra em trailing largo (fase 3)" {
            Write-TrailFile @{ market="SUIUSDT"; side="LONG"; entry=100.0; peak=101.0; stopCurrent=92.0; phase=0; active=$true }
            $r = Update-TrailingPeakLive -Market "SUIUSDT" -CurrentPrice 110.0 -TrailingFile $script:tf
            $p = Read-Pos
            $p.phase | Should Be 3
            ($p.stopCurrent -ge 106.0) | Should Be $true
        }

        It "SL e MONOTONICO (nunca desce se preco recua)" {
            Write-TrailFile @{ market="XUSDT"; side="LONG"; entry=100.0; peak=100.0; stopCurrent=92.0; phase=0; active=$true }
            Update-TrailingPeakLive -Market "XUSDT" -CurrentPrice 105.0 -TrailingFile $script:tf | Out-Null
            $afterPeak = (Read-Pos).stopCurrent
            # preco recua p/ 101 -> SL NAO pode descer
            Update-TrailingPeakLive -Market "XUSDT" -CurrentPrice 101.0 -TrailingFile $script:tf | Out-Null
            $afterDip = (Read-Pos).stopCurrent
            ($afterDip -ge $afterPeak) | Should Be $true
        }

        It "preco abaixo da entrada nao muda fase (sem lucro = sem lock)" {
            Write-TrailFile @{ market="LUSDT"; side="LONG"; entry=100.0; peak=100.5; stopCurrent=92.0; phase=0; active=$true }
            Update-TrailingPeakLive -Market "LUSDT" -CurrentPrice 99.0 -TrailingFile $script:tf | Out-Null
            $p = Read-Pos
            $p.phase | Should Be 0
            $p.stopCurrent | Should Be 92.0
        }
    }

    Context "SHORT (futures) - espelhado" {

        It "queda -3pct move SL p/ breakeven (entry)" {
            Write-TrailFile @{ market="ZEXUSDT"; side="SHORT"; entry=100.0; peak=99.0; stopCurrent=108.0; phase=0; active=$true }
            Update-TrailingPeakLive -Market "ZEXUSDT" -CurrentPrice 97.0 -TrailingFile $script:tf | Out-Null
            $p = Read-Pos
            $p.phase | Should Be 1
            $p.stopCurrent | Should Be 100.0   # breakeven
        }

        It "queda -6pct trava lucro (SL abaixo do entry)" {
            Write-TrailFile @{ market="DEROUSDT"; side="SHORT"; entry=100.0; peak=99.0; stopCurrent=108.0; phase=0; active=$true }
            Update-TrailingPeakLive -Market "DEROUSDT" -CurrentPrice 94.0 -TrailingFile $script:tf | Out-Null
            $p = Read-Pos
            $p.phase | Should Be 2
            ($p.stopCurrent -lt 100.0) | Should Be $true   # lock abaixo do breakeven
        }

        It "SHORT SL monotonico (nunca sobe se preco volta)" {
            Write-TrailFile @{ market="SUSDT"; side="SHORT"; entry=100.0; peak=100.0; stopCurrent=108.0; phase=0; active=$true }
            Update-TrailingPeakLive -Market "SUSDT" -CurrentPrice 94.0 -TrailingFile $script:tf | Out-Null
            $afterDrop = (Read-Pos).stopCurrent
            Update-TrailingPeakLive -Market "SUSDT" -CurrentPrice 99.0 -TrailingFile $script:tf | Out-Null
            $afterBounce = (Read-Pos).stopCurrent
            ($afterBounce -le $afterDrop) | Should Be $true
        }
    }

    Context "Path default (regressao do bug 'if' PS 5.1)" {

        It "funciona SEM -TrailingFile usando JOURNAL_DIR (nao estoura no if)" {
            # Bug: Join-Path (if ...) era invalido em PS 5.1 -> 'termo if nao reconhecido'
            # (9173 falhas no position_watcher). Aqui exercita o caminho default.
            $tmpDir = Join-Path $env:TEMP "trailjdir_$([guid]::NewGuid().ToString('N').Substring(0,8))"
            New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
            $tf = Join-Path $tmpDir "trailing_positions.json"
            ,@(@{ market="HYPEUSDT"; side="LONG"; entry=74.65; peak=75.0; stopCurrent=68.67; phase=0; active=$true }) | ConvertTo-Json -Depth 5 | Set-Content $tf -Encoding UTF8
            $old = $global:JOURNAL_DIR
            $global:JOURNAL_DIR = $tmpDir
            try {
                # NAO passa -TrailingFile -> usa o path default (linha que tinha o bug)
                $r = Update-TrailingPeakLive -Market "HYPEUSDT" -CurrentPrice 77.08
                $r.updated | Should Be $true
                $p = (Get-Content $tf -Raw | ConvertFrom-Json) | Select-Object -First 1
                $p.stopCurrent | Should Be 74.65
            } finally {
                $global:JOURNAL_DIR = $old
                Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Robustez" {

        It "arquivo inexistente nao quebra" {
            $r = Update-TrailingPeakLive -Market "X" -CurrentPrice 1 -TrailingFile (Join-Path $env:TEMP "nope_$([guid]::NewGuid().ToString('N')).json")
            $r.updated | Should Be $false
        }

        It "market ausente no arquivo = sem update" {
            Write-TrailFile @{ market="AAA"; side="LONG"; entry=1.0; peak=1.0; stopCurrent=0.9; phase=0; active=$true }
            $r = Update-TrailingPeakLive -Market "BBB" -CurrentPrice 2 -TrailingFile $script:tf
            $r.updated | Should Be $false
        }
    }
}
