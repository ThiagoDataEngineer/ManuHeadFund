# B4 prevention 2026-05-20 PM6+: Test-DaemonDrift unit test.
# Drift = qualquer .ps1 em AgentsDir com LastWriteTime > processo.StartTime + ThresholdHours.

Describe "B4 Test-DaemonDrift" {
    BeforeAll {
        # Source apenas a funcao do watchdog (extraida pra test isolation)
        # Em prod, vive em scripts/watchdog_paper.ps1. Aqui replicamos pra test.
        function Test-DaemonDrift {
            param([int] $ProcessId, [string] $AgentsDir, [double] $ThresholdHours = 1)
            $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
            if (-not $proc) { return $false }
            $startTime = $proc.StartTime
            if (-not $startTime) { return $false }
            $cutoff = $startTime.AddHours($ThresholdHours)
            $newer = Get-ChildItem -Path $AgentsDir -Filter "*.ps1" -ErrorAction SilentlyContinue |
                     Where-Object { $_.LastWriteTime -gt $cutoff } |
                     Select-Object -First 1
            return ($null -ne $newer)
        }
        $script:tmpAgents = Join-Path $env:TEMP "b4_drift_$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmpAgents -Force | Out-Null
    }
    AfterAll {
        Remove-Item $tmpAgents -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "PID invalido retorna false" {
        (Test-DaemonDrift -ProcessId 999999 -AgentsDir $tmpAgents) | Should Be $false
    }
    It "agents dir vazio retorna false (sem drift)" {
        $myPid = $PID
        (Test-DaemonDrift -ProcessId $myPid -AgentsDir $tmpAgents -ThresholdHours 0) | Should Be $false
    }
    It "arquivo modificado APOS StartTime+threshold = drift detectado" {
        $myPid = $PID
        # Arquivo modificado AGORA (depois do StartTime do PID atual)
        $f = Join-Path $tmpAgents "new_lib.ps1"
        Set-Content -Path $f -Value "# new" -Encoding UTF8
        (Test-DaemonDrift -ProcessId $myPid -AgentsDir $tmpAgents -ThresholdHours -1) | Should Be $true
    }
    It "arquivo dentro do threshold = sem drift" {
        $myPid = $PID
        $f = Join-Path $tmpAgents "ok_lib.ps1"
        Set-Content -Path $f -Value "# ok" -Encoding UTF8
        # ThresholdHours alto = arquivo recente nao conta
        (Test-DaemonDrift -ProcessId $myPid -AgentsDir $tmpAgents -ThresholdHours 24) | Should Be $false
    }
}
