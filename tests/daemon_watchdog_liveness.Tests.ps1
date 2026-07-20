# tests/daemon_watchdog_liveness.Tests.ps1
# Regressao (2026-07-07): Test-DaemonHealthy tratava o lock 'ts' (START timestamp,
# gravado 1x no boot) como heartbeat rolante -> marcava stale qualquer daemon
# vivo > MaxAgeMinutes -> "dead/stale" eterno (Down=4) na frota religada.
# Regra correta: PID do lock VIVO = daemon saudavel, independente da idade do ts.
#
# Pester 3.4 compativel.

$ErrorActionPreference = "Stop"
# O lib chama Export-ModuleMember no fim (falha se dot-sourced fora de modulo).
# Carrega tolerando esse erro — as funcoes ja ficam definidas no escopo.
try { . (Join-Path (Split-Path $PSScriptRoot -Parent) "agents/lib_daemon_watchdog_v2.ps1") } catch { }

Describe "Test-DaemonHealthy liveness por PID (nao por idade do lock)" {

    BeforeEach {
        $script:lockDir = Join-Path $env:TEMP "wd_live_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:lockDir -Force | Out-Null
    }
    AfterEach {
        Remove-Item $script:lockDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "PID vivo + lock 'antigo' (ts de horas atras) => SAUDAVEL" {
        # ts bem no passado (simula lock de boot antigo); PID = este processo (vivo).
        $lock = @{ name = "d1"; pid = $PID; ts = (Get-Date).AddHours(-6).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
        ($lock | ConvertTo-Json -Compress) | Set-Content (Join-Path $script:lockDir "d1.lock") -Encoding UTF8
        Test-DaemonHealthy -DaemonName "d1" -LockDir $script:lockDir -MaxAgeMinutes 5 | Should Be $true
    }

    It "ts em UTC ('Z') com PID vivo => SAUDAVEL (nao confunde tz)" {
        $lock = @{ name = "d2"; pid = $PID; ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
        ($lock | ConvertTo-Json -Compress) | Set-Content (Join-Path $script:lockDir "d2.lock") -Encoding UTF8
        Test-DaemonHealthy -DaemonName "d2" -LockDir $script:lockDir -MaxAgeMinutes 5 | Should Be $true
    }

    It "PID morto => DOWN" {
        # PID improvavel de existir
        $lock = @{ name = "d3"; pid = 999999; ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
        ($lock | ConvertTo-Json -Compress) | Set-Content (Join-Path $script:lockDir "d3.lock") -Encoding UTF8
        Test-DaemonHealthy -DaemonName "d3" -LockDir $script:lockDir -MaxAgeMinutes 5 | Should Be $false
    }

    It "sem lock => DOWN" {
        Test-DaemonHealthy -DaemonName "inexistente" -LockDir $script:lockDir -MaxAgeMinutes 5 | Should Be $false
    }

    Context "Fallback pidfile (sentinel_movers / collect_1h_klines usam journal/<name>.pid)" {
        # $lockDir aqui e journal/daemon_locks; o journal e o pai.
        It "sentinel_movers vivo via journal/sentinel.pid (sem .lock) => SAUDAVEL" {
            $journal = Split-Path $script:lockDir -Parent
            "$PID" | Set-Content (Join-Path $journal "sentinel.pid") -Encoding UTF8
            Test-DaemonHealthy -DaemonName "sentinel_movers" -LockDir $script:lockDir -MaxAgeMinutes 5 | Should Be $true
        }
        It "collect_1h_klines PID morto no pidfile => DOWN" {
            $journal = Split-Path $script:lockDir -Parent
            "999999" | Set-Content (Join-Path $journal "collect_1h.pid") -Encoding UTF8
            Test-DaemonHealthy -DaemonName "collect_1h_klines" -LockDir $script:lockDir -MaxAgeMinutes 5 | Should Be $false
        }
    }
}
