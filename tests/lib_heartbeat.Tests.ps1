# lib_heartbeat.Tests.ps1 -- TDD do nucleo puro do heartbeat.
# Heartbeat agora le trade_outcomes do Supabase (cloud ground-truth), nao do JSONL
# local que nunca existe em runner cloud. Funcoes PURAS (sem I/O) testadas aqui.

$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_heartbeat.ps1")

Describe "Select-LatestOutcomeClosedAt" {
    It "Retorna o maior closed_at (UTC) entre os outcomes" {
        $rows = @(
            [PSCustomObject]@{ market="A"; closed_at="2026-06-20T10:00:00Z" },
            [PSCustomObject]@{ market="B"; closed_at="2026-06-20T18:30:00Z" },
            [PSCustomObject]@{ market="C"; closed_at="2026-06-20T12:00:00Z" }
        )
        $dt = Select-LatestOutcomeClosedAt -Outcomes $rows
        $dt.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") | Should Be "2026-06-20T18:30:00Z"
    }
    It "Cai para o campo 'ts' quando closed_at ausente (schema JSONL local)" {
        $rows = @( [PSCustomObject]@{ market="A"; ts="2026-06-19T09:00:00Z" } )
        $dt = Select-LatestOutcomeClosedAt -Outcomes $rows
        $dt.ToUniversalTime().ToString("yyyy-MM-dd") | Should Be "2026-06-19"
    }
    It "Retorna \$null quando lista vazia" {
        (Select-LatestOutcomeClosedAt -Outcomes @()) | Should Be $null
    }
    It "Ignora valores nao parseaveis sem quebrar" {
        $rows = @(
            [PSCustomObject]@{ market="A"; closed_at="lixo" },
            [PSCustomObject]@{ market="B"; closed_at="2026-06-20T08:00:00Z" }
        )
        (Select-LatestOutcomeClosedAt -Outcomes $rows).ToUniversalTime().ToString("HH") | Should Be "08"
    }
}

Describe "Get-HeartbeatVerdict" {
    $now = [datetime]::Parse("2026-06-20T20:00:00Z").ToUniversalTime()

    It "Sem dados -> alerta no_trades" {
        $v = Get-HeartbeatVerdict -LatestClosedAtUtc $null -NowUtc $now -ThresholdHours 6
        $v.alert  | Should Be $true
        $v.reason | Should Be "no_trades"
    }
    It "Trade recente -> sem alerta (alive)" {
        $dt = [datetime]::Parse("2026-06-20T17:00:00Z").ToUniversalTime()
        $v = Get-HeartbeatVerdict -LatestClosedAtUtc $dt -NowUtc $now -ThresholdHours 6
        $v.alert | Should Be $false
        $v.reason | Should Be "alive"
    }
    It "Trade antigo alem do threshold -> alerta stale" {
        $dt = [datetime]::Parse("2026-06-20T10:00:00Z").ToUniversalTime()  # 10h atras
        $v = Get-HeartbeatVerdict -LatestClosedAtUtc $dt -NowUtc $now -ThresholdHours 6
        $v.alert | Should Be $true
        $v.reason | Should Be "stale"
        [math]::Round($v.hours_since) | Should Be 10
    }
}
