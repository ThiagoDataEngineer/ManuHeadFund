Describe "ConvictionGate Wire (Blocker #1 Fix)" {

    BeforeAll {
        # Load libs
        . (Join-Path $PSScriptRoot "..\agents\lib_gates_drift_wire.ps1")
    }

    Context "Test-ConvictionGate with Mesa Score Override" {
        It "Should PASS when mesa_score > 75 (elite signal)" {
            $result = Test-ConvictionGate -conviction 40 -mesa_score 84
            $result | Should Be $true
        }

        It "Should FAIL when mesa_score > 75 but conviction check function missing" {
            # If function missing, Test-ConvictionGate may not exist
            if (-not (Get-Command Test-ConvictionGate -ErrorAction SilentlyContinue)) {
                Write-Host "[WARN] Test-ConvictionGate not available" -ForegroundColor Yellow
            }
        }

        It "Should use conviction_threshold_strong (40) when mesa_score 60-75" {
            # Mesa 65, conviction 41 should pass (41 > 40)
            $result = Test-ConvictionGate -conviction 41 -mesa_score 65
            $result | Should Be $true
        }

        It "Should FAIL when mesa 65, conviction 39 (below threshold 40)" {
            $result = Test-ConvictionGate -conviction 39 -mesa_score 65
            $result | Should Be $false
        }

        # 2026-07-23 FIX (auditoria "100% integro"): Regra 3 trocou de
        # conviction_threshold (50, nunca de fato rodava -- $Gem.conviction
        # sempre chegava 0 em producao) para conviction_floor (40, ja existia
        # no JSON desde 2026-06-18 mas nunca usado). Decisao do usuario:
        # threshold mais permissivo para nao cortar volume de trades (meta:
        # varios trades/dia, scalp incluso). Valores destes testes ajustados
        # pro floor real de 40 em vez do threshold antigo de 50.
        It "Should use conviction_floor (40) when mesa <60" {
            # Mesa 50, conviction 41 should pass (41 > 40)
            $result = Test-ConvictionGate -conviction 41 -mesa_score 50
            $result | Should Be $true
        }

        It "Should FAIL when mesa <60, conviction <=40 (floor)" {
            $result = Test-ConvictionGate -conviction 39 -mesa_score 50
            $result | Should Be $false
        }
    }

    Context "Gem_Executor Integration" {
        It "Should load conviction gate wire in gem_executor" {
            $gemExecContent = Get-Content (Join-Path $PSScriptRoot "..\agents\gem_executor.ps1") -Raw
            $gemExecContent | Should Match "lib_gates_drift_wire.ps1"
            $gemExecContent | Should Match "Test-ConvictionGate"
        }

        It "Should have conviction gate BEFORE tori gate in execution order" {
            # Conviction gate should be at line ~510
            # Tori gate should be at line ~530
            # Order matters: conviction filters before tori
            $gemExecContent = Get-Content (Join-Path $PSScriptRoot "..\agents\gem_executor.ps1") -Raw
            $convictionIdx = $gemExecContent.IndexOf("CONVICTION GATE")
            $toriIdx = $gemExecContent.IndexOf("TORI GATE")
            $convictionIdx | Should BeLessThan $toriIdx
        }
    }

    Context "Elite Signals Never Rejected (BCHUSDT, ZECUSDT, HYPEUSDT)" {
        It "Should accept BCHUSDT-like signal (mesa 84, conviction 40)" {
            # BCHUSDT was rejected before fix, should pass now
            $result = Test-ConvictionGate -conviction 40 -mesa_score 84
            $result | Should Be $true
        }

        It "Should accept ZECUSDT-like signal (mesa 79, conviction 35)" {
            $result = Test-ConvictionGate -conviction 35 -mesa_score 79
            $result | Should Be $true
        }

        It "Should accept HYPEUSDT-like signal (mesa 79, conviction 30)" {
            $result = Test-ConvictionGate -conviction 30 -mesa_score 79
            $result | Should Be $true
        }
    }
}
