# tg_live_setup_risk.Tests.ps1 -- TDD para painel de risco Mode 2 LIVE
# Pester 3.x, sem acentos.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"

# stubs
$global:TELEGRAM_API_BASE = "https://api.telegram.org"
function Invoke-RestMethod {
    param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
    return [PSCustomObject]@{ ok=$true; result=[PSCustomObject]@{message_id=1} }
}
. (Join-Path $agentsDir "lib_telegram.ps1")

Describe "Format-TgLiveSetupRisk" {

    It "contem market + entry" {
        $msg = Format-TgLiveSetupRisk -Market "ZECUSDT" -Direction "LONG" -Tier "A" `
            -Entry 50.0 -Stop 47.5 -Target 52.5 -SizeUsd 50 `
            -Sharpe 5.31 -DSR 1.0 -PSR 1.0 -PBO 0.0 `
            -WinRatePct 56.6 -MeanR 0.58 -WfPositive 3 -WfTotal 5 `
            -SampleN 249 -SampleYears "2.7y CoinEx" `
            -MentorMsg "razao" -MentorConf 85
        $msg | Should Match "ZECUSDT"
        $msg | Should Match "Entry"
        $msg | Should Match "Stop"
    }

    It "Tier A mostra LIVE check" {
        $msg = Format-TgLiveSetupRisk -Market "X" -Direction "LONG" -Tier "A" `
            -Entry 100 -Stop 95 -Target 110 -SizeUsd 50 `
            -Sharpe 5 -DSR 1 -PSR 1 -PBO 0 -WinRatePct 50 -MeanR 0.5 `
            -WfPositive 5 -WfTotal 5 -SampleN 100 -SampleYears "1y"
        $msg | Should Match "TIER A LIVE"
    }

    It "Tier B mostra alerta edge marginal" {
        $msg = Format-TgLiveSetupRisk -Market "BCH" -Direction "LONG" -Tier "B" `
            -Entry 400 -Stop 390 -Target 420 -SizeUsd 50 `
            -Sharpe 2.67 -DSR 0.77 -PSR 0.97 -PBO 0.0 `
            -WinRatePct 52 -MeanR 0.24 -SampleN 138 -SampleYears "2.7y"
        $msg | Should Match "TIER B PAPER"
        $msg | Should Match "marginal"
    }

    It "calcula worst/best/expected em USD" {
        # Entry 100, Stop 95 (-5%), Target 110 (+10%), SizeUsd 50, MeanR 0.5
        $msg = Format-TgLiveSetupRisk -Market "X" -Direction "LONG" -Tier "A" `
            -Entry 100 -Stop 95 -Target 110 -SizeUsd 50 `
            -Sharpe 5 -DSR 1 -PSR 1 -PBO 0 -WinRatePct 50 -MeanR 0.5 `
            -WfPositive 3 -WfTotal 5 -SampleN 100 -SampleYears "2y"
        # Verifica calculo via contains (sem regex)
        ($msg.Contains("-`$50")) | Should Be $true        # worst
        ($msg.Contains("+`$100")) | Should Be $true       # best
        ($msg.Contains("+`$25"))  | Should Be $true       # expected
    }

    It "DRY mode no instructions executar" {
        $msg = Format-TgLiveSetupRisk -Market "X" -Direction "LONG" -Tier "A" `
            -Entry 100 -Stop 95 -Target 110 -SizeUsd 50 `
            -Sharpe 5 -DSR 1 -PSR 1 -PBO 0 -WinRatePct 50 -MeanR 0.5 `
            -SampleN 100 -SampleYears "2y" -DryRun
        $msg | Should Match "DRY"
        $msg | Should Match "sem ordem real"
    }

    It "icons indicam gates passados" {
        $msg = Format-TgLiveSetupRisk -Market "X" -Direction "LONG" -Tier "A" `
            -Entry 100 -Stop 95 -Target 110 -SizeUsd 50 `
            -Sharpe 5 -DSR 1.0 -PSR 1.0 -PBO 0.1 -WinRatePct 50 -MeanR 0.5 `
            -WfPositive 5 -WfTotal 5 -SampleN 100 -SampleYears "2y"
        # DSR=1.0, PSR=1.0, PBO=0.1, WF=5/5 -> tudo check
        $msg | Should Match "DSR"
        $msg | Should Match "PBO"
        $msg | Should Match "WF"
    }
}
