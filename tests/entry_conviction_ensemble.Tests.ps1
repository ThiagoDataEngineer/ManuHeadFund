# entry_conviction_ensemble.Tests.ps1 -- TDD ensemble de conviccao de entrada
# Eixos: BTC relative strength + Multi-TF gradiente + ensemble + observacao
# Pester 3.4 (Should Be / -ge via Should Be $true). ASCII-only (PS 5.1 safe).

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\lib_btc_relative_strength.ps1"
. ".\agents\lib_multiframe_analysis.ps1"
. ".\agents\lib_entry_conviction_ensemble.ps1"

Describe "Axis 2 - BTC Relative Strength" {

    Context "Get-BtcRelativeStrength (puro)" {

        It "alt +10pct vs btc +1pct, beta 1 => rs 9" {
            $alt = @(100.0, 105.0, 110.0)
            $btc = @(100.0, 100.5, 101.0)
            $r = Get-BtcRelativeStrength -AltCloses $alt -BtcCloses $btc -Beta 1.0
            $r.rs | Should Be 9
        }

        It "detecta decoupling (alt sobe, btc parado)" {
            $alt = @(100.0, 110.0)
            $btc = @(100.0, 101.0)
            $r = Get-BtcRelativeStrength -AltCloses $alt -BtcCloses $btc -Beta 1.0
            $r.decoupled | Should Be $true
        }

        It "NAO decoupling se alt sobe junto com btc (beta-explicado)" {
            $alt = @(100.0, 110.0)
            $btc = @(100.0, 110.0)
            $r = Get-BtcRelativeStrength -AltCloses $alt -BtcCloses $btc -Beta 1.0
            $r.rs | Should Be 0
            $r.decoupled | Should Be $false
        }

        It "aplica beta (alt high-beta nao ganha credito falso)" {
            # alt +20pct mas beta 2 e btc +10pct => rs = 20 - 2*10 = 0
            $alt = @(100.0, 120.0)
            $btc = @(100.0, 110.0)
            $r = Get-BtcRelativeStrength -AltCloses $alt -BtcCloses $btc -Beta 2.0
            $r.rs | Should Be 0
        }

        It "retorna null com series insuficientes" {
            $r = Get-BtcRelativeStrength -AltCloses @(100.0) -BtcCloses @(100.0) -Beta 1.0
            $r | Should BeNullOrEmpty
        }
    }

    Context "Get-RsConvictionScore (0-100, direcao-aware)" {

        It "LONG: rs forte positivo + btc parado = score alto" {
            $s = Get-RsConvictionScore -Rs 9 -BtcReturn 1 -Direction "LONG"
            ($s -ge 80) | Should Be $true
        }

        It "LONG: rs zero = neutro 50" {
            $s = Get-RsConvictionScore -Rs 0 -BtcReturn 0 -Direction "LONG"
            $s | Should Be 50
        }

        It "SHORT: rs negativo (alt mais fraca que btc) = score alto" {
            $s = Get-RsConvictionScore -Rs -9 -BtcReturn 1 -Direction "SHORT"
            ($s -ge 80) | Should Be $true
        }

        It "LONG: rs muito negativo = score baixo" {
            $s = Get-RsConvictionScore -Rs -20 -BtcReturn 0 -Direction "LONG"
            ($s -le 10) | Should Be $true
        }

        It "clamp 0..100 (rs extremo nao estoura)" {
            $s = Get-RsConvictionScore -Rs 200 -BtcReturn 0 -Direction "LONG"
            ($s -le 100) | Should Be $true
        }
    }
}

Describe "Axis 4 - Multi-TF Gradient" {

    Context "Get-MultiTimeframeConviction (0-100, nao binario)" {

        It "LONG: 3/3 STRONG_UP = 100" {
            $s = Get-MultiTimeframeConviction -Trend1D "STRONG_UP" -Trend4H "STRONG_UP" -Trend1H "STRONG_UP" -Direction "LONG"
            $s | Should Be 100
        }

        It "SHORT: 3/3 STRONG_DOWN = 100" {
            $s = Get-MultiTimeframeConviction -Trend1D "STRONG_DOWN" -Trend4H "STRONG_DOWN" -Trend1H "STRONG_DOWN" -Direction "SHORT"
            $s | Should Be 100
        }

        It "LONG: 1D up + 4H up + 1H down = parcial (entre 60 e 80)" {
            $s = Get-MultiTimeframeConviction -Trend1D "UP" -Trend4H "UP" -Trend1H "DOWN" -Direction "LONG"
            (($s -ge 50) -and ($s -le 80)) | Should Be $true
        }

        It "LONG: tudo contra (DOWN) = baixo" {
            $s = Get-MultiTimeframeConviction -Trend1D "STRONG_DOWN" -Trend4H "DOWN" -Trend1H "DOWN" -Direction "LONG"
            ($s -le 10) | Should Be $true
        }

        It "1D pesa mais que 1H (1D up sozinho > 1H up sozinho)" {
            $a = Get-MultiTimeframeConviction -Trend1D "STRONG_UP" -Trend4H "NEUTRAL" -Trend1H "NEUTRAL" -Direction "LONG"
            $b = Get-MultiTimeframeConviction -Trend1D "NEUTRAL" -Trend4H "NEUTRAL" -Trend1H "STRONG_UP" -Direction "LONG"
            ($a -gt $b) | Should Be $true
        }
    }
}

Describe "Ensemble - Get-EntryConviction" {

    Context "Combinacao ponderada de eixos" {

        It "combina 2 eixos presentes (ignora ausentes)" {
            $axes = @{ btc_rs = 87; multitf = 100 }
            $r = Get-EntryConviction -Axes $axes -Direction "LONG"
            ($r.conviction -ge 85) | Should Be $true
            $r.axes_used.Count | Should Be 2
        }

        It "1 eixo so = score do proprio eixo" {
            $axes = @{ structure = 80 }
            $r = Get-EntryConviction -Axes $axes -Direction "LONG"
            $r.conviction | Should Be 80
        }

        It "ready=true quando >= threshold" {
            $axes = @{ btc_rs = 90; multitf = 90 }
            $r = Get-EntryConviction -Axes $axes -Direction "LONG" -Threshold 55
            $r.ready | Should Be $true
        }

        It "ready=false quando < threshold" {
            $axes = @{ btc_rs = 30; multitf = 30 }
            $r = Get-EntryConviction -Axes $axes -Direction "LONG" -Threshold 55
            $r.ready | Should Be $false
        }

        It "todos 5 eixos juntos (caso completo)" {
            $axes = @{ structure = 70; btc_rs = 85; volume = 60; multitf = 90; historical = 50 }
            $r = Get-EntryConviction -Axes $axes -Direction "LONG"
            (($r.conviction -ge 0) -and ($r.conviction -le 100)) | Should Be $true
            $r.axes_used.Count | Should Be 5
        }

        It "pesos customizados respeitados" {
            $axes = @{ btc_rs = 100; multitf = 0 }
            # peso btc_rs dominante => conviccao puxa pra cima
            $w = @{ btc_rs = 0.9; multitf = 0.1 }
            $r = Get-EntryConviction -Axes $axes -Direction "LONG" -Weights $w
            ($r.conviction -ge 85) | Should Be $true
        }

        It "retorna contribuicao por eixo" {
            $axes = @{ btc_rs = 80; multitf = 80 }
            $r = Get-EntryConviction -Axes $axes -Direction "LONG"
            $r.contributions | Should Not BeNullOrEmpty
        }
    }

    Context "Get-StructureScore (trendline vira 1 voto, nao veto)" {

        It "2 toques + span 6 + rejeicao = 75" {
            $s = Get-StructureScore -Touches 2 -CandleSpan 6 -Rejection $true
            $s | Should Be 75
        }

        It "1 toque fraco = baixo (nao zero, eh 1 voto)" {
            $s = Get-StructureScore -Touches 1 -CandleSpan 3 -Rejection $false
            (($s -gt 0) -and ($s -le 30)) | Should Be $true
        }

        It "0 toques = piso baixo" {
            $s = Get-StructureScore -Touches 0 -CandleSpan 0 -Rejection $false
            ($s -le 15) | Should Be $true
        }
    }
}

Describe "Observacao (feed do calibrador)" {

    BeforeAll {
        $script:obsPath = Join-Path $env:TEMP "conviction_obs_test_$([guid]::NewGuid().ToString('N').Substring(0,8)).jsonl"
    }

    AfterAll {
        if (Test-Path $script:obsPath) { Remove-Item $script:obsPath -Force }
    }

    It "Write-ConvictionObservation grava JSONL parseavel" {
        $axes = @{ btc_rs = 85; multitf = 90 }
        Write-ConvictionObservation -Market "SYNDUSDT" -Direction "LONG" -Conviction 88.5 -Axes $axes -Path $script:obsPath
        Test-Path $script:obsPath | Should Be $true
        $line = Get-Content $script:obsPath | Select-Object -First 1
        $obj = $line | ConvertFrom-Json
        $obj.market | Should Be "SYNDUSDT"
        $obj.conviction | Should Be 88.5
    }

    It "Get-ConvictionStats agrega observacoes" {
        Write-ConvictionObservation -Market "AGTUSDT" -Direction "LONG" -Conviction 70 -Axes @{ btc_rs = 70 } -Path $script:obsPath
        $stats = Get-ConvictionStats -Path $script:obsPath
        ($stats.count -ge 2) | Should Be $true
    }
}
