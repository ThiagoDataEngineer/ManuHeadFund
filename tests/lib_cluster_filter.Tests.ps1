$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_cluster_filter.ps1")

function _NewTmpJsonl {
    $f = Join-Path $env:TEMP ("clusterf_" + $PID + "_" + (Get-Random) + ".jsonl")
    return $f
}

function _WriteEntry {
    param([string]$Path, [string]$TsUtc, [string]$Market = "BTCUSDT")
    $obj = [ordered]@{ ts_utc = $TsUtc; market = $Market }
    Add-Content -Path $Path -Value ($obj | ConvertTo-Json -Compress) -Encoding UTF8
}

Describe "Test-ClusterCapExceeded" {

    It "Fail-open: arquivo inexistente nao exceeded" {
        $r = Test-ClusterCapExceeded -AlertsPath "C:\__nonexistent__\foo.jsonl"
        $r.exceeded   | Should Be $false
        $r.day_count  | Should Be 0
        $r.week_count | Should Be 0
    }

    It "Vazio: arquivo sem linhas nao exceeded" {
        $f = _NewTmpJsonl
        try {
            New-Item -ItemType File -Path $f -Force | Out-Null
            $r = Test-ClusterCapExceeded -AlertsPath $f
            $r.exceeded | Should Be $false
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Day cap exceeded: 1 alert nas ultimas 24h" {
        $f = _NewTmpJsonl
        try {
            $now = Get-Date -Date "2026-05-22T12:00:00Z"
            _WriteEntry -Path $f -TsUtc "2026-05-22T08:00:00Z" -Market "BNBUSDT"
            $r = Test-ClusterCapExceeded -AlertsPath $f -NowUtc $now -MaxPerDay 1 -MaxPerWeek 3
            $r.day_count    | Should Be 1
            $r.day_exceeded | Should Be $true
            $r.exceeded     | Should Be $true
            $r.reason | Should Match "day_cap"
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Entry FORA do window 24h nao conta como day mas conta semana" {
        $f = _NewTmpJsonl
        try {
            $now = Get-Date -Date "2026-05-22T12:00:00Z"
            _WriteEntry -Path $f -TsUtc "2026-05-20T08:00:00Z" -Market "INJUSDT"  # ha 2 dias
            $r = Test-ClusterCapExceeded -AlertsPath $f -NowUtc $now -MaxPerDay 1 -MaxPerWeek 3
            $r.day_count    | Should Be 0
            $r.day_exceeded | Should Be $false
            $r.week_count   | Should Be 1
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Week cap exceeded: 3 alerts no rolling 7d" {
        $f = _NewTmpJsonl
        try {
            $now = Get-Date -Date "2026-05-22T12:00:00Z"
            _WriteEntry -Path $f -TsUtc "2026-05-17T08:00:00Z" -Market "BTCUSDT"
            _WriteEntry -Path $f -TsUtc "2026-05-19T08:00:00Z" -Market "INJUSDT"
            _WriteEntry -Path $f -TsUtc "2026-05-20T08:00:00Z" -Market "RENDERUSDT"
            $r = Test-ClusterCapExceeded -AlertsPath $f -NowUtc $now -MaxPerDay 1 -MaxPerWeek 3
            $r.week_count    | Should Be 3
            $r.week_exceeded | Should Be $true
            $r.exceeded      | Should Be $true
            $r.reason | Should Match "week_cap"
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Entry FORA do window 7d nao conta" {
        $f = _NewTmpJsonl
        try {
            $now = Get-Date -Date "2026-05-22T12:00:00Z"
            _WriteEntry -Path $f -TsUtc "2026-05-10T08:00:00Z" -Market "OLD"  # ha 12 dias
            _WriteEntry -Path $f -TsUtc "2026-05-22T06:00:00Z" -Market "RECENT"  # 6h atras (dentro day)
            $r = Test-ClusterCapExceeded -AlertsPath $f -NowUtc $now -MaxPerDay 1 -MaxPerWeek 3
            $r.week_count | Should Be 1
            $r.day_count  | Should Be 1
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Linha invalida nao trava parse (skip silent)" {
        $f = _NewTmpJsonl
        try {
            $now = Get-Date -Date "2026-05-22T12:00:00Z"
            Add-Content -Path $f -Value "isso nao eh json" -Encoding UTF8
            _WriteEntry -Path $f -TsUtc "2026-05-22T08:00:00Z" -Market "BTC"
            $r = Test-ClusterCapExceeded -AlertsPath $f -NowUtc $now -MaxPerDay 1 -MaxPerWeek 3
            $r.day_count | Should Be 1  # so a valid contou
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Determinismo: mesma entrada -> mesma saida" {
        $f = _NewTmpJsonl
        try {
            $now = Get-Date -Date "2026-05-22T12:00:00Z"
            _WriteEntry -Path $f -TsUtc "2026-05-22T08:00:00Z" -Market "BTC"
            _WriteEntry -Path $f -TsUtc "2026-05-21T08:00:00Z" -Market "INJ"
            $r1 = Test-ClusterCapExceeded -AlertsPath $f -NowUtc $now
            $r2 = Test-ClusterCapExceeded -AlertsPath $f -NowUtc $now
            $r1.day_count  | Should Be $r2.day_count
            $r1.week_count | Should Be $r2.week_count
            $r1.exceeded   | Should Be $r2.exceeded
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}