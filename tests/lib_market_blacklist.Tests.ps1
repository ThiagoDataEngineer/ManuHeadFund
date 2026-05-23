$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_market_blacklist.ps1")

function _TmpPath {
    return (Join-Path $env:TEMP ("bl_" + $PID + "_" + (Get-Random) + ".jsonl"))
}

Describe "Add + Test market blacklist" {
    It "Blacklisted market: Test retorna true" {
        $f = _TmpPath
        try {
            Add-MarketBlacklist -Market "BTCUSDT" -TtlHours 24 -Reason "test" -BlacklistPath $f
            Test-MarketBlacklisted -Market "BTCUSDT" -BlacklistPath $f | Should Be $true
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Market nao blacklisted: false" {
        $f = _TmpPath
        try {
            Add-MarketBlacklist -Market "BTCUSDT" -TtlHours 24 -Reason "x" -BlacklistPath $f
            Test-MarketBlacklisted -Market "ETHUSDT" -BlacklistPath $f | Should Be $false
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Arquivo inexistente: Test retorna false (fail-soft)" {
        Test-MarketBlacklisted -Market "BTCUSDT" -BlacklistPath "C:\__none__\x.jsonl" | Should Be $false
    }

    It "Entry expirado: Test retorna false (lazy expire)" {
        $f = _TmpPath
        try {
            # Add com TTL passado (now=2026-01-01, entry expira 2025-12-31)
            $past = (Get-Date).ToUniversalTime().AddDays(-2)
            $entry = [ordered]@{
                market = "OLDUSDT"
                added_at = $past.ToString("o")
                expires_at = $past.AddHours(1).ToString("o")  # expirou 1h depois do added (47h atras)
                reason = "old"
            }
            New-Item -Path $f -ItemType File -Force | Out-Null
            Add-Content -Path $f -Value ($entry | ConvertTo-Json -Compress) -Encoding UTF8
            Test-MarketBlacklisted -Market "OLDUSDT" -BlacklistPath $f | Should Be $false
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Multiple entries mesmo market: usa o ativo mais recente" {
        $f = _TmpPath
        try {
            # Old entry (expired) + new entry (active)
            $past = (Get-Date).ToUniversalTime().AddDays(-5)
            $oldEntry = [ordered]@{
                market = "BTCUSDT"
                added_at = $past.ToString("o")
                expires_at = $past.AddHours(1).ToString("o")
                reason = "old"
            }
            Add-Content -Path $f -Value ($oldEntry | ConvertTo-Json -Compress) -Encoding UTF8
            Add-MarketBlacklist -Market "BTCUSDT" -TtlHours 24 -Reason "new" -BlacklistPath $f
            Test-MarketBlacklisted -Market "BTCUSDT" -BlacklistPath $f | Should Be $true
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Get-BlacklistedMarkets" {
    It "Lista vazia se arquivo inexistente" {
        @(Get-BlacklistedMarkets -BlacklistPath "C:\__nope__\x.jsonl").Count | Should Be 0
    }

    It "Lista markets blacklisted (deduplica por market)" {
        $f = _TmpPath
        try {
            Add-MarketBlacklist -Market "BTCUSDT" -TtlHours 24 -Reason "x" -BlacklistPath $f
            Add-MarketBlacklist -Market "ETHUSDT" -TtlHours 48 -Reason "y" -BlacklistPath $f
            Add-MarketBlacklist -Market "BTCUSDT" -TtlHours 36 -Reason "renewed" -BlacklistPath $f
            $list = Get-BlacklistedMarkets -BlacklistPath $f
            $list.Count | Should Be 2
            ($list | ForEach-Object { $_.market } | Sort-Object) -join "," | Should Be "BTCUSDT,ETHUSDT"
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Property: NowUtc override permite testing temporal" {
    It "Future NowUtc faz entries valid expirarem" {
        $f = _TmpPath
        try {
            Add-MarketBlacklist -Market "X" -TtlHours 24 -Reason "test" -BlacklistPath $f
            $now = (Get-Date).ToUniversalTime()
            Test-MarketBlacklisted -Market "X" -BlacklistPath $f -NowUtc $now | Should Be $true
            # 25h no futuro: entry expirou
            Test-MarketBlacklisted -Market "X" -BlacklistPath $f -NowUtc $now.AddHours(25) | Should Be $false
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}
