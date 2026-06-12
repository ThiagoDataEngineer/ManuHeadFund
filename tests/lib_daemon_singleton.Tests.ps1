# lib_daemon_singleton.Tests.ps1 -- Guard de instancia unica (anti-duplicata).
# Pester 3.x. PS 5.1. Minimo mock: usa processos REAIS (child sleep) pra simular
# "outra instancia viva", refletindo exatamente o que o daemon executa em producao.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_daemon_singleton.ps1")

Describe "lib_daemon_singleton - Enter/Test/Exit" {

    BeforeEach {
        $script:lockDir = Join-Path $env:TEMP ("dsglock_" + [guid]::NewGuid().ToString("N").Substring(0,8))
        New-Item -ItemType Directory -Path $script:lockDir -Force | Out-Null
        $script:children = @()
    }
    AfterEach {
        foreach ($c in $script:children) { try { Stop-Process -Id $c -Force -ErrorAction SilentlyContinue } catch {} }
        Remove-Item $script:lockDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    function New-SleeperProcess {
        # Inicia um processo real de curta duracao e retorna seu PID (simula "outra instancia").
        $p = Start-Process powershell.exe -ArgumentList @("-NoProfile","-Command","Start-Sleep 60") `
                -WindowStyle Hidden -PassThru
        $script:children += $p.Id
        return $p
    }

    Context "Lock ausente / aquisicao limpa" {
        It "Test-DaemonRunning = false quando nao ha lock" {
            (Test-DaemonRunning -Name "scan_master" -LockDir $script:lockDir) | Should Be $false
        }
        It "Enter adquire (true) e cria o lockfile" {
            (Enter-DaemonSingleton -Name "scan_master" -LockDir $script:lockDir) | Should Be $true
            (Test-Path (Get-DaemonLockPath -Name "scan_master" -LockDir $script:lockDir)) | Should Be $true
        }
        It "Apos Enter, Test-DaemonRunning = true (somos a instancia viva)" {
            Enter-DaemonSingleton -Name "scan_master" -LockDir $script:lockDir | Out-Null
            (Test-DaemonRunning -Name "scan_master" -LockDir $script:lockDir) | Should Be $true
        }
    }

    Context "Re-entrancia do MESMO processo (idempotente)" {
        It "Enter duas vezes no mesmo processo = true ambas (donos do lock)" {
            (Enter-DaemonSingleton -Name "gem_loop" -LockDir $script:lockDir) | Should Be $true
            (Enter-DaemonSingleton -Name "gem_loop" -LockDir $script:lockDir) | Should Be $true
        }
    }

    Context "OUTRA instancia viva detem o lock (processo real)" {
        It "Enter retorna FALSE quando outro PID vivo detem o lock" {
            $other = New-SleeperProcess
            # Grava lock como se 'other' fosse o dono vivo
            $payload = [ordered]@{
                name = "scan_master"; pid = $other.Id
                start_ticks = $other.StartTime.Ticks
                ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            } | ConvertTo-Json -Compress
            Set-Content -Path (Get-DaemonLockPath -Name "scan_master" -LockDir $script:lockDir) -Value $payload -Encoding UTF8

            (Test-DaemonRunning -Name "scan_master" -LockDir $script:lockDir) | Should Be $true
            (Enter-DaemonSingleton -Name "scan_master" -LockDir $script:lockDir) | Should Be $false
        }
    }

    Context "Lock STALE (PID morto) = aquisicao permitida" {
        It "Test-DaemonRunning = false quando PID do lock esta morto" {
            $dead = New-SleeperProcess
            $deadPid = $dead.Id
            $deadTicks = $dead.StartTime.Ticks
            Stop-Process -Id $deadPid -Force
            Start-Sleep -Milliseconds 500   # garante morte
            $payload = [ordered]@{ name="scan_master"; pid=$deadPid; start_ticks=$deadTicks; ts="x" } | ConvertTo-Json -Compress
            Set-Content -Path (Get-DaemonLockPath -Name "scan_master" -LockDir $script:lockDir) -Value $payload -Encoding UTF8

            (Test-DaemonRunning -Name "scan_master" -LockDir $script:lockDir) | Should Be $false
            (Enter-DaemonSingleton -Name "scan_master" -LockDir $script:lockDir) | Should Be $true
        }
    }

    Context "Guard de PID-reuse (start_ticks nao bate)" {
        It "Lock com PID vivo mas start_ticks errado = stale (SO reusou o PID)" {
            $other = New-SleeperProcess
            $payload = [ordered]@{
                name="scan_master"; pid=$other.Id
                start_ticks = ($other.StartTime.Ticks - 999999999)   # ticks deliberadamente errados
                ts="x"
            } | ConvertTo-Json -Compress
            Set-Content -Path (Get-DaemonLockPath -Name "scan_master" -LockDir $script:lockDir) -Value $payload -Encoding UTF8
            (Test-DaemonRunning -Name "scan_master" -LockDir $script:lockDir) | Should Be $false
        }
    }

    Context "Lock corrompido = tratado como ausente" {
        It "JSON invalido nao quebra; Test = false e Enter = true" {
            Set-Content -Path (Get-DaemonLockPath -Name "scan_master" -LockDir $script:lockDir) -Value "{lixo nao-json" -Encoding UTF8
            (Test-DaemonRunning -Name "scan_master" -LockDir $script:lockDir) | Should Be $false
            (Enter-DaemonSingleton -Name "scan_master" -LockDir $script:lockDir) | Should Be $true
        }
    }

    Context "Exit-DaemonSingleton libera so o lock proprio" {
        It "Exit remove o lock quando e nosso" {
            Enter-DaemonSingleton -Name "scan_master" -LockDir $script:lockDir | Out-Null
            Exit-DaemonSingleton -Name "scan_master" -LockDir $script:lockDir
            (Test-Path (Get-DaemonLockPath -Name "scan_master" -LockDir $script:lockDir)) | Should Be $false
        }
        It "Exit NAO remove lock de outra instancia viva" {
            $other = New-SleeperProcess
            $payload = [ordered]@{ name="scan_master"; pid=$other.Id; start_ticks=$other.StartTime.Ticks; ts="x" } | ConvertTo-Json -Compress
            $lockPath = Get-DaemonLockPath -Name "scan_master" -LockDir $script:lockDir
            Set-Content -Path $lockPath -Value $payload -Encoding UTF8
            Exit-DaemonSingleton -Name "scan_master" -LockDir $script:lockDir
            (Test-Path $lockPath) | Should Be $true   # preservado (nao e nosso)
        }
    }

    Context "Stop-DaemonByLock - mata por PID do lock + libera" {
        It "Mata o processo do lock e remove o lockfile" {
            $other = New-SleeperProcess
            $lockPath = Get-DaemonLockPath -Name "scan_master" -LockDir $script:lockDir
            $payload = [ordered]@{ name="scan_master"; pid=$other.Id; start_ticks=$other.StartTime.Ticks; ts="x" } | ConvertTo-Json -Compress
            Set-Content -Path $lockPath -Value $payload -Encoding UTF8

            $killed = Stop-DaemonByLock -Name "scan_master" -LockDir $script:lockDir
            $killed | Should Be $other.Id
            Start-Sleep -Milliseconds 400
            (Get-Process -Id $other.Id -ErrorAction SilentlyContinue) | Should BeNullOrEmpty   # morto
            (Test-Path $lockPath) | Should Be $false                                            # lock liberado
        }
        It "Apos Stop, novo Enter consegue adquirir (substituicao limpa)" {
            $other = New-SleeperProcess
            $payload = [ordered]@{ name="gem_loop"; pid=$other.Id; start_ticks=$other.StartTime.Ticks; ts="x" } | ConvertTo-Json -Compress
            Set-Content -Path (Get-DaemonLockPath -Name "gem_loop" -LockDir $script:lockDir) -Value $payload -Encoding UTF8

            Stop-DaemonByLock -Name "gem_loop" -LockDir $script:lockDir | Out-Null
            (Enter-DaemonSingleton -Name "gem_loop" -LockDir $script:lockDir) | Should Be $true
        }
        It "Sem lock = no-op, retorna null" {
            (Stop-DaemonByLock -Name "inexistente" -LockDir $script:lockDir) | Should BeNullOrEmpty
        }
    }

    Context "Daemons distintos nao colidem" {
        It "Enter de scan_master e gem_loop ambos true (locks separados)" {
            (Enter-DaemonSingleton -Name "scan_master" -LockDir $script:lockDir) | Should Be $true
            (Enter-DaemonSingleton -Name "gem_loop"    -LockDir $script:lockDir) | Should Be $true
        }
    }
}
