# lib_position_risk_audit.Tests.ps1 — TDD da avaliacao pura de risco (2026-06-11)
# Caso real: XMRUSDT 20x isolated, liq -12.7%, SL decorativo abaixo da liq.

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_position_risk_audit.ps1")

Describe "Get-PositionRiskAssessment" {

    Context "Caso real XMRUSDT 20x (snapshot 2026-06-11)" {
        $pos = [PSCustomObject]@{
            market = "XMRUSDT"; side = "long"; leverage = 20
            entry = 376.03; last = 417.31
            liq_price = 364.5188775510204; stop_loss_price = 188.01
        }
        $f = @(Get-PositionRiskAssessment -Position $pos)
        $types = @($f | ForEach-Object { $_.type })

        It "flagra USELESS_SL (SL 188 abaixo da liq 364.5)" {
            ($types -contains "USELESS_SL") | Should Be $true
        }
        It "flagra LIQ_PROXIMITY (liq a 12.7% < 15%)" {
            ($types -contains "LIQ_PROXIMITY") | Should Be $true
        }
        It "flagra PROFIT_UNLOCKED (pnl +11% sem SL protegendo entry)" {
            ($types -contains "PROFIT_UNLOCKED") | Should Be $true
        }
        It "flagra HIGH_LEVERAGE (20x >= 10x)" {
            ($types -contains "HIGH_LEVERAGE") | Should Be $true
        }
        It "USELESS_SL recomenda SL entre liq e entry (executavel)" {
            $u = $f | Where-Object { $_.type -eq "USELESS_SL" }
            ($u.action -eq "SET_SL") | Should Be $true
            ($u.action_price -gt 364.52 -and $u.action_price -lt 376.03) | Should Be $true
        }
        It "PROFIT_UNLOCKED recomenda breakeven acima do entry (fee buffer)" {
            $l = $f | Where-Object { $_.type -eq "PROFIT_UNLOCKED" }
            ($l.action_price -gt 376.03) | Should Be $true
        }
    }

    Context "Posicao saudavel nao gera ruido" {
        It "MONUSDT 3x cross com SL no breakeven e pnl baixo: zero findings" {
            $pos = [PSCustomObject]@{
                market = "MONUSDT"; side = "long"; leverage = 3
                entry = 0.021459; last = 0.021671
                liq_price = 0; stop_loss_price = 0.0215
            }
            @(Get-PositionRiskAssessment -Position $pos).Count | Should Be 0
        }
        It "liq distante e pnl flat: zero findings" {
            $pos = [PSCustomObject]@{
                market = "TESTUSDT"; side = "long"; leverage = 3
                entry = 100; last = 101
                liq_price = 50; stop_loss_price = 95
            }
            @(Get-PositionRiskAssessment -Position $pos).Count | Should Be 0
        }
        It "dados invalidos (entry/last zero): retorna vazio sem explodir" {
            $pos = [PSCustomObject]@{ market = "X"; side = "long"; entry = 0; last = 0 }
            @(Get-PositionRiskAssessment -Position $pos).Count | Should Be 0
        }
    }

    Context "SHORT (logica espelhada)" {
        It "SHORT lucrativo sem SL protegendo: PROFIT_UNLOCKED com SL abaixo do entry" {
            $pos = [PSCustomObject]@{
                market = "TESTUSDT"; side = "short"; leverage = 2
                entry = 100; last = 90
                liq_price = 0; stop_loss_price = 105
            }
            $f = @(Get-PositionRiskAssessment -Position $pos)
            $l = $f | Where-Object { $_.type -eq "PROFIT_UNLOCKED" }
            ($null -ne $l) | Should Be $true
            ($l.action_price -lt 100) | Should Be $true
        }
        It "SHORT com SL alem da liq: USELESS_SL recomenda abaixo da liq" {
            $pos = [PSCustomObject]@{
                market = "TESTUSDT"; side = "sell"; leverage = 5
                entry = 100; last = 98
                liq_price = 120; stop_loss_price = 130
            }
            $f = @(Get-PositionRiskAssessment -Position $pos)
            $u = $f | Where-Object { $_.type -eq "USELESS_SL" }
            ($null -ne $u) | Should Be $true
            ($u.action_price -lt 120) | Should Be $true
        }
    }

    Context "PROFIT_RATCHET (gap spot 2026-06-12: AIN +26% destravado)" {
        It "caso real AIN: +19.8% com stop breakeven -> ratchet pra entry*(1+pnl/2)" {
            $pos = [PSCustomObject]@{
                market = "AINUSDT"; side = "long"; leverage = 1
                entry = 0.090932; last = 0.108904
                liq_price = 0; stop_loss_price = 0.0928
            }
            $f = @(Get-PositionRiskAssessment -Position $pos)
            $r = $f | Where-Object { $_.type -eq "PROFIT_RATCHET" }
            ($null -ne $r) | Should Be $true
            ($r.action_price -gt 0.0928 -and $r.action_price -lt 0.108904) | Should Be $true
            @($f | Where-Object { $_.type -eq "PROFIT_UNLOCKED" }).Count | Should Be 0
        }
        It "stop ja acima do protetor: ratchet NAO dispara (monotonico, sem ruido)" {
            $pos = [PSCustomObject]@{
                market = "X"; side = "long"; leverage = 1
                entry = 100; last = 120
                liq_price = 0; stop_loss_price = 112
            }
            @(Get-PositionRiskAssessment -Position $pos | Where-Object { $_.type -eq "PROFIT_RATCHET" }).Count | Should Be 0
        }
        It "ganho entre 8% e 15%: breakeven (PROFIT_UNLOCKED), nao ratchet" {
            $pos = [PSCustomObject]@{
                market = "X"; side = "long"; leverage = 1
                entry = 100; last = 110
                liq_price = 0; stop_loss_price = 95
            }
            $f = @(Get-PositionRiskAssessment -Position $pos)
            @($f | Where-Object { $_.type -eq "PROFIT_RATCHET" }).Count | Should Be 0
            @($f | Where-Object { $_.type -eq "PROFIT_UNLOCKED" }).Count | Should Be 1
        }
        It "SHORT espelhado: +20% short -> protetor ABAIXO do entry" {
            $pos = [PSCustomObject]@{
                market = "X"; side = "short"; leverage = 2
                entry = 100; last = 80
                liq_price = 0; stop_loss_price = 101
            }
            $r = @(Get-PositionRiskAssessment -Position $pos) | Where-Object { $_.type -eq "PROFIT_RATCHET" }
            ($null -ne $r) | Should Be $true
            ([math]::Abs($r.action_price - 90) -lt 0.01) | Should Be $true
        }
    }

    Context "Sem SL nenhum" {
        It "posicao lucrativa SEM SL: PROFIT_UNLOCKED dispara" {
            $pos = [PSCustomObject]@{
                market = "TESTUSDT"; side = "long"; leverage = 2
                entry = 100; last = 110
                liq_price = 0; stop_loss_price = 0
            }
            $f = @(Get-PositionRiskAssessment -Position $pos)
            @($f | Where-Object { $_.type -eq "PROFIT_UNLOCKED" }).Count | Should Be 1
        }
    }
}
