$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

Describe "register_wss_forward_resolve.ps1 (idempotent + dryrun)" {

    It "Script exists" {
        $f = Join-Path $root "scripts\register_wss_forward_resolve.ps1"
        (Test-Path $f) | Should Be $true
    }

    It "Cron target exists" {
        $f = Join-Path $root "scripts\cron_wss_forward_resolve.ps1"
        (Test-Path $f) | Should Be $true
    }

    It "DryRun executa sem erro + nao cria task" {
        $f = Join-Path $root "scripts\register_wss_forward_resolve.ps1"
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $f -DryRun 2>&1
        ($out -join "`n") | Should Match "DRYRUN"
        ($out -join "`n") | Should Match "CoinExWssForwardResolve"
        # Verifica que NAO criou task real
        $task = Get-ScheduledTask -TaskName "CoinExWssForwardResolve" -ErrorAction SilentlyContinue
        $task | Should Be $null
    }

    It "Calculo de proximo Sabado eh consistente" {
        # Lib calc embed (replica logica): 0..6 -> dom..sab, sab=6
        $now = [datetime]::new(2026, 5, 22, 10, 0, 0)  # sex 22/05 10am
        $expectedDays = 1  # proximo sabado eh 23/05
        $daysUntilSat = (6 - [int]$now.DayOfWeek + 7) % 7
        if ($daysUntilSat -eq 0) {
            if ($now.Hour -lt 23) { $daysUntilSat = 0 } else { $daysUntilSat = 7 }
        }
        $daysUntilSat | Should Be $expectedDays
    }

    It "Sabado 22h: agendamento eh hoje (ainda nao passou 23h)" {
        $now = [datetime]::new(2026, 5, 23, 22, 0, 0)  # sab 22/05 22h
        $daysUntilSat = (6 - [int]$now.DayOfWeek + 7) % 7
        if ($daysUntilSat -eq 0) {
            if ($now.Hour -lt 23) { $daysUntilSat = 0 } else { $daysUntilSat = 7 }
        }
        $daysUntilSat | Should Be 0  # hoje
    }

    It "Sabado 23h+: agendamento eh proximo sabado" {
        $now = [datetime]::new(2026, 5, 23, 23, 30, 0)  # sab 22/05 23:30
        $daysUntilSat = (6 - [int]$now.DayOfWeek + 7) % 7
        if ($daysUntilSat -eq 0) {
            if ($now.Hour -lt 23) { $daysUntilSat = 0 } else { $daysUntilSat = 7 }
        }
        $daysUntilSat | Should Be 7  # proximo sabado
    }
}

Describe "Property: cron_wss_forward_resolve roda sem crash" {
    It "DryRun do cron alvo executa graceful (0 pending = exit 0)" {
        $f = Join-Path $root "scripts\cron_wss_forward_resolve.ps1"
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $f -DryRun 2>&1
        $LASTEXITCODE | Should Be 0
        ($out -join "`n") | Should Match "WSS Forward Resolve cron"
    }
}
