# short_mastery.Tests.ps1 -- TDD da maestria SHORT
#   Get-OverextensionScore: dumps comecam com OVEREXTENSAO (esticado+overbought),
#     nao com downtrend confirmado. Eixo bidirecional (SHORT=esticado up; LONG=esticado down).
#   Pesos DIRECIONAIS: SHORT pondera overextension/structure mais que LONG.
# Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\lib_multiframe_analysis.ps1"   # Get-RSI
. ".\agents\lib_entry_conviction_ensemble.ps1"

function Make-Series([double]$start,[double]$end,[int]$n) {
    $a=@(); for($i=0;$i -lt $n;$i++){ $a += $start + ($end-$start)*($i/($n-1)) }; return $a
}

Describe "Get-OverextensionScore (eixo de reversao)" {

    Context "SHORT = esticado pra CIMA (pre-dump)" {

        It "preco muito acima da SMA + overbought = score alto" {
            $closes = Make-Series 100 135 25   # subida forte e esticada
            $s = Get-OverextensionScore -Closes $closes -Direction "SHORT"
            ($s -ge 70) | Should Be $true
        }

        It "esticado pra cima NAO favorece LONG" {
            $closes = Make-Series 100 135 25
            $s = Get-OverextensionScore -Closes $closes -Direction "LONG"
            ($s -le 55) | Should Be $true
        }
    }

    Context "LONG = esticado pra BAIXO (pre-bounce)" {

        It "preco muito abaixo da SMA + oversold = score alto" {
            $closes = Make-Series 135 100 25   # queda forte e esticada
            $s = Get-OverextensionScore -Closes $closes -Direction "LONG"
            ($s -ge 70) | Should Be $true
        }
    }

    Context "Neutro / robustez" {

        It "preco na media = neutro ~50" {
            $closes = @(); for($i=0;$i -lt 25;$i++){ $closes += 100.0 + (($i % 2)*0.2) }
            $s = Get-OverextensionScore -Closes $closes -Direction "SHORT"
            (($s -ge 40) -and ($s -le 60)) | Should Be $true
        }

        It "dados insuficientes = 50" {
            $s = Get-OverextensionScore -Closes @(100.0,101.0) -Direction "SHORT"
            $s | Should Be 50
        }

        It "clamp 0..100" {
            $closes = Make-Series 10 200 30
            $s = Get-OverextensionScore -Closes $closes -Direction "SHORT"
            (($s -ge 0) -and ($s -le 100)) | Should Be $true
        }
    }
}

Describe "Pesos direcionais (Get-ConvictionDefaultWeights -Direction)" {

    It "SHORT pondera overextension MAIS que LONG" {
        $wl = Get-ConvictionDefaultWeights -Direction "LONG"
        $ws = Get-ConvictionDefaultWeights -Direction "SHORT"
        ($ws.overextension -gt $wl.overextension) | Should Be $true
    }

    It "LONG pondera volume/multitf mais que SHORT (trend-following)" {
        $wl = Get-ConvictionDefaultWeights -Direction "LONG"
        $ws = Get-ConvictionDefaultWeights -Direction "SHORT"
        ($wl.volume -ge $ws.volume) | Should Be $true
    }

    It "pesos somam ~1.0 (ambas direcoes)" {
        foreach ($d in @("LONG","SHORT")) {
            $w = Get-ConvictionDefaultWeights -Direction $d
            $sum = ($w.Values | Measure-Object -Sum).Sum
            ([math]::Abs($sum - 1.0) -lt 0.001) | Should Be $true
        }
    }

    It "default sem direcao continua funcionando (LONG)" {
        $w = Get-ConvictionDefaultWeights
        $w.Count | Should BeGreaterThan 0
    }
}

Describe "Ensemble usa pesos direcionais quando Weights nao passado" {

    It "SHORT com overextension alto puxa conviccao mais que LONG (mesmo axes)" {
        $axes = @{ overextension = 95; multitf = 30; btc_rs = 50; volume = 50; structure = 70; historical = 60 }
        $short = Get-EntryConviction -Axes $axes -Direction "SHORT"
        $long  = Get-EntryConviction -Axes $axes -Direction "LONG"
        ($short.conviction -gt $long.conviction) | Should Be $true
    }
}
