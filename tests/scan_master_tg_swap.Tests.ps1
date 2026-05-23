# scan_master_tg_swap.Tests.ps1 -- Pester 3.x
# TDD: garante que scan_master.ps1 usa Wait-TgCallbackApproval (Stage 3 inline keyboard)
# ao inves de Wait-TelegramApproval (message polling legado).
#
# Contrato Wait-TgCallbackApproval:
#   params: -Gem (obj), -GemId (string), -TimeoutSeconds (int)
#   retorno: hashtable @{ decision; from; message_id; elapsed_ms }
#     decision in { approve, reject, timeout, error }
#
# Contrato Wait-TelegramApproval (legado):
#   params: -Message (string), -TimeoutSeconds (int)
#   retorno: bool

$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptsDir = Join-Path (Split-Path $here -Parent) "scripts"
$agentsDir  = Join-Path (Split-Path $here -Parent) "agents"
$scanMaster = Join-Path $scriptsDir "scan_master.ps1"
$libTg      = Join-Path $agentsDir  "lib_telegram.ps1"


Describe "scan_master.ps1 Telegram approval swap - Stage 3 inline keyboard" {

    It "scan_master.ps1 NAO contem chamada Wait-TelegramApproval (deprecated)" {
        $content = Get-Content -Raw -Path $scanMaster
        ($content -match "Wait-TelegramApproval") | Should Be $false
    }

    It "scan_master.ps1 contem chamada Wait-TgCallbackApproval" {
        $content = Get-Content -Raw -Path $scanMaster
        ($content -match "Wait-TgCallbackApproval") | Should Be $true
    }

    It "Wait-TgCallbackApproval esta definida em agents/lib_telegram.ps1" {
        $libContent = Get-Content -Raw -Path $libTg
        ($libContent -match "function Wait-TgCallbackApproval") | Should Be $true
    }

    It "Chamada em scan_master.ps1 passa -Gem e -GemId (contrato novo)" {
        $content = Get-Content -Raw -Path $scanMaster
        # Bloco em torno da chamada Wait-TgCallbackApproval deve ter -Gem e -GemId
        ($content -match "(?ms)Wait-TgCallbackApproval[^\r\n]*-Gem\s")   | Should Be $true
        ($content -match "(?ms)Wait-TgCallbackApproval[^\r\n]*-GemId\s") | Should Be $true
    }

    It "Resultado de Wait-TgCallbackApproval e tratado como hashtable com .decision (NAO como bool)" {
        $content = Get-Content -Raw -Path $scanMaster
        # Deve usar .decision -eq 'approve' (ou similar) ao inves de if ($aprovado)
        ($content -match "\.decision\s*-eq\s*['""]approve['""]") | Should Be $true
    }
}
