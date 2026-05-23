# lib_cycle_context.Tests.ps1 -- Pester 3.x
# Contrato: Get-CycleContext compoe Pi/200WMA/ATH-DD/NUPL (Partes A+B)
#   -> cycle_phase, risk_score 0-100, recommendation, summary_line
# Stubs: redefine as 4 funcoes de A+B apos dot-source para isolar logica composta.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Host    { param() }
function Write-Warning { param() }

. "$here\..\agents\lib_cycle_mocks.ps1"
. "$here\..\agents\lib_cycle_context.ps1"

# Stubs apos dot-source (script scope sobrepoe os mocks)
$global:STUB_PI    = $null
$global:STUB_WMA   = $null
$global:STUB_ATH   = $null
$global:STUB_NUPL  = $null

function Get-PiCycleSignal {
    param($DailyCloses)
    return $global:STUB_PI
}
function Get-200WMAContext {
    param($DailyCloses, $CurrentPrice)
    return $global:STUB_WMA
}
function Get-ATHDrawdown {
    param($DailyCloses, $Dates, $CurrentPrice)
    return $global:STUB_ATH
}
function Get-NUPLProxy {
    param($FearGreed, $DistanceFromSMA200, $FundingRate8h)
    return $global:STUB_NUPL
}

# Helpers
function Set-Pi   { param($S="NEUTRAL")             $global:STUB_PI   = [PSCustomObject]@{ signal=$S; ma_111=0; ma_350x2=0 } }
function Set-Wma  { param($Z="ABOVE",$D=10)         $global:STUB_WMA  = [PSCustomObject]@{ zone=$Z; distance_pct=$D; wma=0 } }
function Set-Ath  { param($Z="HEALTHY",$DD=-10)     $global:STUB_ATH  = [PSCustomObject]@{ zone=$Z; drawdown_pct=$DD; ath=0; ath_date=(Get-Date) } }
function Set-Nupl { param($S=0.5,$Z="OPTIMISM")     $global:STUB_NUPL = [PSCustomObject]@{ score=$S; zone=$Z; raw=0 } }

# Defaults: bull mid-cycle saudavel
$dailyCloses = @(100,101,102) * 200   # ~600 dias mock

Describe "Get-CycleContext - composicao Partes A+B" {

    It "Pi TRIGGERED + NUPL EUFORIA -> EVITAR_LONGS (risk > 80)" {
        Set-Pi "TRIGGERED"; Set-Wma "ABOVE" 40; Set-Ath "HEALTHY" -5; Set-Nupl 0.95 "EUFORIA"
        $out = Get-CycleContext -Market "BTCUSDT" -DailyCloses $dailyCloses -Dates @() `
            -CurrentPrice 100 -FearGreed 90 -DistanceFromSMA200 40 -FundingRate8h 0.0008
        ($out.recommendation) | Should Be "EVITAR_LONGS"
        ($out.risk_score -gt 80) | Should Be $true
    }

    It "Capitulacao total -> AGRESSIVO_LONG (risk < 20)" {
        Set-Pi "NEUTRAL"; Set-Wma "NEAR" -5; Set-Ath "CAPITULATION" -82; Set-Nupl 0.10 "CAPITULATION"
        $out = Get-CycleContext -Market "BTCUSDT" -DailyCloses $dailyCloses -Dates @() `
            -CurrentPrice 100 -FearGreed 8 -DistanceFromSMA200 -45 -FundingRate8h -0.0005
        ($out.recommendation) | Should Be "AGRESSIVO_LONG"
        ($out.risk_score -lt 20) | Should Be $true
    }

    It "Correcao saudavel em bull -> LONG_CAUTELOSO" {
        Set-Pi "BEFORE"; Set-Wma "ABOVE" 15; Set-Ath "CORRECTION" -25; Set-Nupl 0.45 "OPTIMISM"
        $out = Get-CycleContext -Market "BTCUSDT" -DailyCloses $dailyCloses -Dates @() `
            -CurrentPrice 100 -FearGreed 45 -DistanceFromSMA200 15 -FundingRate8h 0.0001
        ($out.recommendation) | Should Be "LONG_CAUTELOSO"
    }

    It "cycle_phase consistente: Pi TRIGGERED + NUPL > 0.70 -> DISTRIBUICAO" {
        Set-Pi "TRIGGERED"; Set-Wma "ABOVE" 50; Set-Ath "HEALTHY" 0; Set-Nupl 0.80 "EUFORIA"
        $out = Get-CycleContext -Market "BTCUSDT" -DailyCloses $dailyCloses -Dates @() `
            -CurrentPrice 100 -FearGreed 88 -DistanceFromSMA200 50 -FundingRate8h 0.0009
        ($out.cycle_phase) | Should Be "DISTRIBUICAO"
    }

    It "risk_score crescente conforme indicadores ficam bearish" {
        Set-Pi "NEUTRAL"; Set-Wma "NEAR" 0; Set-Ath "CAPITULATION" -75; Set-Nupl 0.15 "CAPITULATION"
        $r1 = (Get-CycleContext -Market "BTCUSDT" -DailyCloses $dailyCloses -Dates @() `
            -CurrentPrice 100 -FearGreed 10 -DistanceFromSMA200 -30 -FundingRate8h 0).risk_score

        Set-Pi "BEFORE"; Set-Wma "ABOVE" 10; Set-Ath "HEALTHY" -10; Set-Nupl 0.50 "OPTIMISM"
        $r2 = (Get-CycleContext -Market "BTCUSDT" -DailyCloses $dailyCloses -Dates @() `
            -CurrentPrice 100 -FearGreed 50 -DistanceFromSMA200 10 -FundingRate8h 0.0001).risk_score

        Set-Pi "TRIGGERED"; Set-Wma "ABOVE" 50; Set-Ath "HEALTHY" 0; Set-Nupl 0.90 "EUFORIA"
        $r3 = (Get-CycleContext -Market "BTCUSDT" -DailyCloses $dailyCloses -Dates @() `
            -CurrentPrice 100 -FearGreed 90 -DistanceFromSMA200 50 -FundingRate8h 0.001).risk_score

        ($r1 -lt $r2) | Should Be $true
        ($r2 -lt $r3) | Should Be $true
    }

    It "Insufficient data nao quebra (fallback NEUTRO)" {
        $global:STUB_PI = $null; $global:STUB_WMA = $null; $global:STUB_ATH = $null; $global:STUB_NUPL = $null
        $out = Get-CycleContext -Market "BTCUSDT" -DailyCloses @() -Dates @() `
            -CurrentPrice 0 -FearGreed 50 -DistanceFromSMA200 0 -FundingRate8h 0
        ($out.recommendation) | Should Be "NEUTRO"
        ($out.cycle_phase -ne $null) | Should Be $true
    }

    It "NUPL EUFORIA + Pi BEFORE -> risk > 70" {
        Set-Pi "BEFORE"; Set-Wma "ABOVE" 30; Set-Ath "HEALTHY" -3; Set-Nupl 0.95 "EUFORIA"
        $out = Get-CycleContext -Market "BTCUSDT" -DailyCloses $dailyCloses -Dates @() `
            -CurrentPrice 100 -FearGreed 88 -DistanceFromSMA200 30 -FundingRate8h 0.0007
        ($out.risk_score -gt 70) | Should Be $true
    }

    It "summary_line nunca vazia e < 200 chars" {
        Set-Pi "BEFORE"; Set-Wma "ABOVE" 15; Set-Ath "HEALTHY" -8; Set-Nupl 0.55 "OPTIMISM"
        $out = Get-CycleContext -Market "BTCUSDT" -DailyCloses $dailyCloses -Dates @() `
            -CurrentPrice 100 -FearGreed 60 -DistanceFromSMA200 15 -FundingRate8h 0.0002
        ($out.summary_line.Length -gt 0)   | Should Be $true
        ($out.summary_line.Length -lt 200) | Should Be $true
    }
}
