# B16 fix 2026-05-20 PM6+390min.
# Watchdog backoff exponencial + kill switch.
# Antes: processo morrendo logo apos start = respawn-loop infinito (potencial 1000x/h).
# Agora: backoff exponencial (2^n segundos) + kill switch apos N falhas consecutivas.

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_watchdog_backoff.ps1")

Describe "B16 Test-RespawnAllowed" {
    BeforeEach {
        $script:statePath = Join-Path $env:TEMP "b16_state_$([guid]::NewGuid()).json"
    }
    AfterEach {
        Remove-Item $statePath -Force -ErrorAction SilentlyContinue
    }

    It "1a tentativa: permite respawn imediato (sem historico)" {
        $r = Test-RespawnAllowed -Path $statePath -ProcName "scan_master"
        $r.allowed | Should Be $true
        $r.wait_seconds | Should Be 0
    }
    It "Apos 1 falha: backoff 2s" {
        Add-RespawnFailure -Path $statePath -ProcName "scan_master"
        $r = Test-RespawnAllowed -Path $statePath -ProcName "scan_master"
        $r.allowed | Should Be $false
        $r.wait_seconds | Should BeGreaterThan 0
        $r.wait_seconds | Should BeLessThan 5
    }
    It "Apos 3 falhas: backoff 8s (2^3=8)" {
        1..3 | ForEach-Object { Add-RespawnFailure -Path $statePath -ProcName "scan_master" }
        $r = Test-RespawnAllowed -Path $statePath -ProcName "scan_master"
        $r.wait_seconds | Should BeGreaterThan 3
        $r.wait_seconds | Should BeLessThan 17
    }
    It "Apos MaxFailures consecutivas: kill switch (allowed=false even after wait)" {
        1..10 | ForEach-Object { Add-RespawnFailure -Path $statePath -ProcName "scan_master" }
        $r = Test-RespawnAllowed -Path $statePath -ProcName "scan_master" -MaxFailures 5
        $r.killed_switch | Should Be $true
        $r.allowed | Should Be $false
    }
    It "Reset-RespawnState zera contador apos respawn success" {
        1..3 | ForEach-Object { Add-RespawnFailure -Path $statePath -ProcName "scan_master" }
        Reset-RespawnState -Path $statePath -ProcName "scan_master"
        $r = Test-RespawnAllowed -Path $statePath -ProcName "scan_master"
        $r.allowed | Should Be $true
    }
    It "Procnames isolados: scan_master failures NAO afetam gem_loop" {
        1..5 | ForEach-Object { Add-RespawnFailure -Path $statePath -ProcName "scan_master" }
        $r = Test-RespawnAllowed -Path $statePath -ProcName "gem_loop"
        $r.allowed | Should Be $true
    }
}
