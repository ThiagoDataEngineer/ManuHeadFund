# lib_sizing_dynamics_stop_target.Tests.ps1 -- TDD de Resolve-StopTargetPct
# (agents/lib_sizing_dynamics.ps1)
#
# 2026-09-01: FIX CRITICO -- DefaultStop=0.02 hardcoded era o mesmo fallback
# de emergencia que ja causou o bug de 2026-08-25 (stop de 2% em TRIGGER/
# TORI_*). Aquele fix so populou stop_pct na origem (gem_loop.ps1), nunca
# mudou o DEFAULT desta funcao. Achado real: ARBUSDT reabriu/stopou 4x em 6h
# via caminho diferente (discovery scan em gem_executor.ps1) que tambem cai
# no default sem popular sizing.stop_pct -- confirmado stop_pct=2.00%
# cravado nas 4 entradas, -$19.62 em 6h. Fix: default agora usa
# $global:GEM_STOP_TRIGGER_1H (constante ja calibrada por ATR real,
# config.ps1) em vez de reintroduzir 2% hardcoded.
#
# Pester 3.4 (motor real de producao/CI).

$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_sizing_dynamics.ps1")

Describe "Resolve-StopTargetPct" {
    BeforeEach {
        # Isola de qualquer config.ps1 real ja carregada no processo de teste.
        $global:GEM_STOP_TRIGGER_1H = $null
    }

    Context "Sizing com stop_pct/target_pct validos (caminho feliz, preservado)" {
        It "usa stop_pct/target_pct do Sizing quando presentes e validos (PSCustomObject)" {
            $sizing = [PSCustomObject]@{ stop_pct = 0.30; target_pct = 0.90 }
            $r = Resolve-StopTargetPct -Sizing $sizing
            $r.stop_pct | Should Be 0.30
            $r.target_pct | Should Be 0.90
        }
        It "usa stop_pct/target_pct do Sizing quando presentes e validos (hashtable)" {
            $sizing = @{ stop_pct = 0.50; target_pct = 2.50 }
            $r = Resolve-StopTargetPct -Sizing $sizing
            $r.stop_pct | Should Be 0.50
            $r.target_pct | Should Be 2.50
        }
    }

    Context "Sizing ausente/invalido -- default (achado real ARBUSDT)" {
        It "sem $global:GEM_STOP_TRIGGER_1H definido: cai no fallback fixo 0.03 (NAO mais 0.02)" {
            $r = Resolve-StopTargetPct -Sizing $null
            $r.stop_pct | Should Be 0.03
        }

        It "COM $global:GEM_STOP_TRIGGER_1H definido: usa a constante calibrada por ATR real" {
            $global:GEM_STOP_TRIGGER_1H = 0.03
            $r = Resolve-StopTargetPct -Sizing $null
            $r.stop_pct | Should Be 0.03
        }

        It "se GEM_STOP_TRIGGER_1H for recalibrado no futuro (ex: 0.035), o default acompanha" {
            $global:GEM_STOP_TRIGGER_1H = 0.035
            $r = Resolve-StopTargetPct -Sizing $null
            $r.stop_pct | Should Be 0.035
        }

        It "Sizing SEM stop_pct (caso real: sizing so tem sizing_pct, achado 2026-08-25/09-01) cai no default calibrado" {
            $sizing = [PSCustomObject]@{ sizing_pct = 0.02 }
            $r = Resolve-StopTargetPct -Sizing $sizing
            $r.stop_pct | Should Be 0.03
        }

        It "stop_pct=0 no Sizing (invalido) cai no default calibrado, nao fica 0" {
            $sizing = [PSCustomObject]@{ stop_pct = 0 }
            $r = Resolve-StopTargetPct -Sizing $sizing
            $r.stop_pct | Should Be 0.03
        }

        It "stop_pct>=1 no Sizing (invalido, fracao errada) cai no default calibrado" {
            $sizing = [PSCustomObject]@{ stop_pct = 1.5 }
            $r = Resolve-StopTargetPct -Sizing $sizing
            $r.stop_pct | Should Be 0.03
        }

        It "target_pct ausente cai no default de R:R 1:5 (0.10), independente do stop" {
            $r = Resolve-StopTargetPct -Sizing $null
            $r.target_pct | Should Be 0.10
        }
    }

    Context "DefaultStop explicito ainda funciona (override manual preservado)" {
        It "-DefaultStop explicito (>0) tem prioridade sobre GEM_STOP_TRIGGER_1H" {
            $global:GEM_STOP_TRIGGER_1H = 0.03
            $r = Resolve-StopTargetPct -Sizing $null -DefaultStop 0.50
            $r.stop_pct | Should Be 0.50
        }
    }
}
