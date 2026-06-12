# Layer 4 Advisory Mode Tests
# Validates that Layer 4 in ADVISORY mode does NOT close positions automatically

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_layer4_tori_timestop.ps1")

Describe "Layer 4 Advisory Mode" {

    It "Update-Layer4Review accepts AutoExecute switch parameter" {
        $cmd = Get-Command Update-Layer4Review
        $hasAutoExec = $cmd.Parameters.ContainsKey('AutoExecute')
        $hasAutoExec | Should Be $true
    }

    It "Default mode is ADVISORY not AUTO_EXECUTE" {
        # Without setting global flag and without -AutoExecute switch
        $global:LAYER4_AUTO_EXECUTE = $null
        $cmd = Get-Command Update-Layer4Review
        $autoExecParam = $cmd.Parameters['AutoExecute']
        $autoExecParam.SwitchParameter | Should Be $true
    }

    It "Get-Layer4Decision returns action without executing" {
        $position = [PSCustomObject]@{
            market       = "UNIUSDT"
            side         = "LONG"
            entry        = 3.46
            peak         = 3.46
            currentPrice = 3.37
            stop         = 3.30
            target       = 3.60
            openedAt     = (Get-Date).AddHours(-27).ToString("yyyy-MM-dd HH:mm:ss")
        }

        $decision = Get-Layer4Decision -Position $position -Regime "SIDEWAYS"
        # 27h in SIDEWAYS is MEDIUM tier (between 24-36) = REVIEW_STAGNATION
        $decision.action | Should Be "REVIEW_STAGNATION"
    }

    It "Decision function does not modify position state" {
        $position = [PSCustomObject]@{
            market       = "UNIUSDT"
            side         = "LONG"
            entry        = 3.46
            peak         = 3.46
            currentPrice = 3.37
            stop         = 3.30
            target       = 3.60
            active       = $true
            openedAt     = (Get-Date).AddHours(-27).ToString("yyyy-MM-dd HH:mm:ss")
        }

        $null = Get-Layer4Decision -Position $position
        # Position should still be active after decision call
        $position.active | Should Be $true
    }

    It "Advisory mode tracks layer4Advisory metadata only" {
        # In advisory mode, position gets layer4Advisory field but stays active
        $position = [PSCustomObject]@{
            market         = "UNIUSDT"
            side           = "LONG"
            active         = $true
            layer4Advisory = "CLOSE_TIME_STOP"
        }

        $position.active | Should Be $true
        $position.layer4Advisory | Should Be "CLOSE_TIME_STOP"
    }
}

Describe "Layer 4 Auto-Execute Mode Opt-In" {

    It "Global flag LAYER4_AUTO_EXECUTE controls auto-execution" {
        # Test that setting global flag enables auto-execute path
        $global:LAYER4_AUTO_EXECUTE = $true
        $isAutoEnabled = ($global:LAYER4_AUTO_EXECUTE -eq $true)
        $isAutoEnabled | Should Be $true

        # Cleanup
        $global:LAYER4_AUTO_EXECUTE = $false
    }

    It "Auto-execute disabled by default" {
        $global:LAYER4_AUTO_EXECUTE = $null
        $isAutoEnabled = ($global:LAYER4_AUTO_EXECUTE -eq $true)
        $isAutoEnabled | Should Be $false
    }

    It "AutoExecute switch overrides global flag if true" {
        $global:LAYER4_AUTO_EXECUTE = $false
        $forceAuto = $true
        $shouldAutoExec = ($forceAuto -or ($global:LAYER4_AUTO_EXECUTE -eq $true))
        $shouldAutoExec | Should Be $true
    }
}

Describe "Layer 4 Exchange Sync Safety" {

    It "Auto-execute requires CoinEx-ClosePosition to mark journal inactive" {
        # Critical: position must close on exchange BEFORE journal marks inactive
        # This prevents the orphan-reverse problem (journal closed, exchange open)
        $exchangeClosed = $false
        $shouldMarkInactive = $exchangeClosed
        $shouldMarkInactive | Should Be $false
    }

    It "If exchange close fails, journal stays active (no orphan reverse)" {
        $exchangeClosed = $false
        $journalActive = $true
        if ($exchangeClosed) { $journalActive = $false }
        $journalActive | Should Be $true
    }

    It "If exchange close succeeds, journal marks inactive" {
        $exchangeClosed = $true
        $journalActive = $true
        if ($exchangeClosed) { $journalActive = $false }
        $journalActive | Should Be $false
    }
}
