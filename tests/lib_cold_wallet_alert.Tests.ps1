# lib_cold_wallet_alert.Tests.ps1 -- TDD pra hot-wallet ratio alert.
# Pester 3.x.
#
# Pattern: cron diario checa saldo CoinEx ("hot"). Se exceder threshold
# (default 80% do total_assumed), alerta TG: "considere withdraw to cold".

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_cold_wallet_alert.ps1")

$script:tmp = Join-Path $env:TEMP ("cwa_$([guid]::NewGuid())")
New-Item -ItemType Directory -Path $tmp -Force | Out-Null


Describe "Test-HotWalletRatio" {
    It "Hot=$2000, Total=$2500 (declarado) ratio=0.8 = OK (no alert)" {
        $r = Test-HotWalletRatio -HotWalletUsd 2000 -TotalDeclaredUsd 2500
        $r.ratio | Should Be 0.8
        $r.alert | Should Be $false
    }
    It "Hot=$2500, Total=$2500 ratio=1.0 = ALERT (100% exposto)" {
        $r = Test-HotWalletRatio -HotWalletUsd 2500 -TotalDeclaredUsd 2500
        $r.ratio | Should Be 1.0
        $r.alert | Should Be $true
        $r.reason | Should Match "exceeds"
    }
    It "Hot=$3000, Total=$2500 (>100%) = ALERT" {
        $r = Test-HotWalletRatio -HotWalletUsd 3000 -TotalDeclaredUsd 2500
        ($r.ratio -gt 1.0) | Should Be $true
        $r.alert | Should Be $true
    }
    It "Threshold customizado 0.5: hot=$1500 total=$2500 ratio=0.6 = ALERT" {
        $r = Test-HotWalletRatio -HotWalletUsd 1500 -TotalDeclaredUsd 2500 -Threshold 0.5
        $r.alert | Should Be $true
    }
    It "Hot=0 retorna alert=false (sem exposicao)" {
        $r = Test-HotWalletRatio -HotWalletUsd 0 -TotalDeclaredUsd 2500
        $r.alert | Should Be $false
    }
    It "TotalDeclared 0 retorna alert=false (config nao definida; nao bloqueia)" {
        $r = Test-HotWalletRatio -HotWalletUsd 1000 -TotalDeclaredUsd 0
        $r.alert | Should Be $false
        $r.reason | Should Match "no_total_declared"
    }
}


Describe "Get-AlertMessage" {
    It "Formata mensagem TG com numbers + recomendacao" {
        $r = Test-HotWalletRatio -HotWalletUsd 2500 -TotalDeclaredUsd 2500
        $msg = Get-AlertMessage -Check $r
        $msg -match "Hot wallet" | Should Be $true
        $msg -match "100%" | Should Be $true
        $msg -match "withdraw|cold" | Should Be $true
    }
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
