# conviction_axes_final.Tests.ps1 -- TDD dos 2 ultimos eixos (servico completo)
#   structure -> trendline/S-R real (toques) via Get-StructureFromCandles
#   historical -> fingerprint de pre-pump (compressao+volume+higher-lows)
# Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\lib_entry_conviction_ensemble.ps1"

Describe "Eixo Estrutura por trendline real (Get-StructureFromCandles)" {

    Context "LONG - toques no suporte" {

        It "3 toques no suporte + span + bounce = score alto" {
            #            idx: 0     1     2     3     4     5     6     7
            $lows  = @(  100.0, 106.0, 100.4, 107.0, 105.0, 108.0, 100.6, 106.0)
            $highs = @(  108.0, 109.0, 107.0, 110.0, 109.0, 111.0, 108.0, 110.0)
            $closes= @(  105.0, 107.0, 104.0, 108.0, 107.0, 109.0, 104.0, 108.0)
            $s = Get-StructureFromCandles -Highs $highs -Lows $lows -Closes $closes -Direction "LONG"
            ($s -ge 70) | Should Be $true
        }

        It "1 toque so = score baixo (voto fraco, nao veto)" {
            $lows  = @(100.0, 120.0, 130.0, 125.0, 128.0, 124.0)
            $highs = @(110.0, 125.0, 135.0, 130.0, 133.0, 129.0)
            $closes= @(108.0, 123.0, 133.0, 128.0, 131.0, 127.0)
            $s = Get-StructureFromCandles -Highs $highs -Lows $lows -Closes $closes -Direction "LONG"
            ($s -le 40) | Should Be $true
        }
    }

    Context "SHORT - toques na resistencia" {

        It "3 toques na resistencia = score alto" {
            $highs = @(120.0, 114.0, 119.8, 113.0, 115.0, 112.0, 119.6, 114.0)
            $lows  = @(112.0, 111.0, 113.0, 110.0, 111.0, 109.0, 112.0, 110.0)
            $closes= @(114.0, 112.0, 115.0, 111.0, 112.0, 110.0, 115.0, 112.0)
            $s = Get-StructureFromCandles -Highs $highs -Lows $lows -Closes $closes -Direction "SHORT"
            ($s -ge 70) | Should Be $true
        }
    }

    Context "Robustez" {

        It "dados insuficientes = neutro 50" {
            $s = Get-StructureFromCandles -Highs @(1.0) -Lows @(1.0) -Closes @(1.0) -Direction "LONG"
            $s | Should Be 50
        }
    }
}

Describe "Eixo Historico - fingerprint de pre-pump (Get-PrePumpFingerprintScore)" {

    Context "LONG (pre-pump)" {

        It "compressao + volume subindo + higher-lows = score alto" {
            # range comprimindo, volume crescente, fundos subindo (acumulacao)
            $highs = @(120.0,118.0,116.0,114.0,113.0,112.5,112.0,111.8)
            $lows  = @(100.0,103.0,105.0,107.0,108.0,108.5,109.0,109.5)
            $closes= @(110.0,111.0,110.5,111.0,110.8,111.2,111.0,111.5)
            $vols  = @(100.0,110.0,120.0,130.0,150.0,170.0,190.0,210.0)
            $s = Get-PrePumpFingerprintScore -Highs $highs -Lows $lows -Closes $closes -Volumes $vols -Direction "LONG"
            ($s -ge 65) | Should Be $true
        }

        It "pump ja explodiu (expansao + volume ja gasto) = score menor" {
            $highs = @(100.0,101.0,102.0,103.0,120.0,140.0,160.0,180.0)
            $lows  = @(99.0,100.0,101.0,102.0,110.0,130.0,150.0,170.0)
            $closes= @(100.0,101.0,102.0,103.0,119.0,139.0,159.0,179.0)
            $vols  = @(300.0,280.0,260.0,240.0,220.0,200.0,180.0,160.0)
            $s = Get-PrePumpFingerprintScore -Highs $highs -Lows $lows -Closes $closes -Volumes $vols -Direction "LONG"
            ($s -lt 65) | Should Be $true
        }

        It "dados insuficientes = neutro 50" {
            $s = Get-PrePumpFingerprintScore -Highs @(1.0) -Lows @(1.0) -Closes @(1.0) -Volumes @(1.0) -Direction "LONG"
            $s | Should Be 50
        }
    }

    Context "SHORT (pre-dump = lower-highs)" {

        It "lower-highs + volume subindo + compressao = score alto" {
            $highs = @(120.0,118.0,116.0,114.0,113.0,112.0,111.0,110.5)
            $lows  = @(100.0,101.0,102.0,103.0,104.0,104.5,105.0,105.5)
            $closes= @(110.0,109.0,108.0,107.0,107.0,106.5,106.0,106.0)
            $vols  = @(100.0,120.0,140.0,160.0,180.0,200.0,220.0,240.0)
            $s = Get-PrePumpFingerprintScore -Highs $highs -Lows $lows -Closes $closes -Volumes $vols -Direction "SHORT"
            ($s -ge 65) | Should Be $true
        }
    }

    Context "clamp" {
        It "score sempre 0..100" {
            $highs = @(120.0,115.0,112.0,110.0,109.0,108.0,107.5,107.0)
            $lows  = @(90.0,95.0,100.0,103.0,105.0,106.0,106.5,107.0)
            $closes= @(105.0,106.0,106.0,107.0,107.0,107.0,107.0,107.0)
            $vols  = @(10.0,50.0,100.0,200.0,400.0,800.0,1600.0,3200.0)
            $s = Get-PrePumpFingerprintScore -Highs $highs -Lows $lows -Closes $closes -Volumes $vols -Direction "LONG"
            (($s -ge 0) -and ($s -le 100)) | Should Be $true
        }
    }
}

Describe "Ensemble 5 eixos completo" {

    It "combina os 5 eixos canonicos" {
        $axes = @{ structure = 70; btc_rs = 80; volume = 75; multitf = 65; historical = 72 }
        $r = Get-EntryConviction -Axes $axes -Direction "LONG"
        $r.axes_used.Count | Should Be 5
        (($r.conviction -ge 0) -and ($r.conviction -le 100)) | Should Be $true
    }
}
