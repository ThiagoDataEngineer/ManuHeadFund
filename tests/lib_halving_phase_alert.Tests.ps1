# lib_halving_phase_alert.Tests.ps1 -- Pester 3.x
# Alert de mudanca de halving_phase: detecta transition + formata mensagem Telegram.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\lib_market_context_engine.ps1"
. "$here\..\agents\lib_halving_phase_alert.ps1"


Describe "Test-HalvingPhaseChanged - detecta transition" {
    It "Phase igual retorna false" {
        $result = Test-HalvingPhaseChanged -Previous "phase_1_bull" -Current "phase_1_bull"
        $result | Should Be $false
    }

    It "Phase diferente retorna true" {
        $result = Test-HalvingPhaseChanged -Previous "phase_1_bull" -Current "phase_2_top"
        $result | Should Be $true
    }

    It "Previous null trata como mudanca (primeira execucao)" {
        $result = Test-HalvingPhaseChanged -Previous $null -Current "phase_1_bull"
        $result | Should Be $true
    }
}


Describe "Format-HalvingPhaseAlert - mensagem Telegram" {
    It "Mensagem contem regime atual e implicacao" {
        $msg = Format-HalvingPhaseAlert -Previous "phase_1_bull" -Current "phase_2_top"
        $msg | Should Match "phase_2_top"
        $msg | Should Match "phase_1_bull"
    }

    It "Mensagem inclui acao recomendada por phase" {
        $msg = Format-HalvingPhaseAlert -Previous "phase_1_bull" -Current "phase_2_top"
        # phase_2_top = BLOCK BULL_WEAK
        $msg | Should Match "(?i)(block|avoid|cuidado)"
    }

    It "Primeira execucao (previous null) gera msg de boas-vindas" {
        $msg = Format-HalvingPhaseAlert -Previous $null -Current "phase_3_bear"
        $msg | Should Match "phase_3_bear"
    }
}


Describe "Get-PhaseStateFile - persistencia simples" {
    It "Path retorna string nao-vazia" {
        $p = Get-PhaseStateFile
        $p | Should Not BeNullOrEmpty
    }
}


Describe "Save-PhaseState / Get-LastPhase - I/O JSON" {
    BeforeEach {
        $tmp = Join-Path $env:TEMP "test_phase_state_$([Guid]::NewGuid().ToString('N')).json"
        $global:__TEST_PHASE_FILE = $tmp
    }
    AfterEach {
        if (Test-Path $global:__TEST_PHASE_FILE) { Remove-Item $global:__TEST_PHASE_FILE -Force }
        Remove-Variable -Name "__TEST_PHASE_FILE" -Scope Global -ErrorAction SilentlyContinue
    }

    It "Save + Get retorna mesma phase" {
        Save-PhaseState -Phase "phase_2_top" -StatePath $global:__TEST_PHASE_FILE
        $p = Get-LastPhase -StatePath $global:__TEST_PHASE_FILE
        $p | Should Be "phase_2_top"
    }

    It "Arquivo inexistente retorna null" {
        $tmp = Join-Path $env:TEMP "nonexistent_$([Guid]::NewGuid().ToString('N')).json"
        $p = Get-LastPhase -StatePath $tmp
        $p | Should BeNullOrEmpty
    }
}
