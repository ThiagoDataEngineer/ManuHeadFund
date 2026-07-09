# capital_context_failsafe.Tests.ps1 — TDD fix cap_exposure 2026-07-09 (Pester 3.4)
# Trava 3 comportamentos:
#  1. Sem fetch real -> source=fallback e NUNCA persiste (nao polui Supabase/journal)
#  2. Cache REAL stale disponivel -> preferido sobre bootstrap (cached_stale)
#  3. Get-ExecutableCapitalUSDT: isolated=futures only; cross=spot+futures

$here = Split-Path $PSScriptRoot -Parent
$libPath = Join-Path $here "agents\lib_capital_context.ps1"

# Dot-source no ESCOPO DO ARQUIVO (regra do projeto: dot-source dentro de funcao
# fica em escopo local e as funcoes somem -- bug classe conhecida 2026-07-02)
. $libPath

function Reset-CapCtxEnv {
    param([string]$TmpDir)
    $global:STATE_STORE_BACKEND = "local"
    Remove-Item Function:\CoinEx-GetSpotCapitalUSDT -ErrorAction SilentlyContinue
    Remove-Item Function:\CoinEx-GetFuturesCapitalUSDT -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-StateRecords -ErrorAction SilentlyContinue
    Remove-Item Function:\Save-StateRecords -ErrorAction SilentlyContinue
    $global:CAPITAL_SPOT = 100.0
    $global:CAPITAL_FUTURES = 100.0
    $global:CAPITAL_SPOT_LAST_REFRESH = $null
    $global:CAPITAL_FUTURES_LAST_REFRESH = $null
}

Describe "capital_context fail-safe (fix cap_exposure 2026-07-09)" {

    It "1a. fetcher devolve bootstrap (sem LAST_REFRESH avancar) -> source=fallback" {
        $tmp = Join-Path $env:TEMP ("capctx_" + [guid]::NewGuid().ToString("N").Substring(0,8))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $ctxPath = Join-Path $tmp "capital_context.json"
        Reset-CapCtxEnv -TmpDir $tmp
        function global:CoinEx-GetSpotCapitalUSDT { return $global:CAPITAL_SPOT }
        function global:CoinEx-GetFuturesCapitalUSDT { return $global:CAPITAL_FUTURES }

        $ctx = Get-CapitalContext -Force -ContextPath $ctxPath
        $ctx.source | Should Be "fallback"
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "1b. fallback NAO persiste no journal" {
        $tmp = Join-Path $env:TEMP ("capctx_" + [guid]::NewGuid().ToString("N").Substring(0,8))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $ctxPath = Join-Path $tmp "capital_context.json"
        Reset-CapCtxEnv -TmpDir $tmp
        function global:CoinEx-GetSpotCapitalUSDT { return $global:CAPITAL_SPOT }
        function global:CoinEx-GetFuturesCapitalUSDT { return $global:CAPITAL_FUTURES }

        Get-CapitalContext -Force -ContextPath $ctxPath | Out-Null
        (Test-Path $ctxPath) | Should Be $false
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "2. cache REAL stale preferido sobre bootstrap (cached_stale)" {
        $tmp = Join-Path $env:TEMP ("capctx_" + [guid]::NewGuid().ToString("N").Substring(0,8))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $ctxPath = Join-Path $tmp "capital_context.json"
        Reset-CapCtxEnv -TmpDir $tmp

        $old = @{
            id=1; spot=2425.5; futures=2741.2; total=5166.7
            snapshot_ts=(Get-Date).ToUniversalTime().AddHours(-3).ToString("o")
            source="fresh"
        } | ConvertTo-Json
        Set-Content -Path $ctxPath -Value $old -Encoding UTF8

        function global:CoinEx-GetSpotCapitalUSDT { return $global:CAPITAL_SPOT }
        function global:CoinEx-GetFuturesCapitalUSDT { return $global:CAPITAL_FUTURES }

        # MaxAge 60min -> cache 3h stale -> fresh falha -> cached_stale
        $ctx = Get-CapitalContext -ContextPath $ctxPath -MaxAgeMinutes 60
        $ctx.source | Should Be "cached_stale"
        $ctx.total | Should Be 5166.7
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "3a. fetch REAL (LAST_REFRESH avanca) -> fresh e persiste" {
        $tmp = Join-Path $env:TEMP ("capctx_" + [guid]::NewGuid().ToString("N").Substring(0,8))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $ctxPath = Join-Path $tmp "capital_context.json"
        Reset-CapCtxEnv -TmpDir $tmp

        function global:CoinEx-GetSpotCapitalUSDT {
            $global:CAPITAL_SPOT = 2425.5
            $global:CAPITAL_SPOT_LAST_REFRESH = Get-Date
            return 2425.5
        }
        function global:CoinEx-GetFuturesCapitalUSDT {
            $global:CAPITAL_FUTURES = 2741.2
            $global:CAPITAL_FUTURES_LAST_REFRESH = Get-Date
            return 2741.2
        }

        $ctx = Get-CapitalContext -Force -ContextPath $ctxPath
        $ctx.source | Should Be "fresh"
        $ctx.total | Should Be 5166.7
        (Test-Path $ctxPath) | Should Be $true
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "3b. Get-ExecutableCapitalUSDT isolated -> futures only" {
        $tmp = Join-Path $env:TEMP ("capctx_" + [guid]::NewGuid().ToString("N").Substring(0,8))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $ctxPath = Join-Path $tmp "capital_context.json"
        Reset-CapCtxEnv -TmpDir $tmp

        $real = @{
            id=1; spot=2000.0; futures=3000.0; total=5000.0
            snapshot_ts=(Get-Date).ToUniversalTime().ToString("o")
            source="fresh"
        } | ConvertTo-Json
        Set-Content -Path $ctxPath -Value $real -Encoding UTF8
        Get-CapitalContext -ContextPath $ctxPath | Out-Null

        $r = Get-ExecutableCapitalUSDT -MarketType FUTURES -MarginMode isolated
        $r.capital | Should Be 3000.0
        $r.wallet_cap | Should Be 3000.0
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "3c. Get-ExecutableCapitalUSDT cross -> spot+futures, wallet=futures" {
        $tmp = Join-Path $env:TEMP ("capctx_" + [guid]::NewGuid().ToString("N").Substring(0,8))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $ctxPath = Join-Path $tmp "capital_context.json"
        Reset-CapCtxEnv -TmpDir $tmp

        $real = @{
            id=1; spot=2000.0; futures=3000.0; total=5000.0
            snapshot_ts=(Get-Date).ToUniversalTime().ToString("o")
            source="fresh"
        } | ConvertTo-Json
        Set-Content -Path $ctxPath -Value $real -Encoding UTF8
        Get-CapitalContext -ContextPath $ctxPath | Out-Null

        $r = Get-ExecutableCapitalUSDT -MarketType FUTURES -MarginMode cross
        $r.capital | Should Be 5000.0
        $r.wallet_cap | Should Be 3000.0
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
