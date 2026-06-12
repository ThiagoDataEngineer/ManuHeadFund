# promotion_telegram.Tests.ps1 -- TDD Format-TgPromotion*
# Pester 3.x. UTF-8 BOM.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_promotion_telegram.ps1")

Describe "Format-TgPromotionPropose" {

    It "contem market e acao promote" {
        $proposal = [PSCustomObject]@{
            action = "propose_promote"
            from_state = 1
            to_state = 2
            gate = [PSCustomObject]@{
                gate = "obs_to_c"
                passed = $true
                reasons = @("sharpe_30d_ok","mom_20d_positive","n_trades_ok","max_dd_ok","regime_ok")
                failures = @()
            }
        }
        $msg = Format-TgPromotionPropose -Market "PENDLEUSDT" -Proposal $proposal
        $msg -match "PENDLEUSDT" | Should Be $true
        $msg -match "promote|PROMOTE" | Should Be $true
    }

    It "menciona tier source e tier target" {
        $proposal = [PSCustomObject]@{
            action = "propose_promote"
            from_state = 2
            to_state = 3
            gate = [PSCustomObject]@{
                gate = "c_to_b"
                passed = $true
                reasons = @("sharpe_60d_ok","psr_ok")
                failures = @()
            }
        }
        $msg = Format-TgPromotionPropose -Market "TONUSDT" -Proposal $proposal
        $msg -match "PAPER_C" | Should Be $true
        $msg -match "PAPER_B" | Should Be $true
    }

    It "lista reasons quando gate passa" {
        $proposal = [PSCustomObject]@{
            action = "propose_promote"
            from_state = 1
            to_state = 2
            gate = [PSCustomObject]@{
                gate = "obs_to_c"
                passed = $true
                reasons = @("sharpe_30d_ok","regime_ok (BULL_STRONG|BEAR_WEAK)")
                failures = @()
            }
        }
        $msg = Format-TgPromotionPropose -Market "X" -Proposal $proposal
        $msg -match "sharpe_30d_ok" | Should Be $true
    }

    It "demote message contem acao demote e razao" {
        $proposal = [PSCustomObject]@{
            action = "propose_demote"
            from_state = 3
            to_state = 2
            reason = "consecutive_negative_4_weeks"
        }
        $msg = Format-TgPromotionPropose -Market "ZECUSDT" -Proposal $proposal
        $msg -match "demote|DEMOTE" | Should Be $true
        $msg -match "consecutive_negative" | Should Be $true
    }
}
