# conviction_axes_plus.Tests.ps1 -- TDD eixos novos (volume + estrutura) + stop default
# (c): consertar StopPct=0 + ligar mais eixos no ensemble.
# Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\lib_sizing_dynamics.ps1"
. ".\agents\lib_entry_conviction_ensemble.ps1"

Describe "Resolve-StopTargetPct (conserta StopPct=0)" {

    It "usa stop/target do sizing quando validos" {
        $r = Resolve-StopTargetPct -Sizing @{ stop_pct = 0.015; target_pct = 0.075 }
        $r.stop_pct | Should Be 0.015
        $r.target_pct | Should Be 0.075
    }

    It "stop_pct=0 (gem TRIGGER) -> usa default 0.02" {
        $r = Resolve-StopTargetPct -Sizing @{ sizing_pct = 0.02 }
        $r.stop_pct | Should Be 0.02
        ($r.target_pct -gt 0) | Should Be $true
    }

    It "stop_pct ausente (null) -> default" {
        $r = Resolve-StopTargetPct -Sizing @{ stop_pct = $null; target_pct = $null }
        ($r.stop_pct -gt 0 -and $r.stop_pct -lt 1) | Should Be $true
        ($r.target_pct -gt 0) | Should Be $true
    }

    It "stop_pct >= 1 (invalido) -> default" {
        $r = Resolve-StopTargetPct -Sizing @{ stop_pct = 5; target_pct = 0 }
        ($r.stop_pct -lt 1) | Should Be $true
    }

    It "respeita defaults customizados" {
        $r = Resolve-StopTargetPct -Sizing @{} -DefaultStop 0.03 -DefaultTarget 0.15
        $r.stop_pct | Should Be 0.03
        $r.target_pct | Should Be 0.15
    }

    It "mantem R:R 1:5 no default (target = 5x stop)" {
        $r = Resolve-StopTargetPct -Sizing @{}
        ([math]::Round($r.target_pct / $r.stop_pct, 1)) | Should Be 5
    }
}

Describe "Eixo Volume (volume antes do preco)" {

    Context "Get-VolumeConvictionScore" {

        It "volume estavel (ratio ~1) = neutro ~50" {
            $vols = @(100.0,100.0,100.0,100.0,100.0,100.0,100.0,100.0)
            $s = Get-VolumeConvictionScore -Volumes $vols
            (($s -ge 45) -and ($s -le 55)) | Should Be $true
        }

        It "spike forte de volume (2x+) = score alto" {
            $vols = @(100.0,100.0,100.0,100.0,100.0,250.0,260.0,255.0)
            $s = Get-VolumeConvictionScore -Volumes $vols
            ($s -ge 80) | Should Be $true
        }

        It "volume secando = score baixo" {
            $vols = @(200.0,200.0,200.0,200.0,200.0,80.0,70.0,75.0)
            $s = Get-VolumeConvictionScore -Volumes $vols
            ($s -lt 50) | Should Be $true
        }

        It "dados insuficientes = neutro 50 (nao quebra)" {
            $s = Get-VolumeConvictionScore -Volumes @(100.0)
            $s | Should Be 50
        }

        It "clamp 0..100" {
            $vols = @(1.0,1.0,1.0,1.0,1.0,1000.0,1000.0,1000.0)
            $s = Get-VolumeConvictionScore -Volumes $vols
            ($s -le 100) | Should Be $true
        }
    }
}

Describe "Eixo Estrutura (posicao no range)" {

    Context "Get-RangePositionScore" {

        It "LONG perto do suporte (fundo do range) = score alto" {
            $highs = @(110.0,108.0,112.0,109.0)
            $lows  = @(100.0,101.0,99.0,100.0)
            $s = Get-RangePositionScore -Highs $highs -Lows $lows -CurrentPrice 100.5 -Direction "LONG"
            ($s -ge 70) | Should Be $true
        }

        It "LONG perto da resistencia (topo) = score baixo" {
            $highs = @(110.0,108.0,112.0,109.0)
            $lows  = @(100.0,101.0,99.0,100.0)
            $s = Get-RangePositionScore -Highs $highs -Lows $lows -CurrentPrice 111.5 -Direction "LONG"
            ($s -le 30) | Should Be $true
        }

        It "SHORT perto da resistencia = score alto" {
            $highs = @(110.0,108.0,112.0,109.0)
            $lows  = @(100.0,101.0,99.0,100.0)
            $s = Get-RangePositionScore -Highs $highs -Lows $lows -CurrentPrice 111.5 -Direction "SHORT"
            ($s -ge 70) | Should Be $true
        }

        It "range zero (nao quebra) = neutro 50" {
            $s = Get-RangePositionScore -Highs @(100.0,100.0) -Lows @(100.0,100.0) -CurrentPrice 100.0 -Direction "LONG"
            $s | Should Be 50
        }
    }
}

Describe "Ensemble com 4 eixos" {

    It "combina structure+btc_rs+volume+multitf" {
        $axes = @{ structure = 80; btc_rs = 70; volume = 75; multitf = 60 }
        $r = Get-EntryConviction -Axes $axes -Direction "LONG"
        $r.axes_used.Count | Should Be 4
        (($r.conviction -ge 0) -and ($r.conviction -le 100)) | Should Be $true
    }
}
