$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_wss_forward_tracker.ps1")

function _TmpPath { return (Join-Path $env:TEMP ("wssfwd_" + $PID + "_" + (Get-Random) + ".jsonl")) }

Describe "Add-WssSignal" {
    It "Adiciona signal pending" {
        $f = _TmpPath
        try {
            Add-WssSignal -Market "BTCUSDT" -WssScore 75 -EntryPrice 95000 -PathOverride $f
            (Test-Path $f) | Should Be $true
            $lines = @(Get-Content $f -Encoding UTF8)
            $lines.Count | Should Be 1
            ($lines[0] | ConvertFrom-Json).status | Should Be "pending"
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Idempotente: dup mesmo market+date NAO duplica" {
        $f = _TmpPath
        try {
            $ts = "2026-05-22T12:00:00Z"
            Add-WssSignal -Market "BTCUSDT" -TriggeredAt $ts -PathOverride $f
            Add-WssSignal -Market "BTCUSDT" -TriggeredAt $ts -PathOverride $f
            (@(Get-Content $f -Encoding UTF8)).Count | Should Be 1
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Resolve-WssSignal" {
    It "Append resolved entry" {
        $f = _TmpPath
        try {
            Add-WssSignal -Market "ETHUSDT" -TriggeredAt "2026-05-20T10:00:00Z" -PathOverride $f
            Resolve-WssSignal -Market "ETHUSDT" -TriggeredAtDate "2026-05-20" -ExitPrice 3200 -RealizedPct 3.5 -Hit $true -PathOverride $f
            $lines = @(Get-Content $f -Encoding UTF8)
            $lines.Count | Should Be 2
            ($lines[1] | ConvertFrom-Json).status | Should Be "resolved"
            ($lines[1] | ConvertFrom-Json).hit | Should Be $true
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Get-PendingWssSignals" {
    It "Vazio se nada" {
        $f = _TmpPath
        @(Get-PendingWssSignals -PathOverride $f).Count | Should Be 0
    }

    It "Pending nao retorna se ja resolved" {
        $f = _TmpPath
        try {
            Add-WssSignal -Market "BTCUSDT" -TriggeredAt "2026-05-20T10:00:00Z" -PathOverride $f
            Resolve-WssSignal -Market "BTCUSDT" -TriggeredAtDate "2026-05-20" -RealizedPct 2 -Hit $false -PathOverride $f
            @(Get-PendingWssSignals -PathOverride $f).Count | Should Be 0
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Mix pending + resolved: lista so pending" {
        $f = _TmpPath
        try {
            Add-WssSignal -Market "P1" -TriggeredAt "2026-05-20T10:00:00Z" -PathOverride $f
            Add-WssSignal -Market "P2" -TriggeredAt "2026-05-21T10:00:00Z" -PathOverride $f
            Add-WssSignal -Market "R1" -TriggeredAt "2026-05-19T10:00:00Z" -PathOverride $f
            Resolve-WssSignal -Market "R1" -TriggeredAtDate "2026-05-19" -RealizedPct 5 -Hit $true -PathOverride $f
            $pending = Get-PendingWssSignals -PathOverride $f
            $pending.Count | Should Be 2
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Get-WssForwardStats" {
    It "Empty: zeros" {
        $f = _TmpPath
        $s = Get-WssForwardStats -PathOverride $f
        $s.n_resolved | Should Be 0
        $s.hit_count | Should Be 0
    }

    It "3 resolved 2 hits: stats corretos" {
        $f = _TmpPath
        try {
            Add-WssSignal -Market "A" -TriggeredAt "2026-05-20T10:00:00Z" -PathOverride $f
            Add-WssSignal -Market "B" -TriggeredAt "2026-05-20T10:00:00Z" -PathOverride $f
            Add-WssSignal -Market "C" -TriggeredAt "2026-05-21T10:00:00Z" -PathOverride $f
            Resolve-WssSignal -Market "A" -TriggeredAtDate "2026-05-20" -RealizedPct 3 -Hit $true -PathOverride $f
            Resolve-WssSignal -Market "B" -TriggeredAt "2026-05-20" -RealizedPct -1 -Hit $false -PathOverride $f
            Resolve-WssSignal -Market "C" -TriggeredAt "2026-05-21" -RealizedPct 4.5 -Hit $true -PathOverride $f
            $s = Get-WssForwardStats -PathOverride $f
            $s.n_resolved | Should Be 3
            $s.hit_count | Should Be 2
            $s.hit_rate_pct | Should Be 66.7
            ($s.mean_realized_pct -ge 2.1 -and $s.mean_realized_pct -le 2.2) | Should Be $true  # (3-1+4.5)/3=2.17
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}
