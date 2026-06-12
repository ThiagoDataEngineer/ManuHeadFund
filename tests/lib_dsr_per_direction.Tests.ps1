$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_dsr_global.ps1")

function _TmpJsonl { return (Join-Path $env:TEMP ("dsr_" + $PID + "_" + (Get-Random) + ".jsonl")) }

Describe "Add-DsrTrial E.1 direction param" {
    It "Default Direction=LONG (backward compat)" {
        $f = _TmpJsonl
        try {
            Add-DsrTrial -Path $f -GateName "beta" -Market "BTCUSDT"
            $line = (Get-Content $f -Encoding UTF8)
            $obj = $line | ConvertFrom-Json
            $obj.direction | Should Be "LONG"
            $obj.market | Should Be "BTCUSDT"
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Direction=SHORT explicito" {
        $f = _TmpJsonl
        try {
            Add-DsrTrial -Path $f -GateName "beta" -Market "ETHUSDT" -Direction "SHORT"
            $line = (Get-Content $f -Encoding UTF8)
            $obj = $line | ConvertFrom-Json
            $obj.direction | Should Be "SHORT"
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Get-DsrTrialsByDirection filter" {
    It "Filter SHORT only retorna apenas SHORT entries" {
        $f = _TmpJsonl
        try {
            Add-DsrTrial -Path $f -GateName "beta" -Market "BTCUSDT" -Direction "LONG"
            Add-DsrTrial -Path $f -GateName "beta" -Market "ETHUSDT" -Direction "SHORT"
            Add-DsrTrial -Path $f -GateName "beta" -Market "SOLUSDT" -Direction "SHORT"
            $shorts = Get-DsrTrialsByDirection -Path $f -Direction "SHORT"
            $shorts.Count | Should Be 2
            foreach ($s in $shorts) { $s.direction | Should Be "SHORT" }
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Filter LONG only retorna apenas LONG (default) entries" {
        $f = _TmpJsonl
        try {
            Add-DsrTrial -Path $f -GateName "beta" -Market "BTCUSDT" -Direction "LONG"
            Add-DsrTrial -Path $f -GateName "beta" -Market "ETHUSDT" -Direction "SHORT"
            Add-DsrTrial -Path $f -GateName "beta" -Market "INJUSDT"  # default LONG
            $longs = Get-DsrTrialsByDirection -Path $f -Direction "LONG"
            $longs.Count | Should Be 2
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Filter ALL retorna tudo" {
        $f = _TmpJsonl
        try {
            Add-DsrTrial -Path $f -GateName "beta" -Market "BTCUSDT"
            Add-DsrTrial -Path $f -GateName "beta" -Market "ETHUSDT" -Direction "SHORT"
            $all = Get-DsrTrialsByDirection -Path $f -Direction "ALL"
            $all.Count | Should Be 2
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Arquivo ausente: empty array" {
        @(Get-DsrTrialsByDirection -Path "C:\__nope__\x.jsonl" -Direction "SHORT").Count | Should Be 0
    }

    It "Entry sem direction field: trata como LONG (backward compat)" {
        $f = _TmpJsonl
        try {
            # Append manualmente JSON sem direction (legacy format)
            $legacy = '{"ts":"2026-05-01T00:00:00Z","gate":"beta","market":"OLD_LONG"}'
            $legacy | Out-File -FilePath $f -Encoding UTF8
            $longs = Get-DsrTrialsByDirection -Path $f -Direction "LONG"
            $longs.Count | Should Be 1
            $longs[0].market | Should Be "OLD_LONG"
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Property: backward compat retaining LONG default" {
    It "Old caller sem -Direction: ainda funciona" {
        $f = _TmpJsonl
        try {
            $r = Add-DsrTrial -Path $f -GateName "beta" -Market "BTCUSDT"
            $r.success | Should Be $true
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}
