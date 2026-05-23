# orchestrator_v6_live_execution.Tests.ps1 -- Pester 3.x
#
# V6 PlaceOrder gap (2026-05-20): testa que Invoke-OrchestratorV6 corretamente
# decide entre paper-only (B default) e live execution (A opt-in via flag).
#
# Estrategia: testar funcao pura Invoke-V6PostMentorExecution que recebe
# decisao+flags+stubs e retorna ordemId ou null. Logica de IO fica isolada.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Stubs globais
$global:CLAUDE_MODEL      = "claude-sonnet-4"
$global:CLAUDE_MAX_TOKENS = 4000
$global:ANTHROPIC_API_KEY = "test-key"

function Write-Host    { param() }
function Write-Warning { param() }

# Dot-source orchestrator_v6 pra carregar Invoke-V6PostMentorExecution (sera adicionada)
. "$here\..\agents\orchestrator_v6.ps1"

# Stubs APOS dot-source
$global:STUB_TG_APPROVAL = $true
$global:STUB_ORDER       = [PSCustomObject]@{ order_id = "ORD_TEST_123" }
$global:STUB_PLACEORDER_THROW = $false
$global:CALLED_TG_APPROVAL = $false
$global:CALLED_PLACEORDER  = $false

function Wait-TelegramApproval {
    param([string]$Message, [int]$TimeoutSeconds)
    $global:CALLED_TG_APPROVAL = $true
    return $global:STUB_TG_APPROVAL
}
function CoinEx-PlaceOrder {
    param($Market, $Side, $Type, $Amount, $Price, $StopLoss, $Target, $StpMode)
    $global:CALLED_PLACEORDER = $true
    if ($global:STUB_PLACEORDER_THROW) { throw "mock_api_failure" }
    return $global:STUB_ORDER
}
function Send-TelegramAlert { param() return $true }

function Reset-Stubs {
    $global:CALLED_TG_APPROVAL = $false
    $global:CALLED_PLACEORDER  = $false
    $global:STUB_TG_APPROVAL   = $true
    $global:STUB_PLACEORDER_THROW = $false
}

# Helper: monta tmp journal dir + opt-in flags
function New-FlagsDir {
    param([switch]$LiveMode, [switch]$V6Live)
    $tmp = Join-Path $env:TEMP "v6live_$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    if ($LiveMode) { "x" | Out-File (Join-Path $tmp "LIVE_MODE_ENABLED.flag") -Encoding utf8 }
    if ($V6Live)   { "x" | Out-File (Join-Path $tmp "V6_LIVE_ENABLED.flag")   -Encoding utf8 }
    return $tmp
}

function New-MentorApprove { [PSCustomObject]@{ decision="APROVAR"; confianca=80; mentor_mensagem="ok" } }
function New-MentorVeto    { [PSCustomObject]@{ decision="VETAR"; confianca=20; mentor_mensagem="veto" } }
function New-Setup { [PSCustomObject]@{ entry=100; stop=95; target=120; rr=4 } }


Describe "Invoke-V6PostMentorExecution - B (paper default)" {

    It "Sem V6_LIVE flag: NUNCA chama PlaceOrder mesmo com Mentor APROVAR + LIVE_MODE" {
        Reset-Stubs
        $dir = New-FlagsDir -LiveMode  # so LIVE_MODE, sem V6_LIVE
        $r = Invoke-V6PostMentorExecution -Market "BTCUSDT" -Decisao "EXECUTAR" `
            -Mentor (New-MentorApprove) -Setup (New-Setup) -Side "buy" -Amount 10 `
            -JournalDir $dir -DryRun:$false
        $r.ordemId | Should Be $null
        $r.paperOnly | Should Be $true
        $global:CALLED_PLACEORDER | Should Be $false
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Sem nenhuma flag (defensive default): paper-only" {
        Reset-Stubs
        $dir = New-FlagsDir   # zero flags
        $r = Invoke-V6PostMentorExecution -Market "BTCUSDT" -Decisao "EXECUTAR" `
            -Mentor (New-MentorApprove) -Setup (New-Setup) -Side "buy" -Amount 10 `
            -JournalDir $dir -DryRun:$false
        $r.ordemId | Should Be $null
        $r.paperOnly | Should Be $true
        $global:CALLED_PLACEORDER | Should Be $false
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "DryRun=true sobrepoe flags (forca paper)" {
        Reset-Stubs
        $dir = New-FlagsDir -LiveMode -V6Live  # ambos flags
        $r = Invoke-V6PostMentorExecution -Market "BTCUSDT" -Decisao "EXECUTAR" `
            -Mentor (New-MentorApprove) -Setup (New-Setup) -Side "buy" -Amount 10 `
            -JournalDir $dir -DryRun:$true
        $r.ordemId | Should Be $null
        $r.paperOnly | Should Be $true
        $global:CALLED_PLACEORDER | Should Be $false
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Decisao VETAR: NUNCA executa mesmo com flags" {
        Reset-Stubs
        $dir = New-FlagsDir -LiveMode -V6Live
        $r = Invoke-V6PostMentorExecution -Market "BTCUSDT" -Decisao "ABORTAR" `
            -Mentor (New-MentorVeto) -Setup (New-Setup) -Side "buy" -Amount 10 `
            -JournalDir $dir -DryRun:$false
        $r.ordemId | Should Be $null
        $global:CALLED_PLACEORDER | Should Be $false
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}


Describe "Invoke-V6PostMentorExecution - A (live opt-in com 2 flags)" {

    It "Ambos flags + EXECUTAR + approval OK: chama PlaceOrder + retorna ordemId" {
        Reset-Stubs
        $global:STUB_TG_APPROVAL = $true
        $dir = New-FlagsDir -LiveMode -V6Live
        $r = Invoke-V6PostMentorExecution -Market "BTCUSDT" -Decisao "EXECUTAR" `
            -Mentor (New-MentorApprove) -Setup (New-Setup) -Side "buy" -Amount 10 `
            -JournalDir $dir -DryRun:$false
        $global:CALLED_TG_APPROVAL | Should Be $true
        $global:CALLED_PLACEORDER  | Should Be $true
        $r.ordemId | Should Be "ORD_TEST_123"
        $r.paperOnly | Should Be $false
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Ambos flags + EXECUTAR + approval CANCEL: ordemId null + decisao CANCELADO" {
        Reset-Stubs
        $global:STUB_TG_APPROVAL = $false   # user disse nao
        $dir = New-FlagsDir -LiveMode -V6Live
        $r = Invoke-V6PostMentorExecution -Market "BTCUSDT" -Decisao "EXECUTAR" `
            -Mentor (New-MentorApprove) -Setup (New-Setup) -Side "buy" -Amount 10 `
            -JournalDir $dir -DryRun:$false
        $global:CALLED_TG_APPROVAL | Should Be $true
        $global:CALLED_PLACEORDER  | Should Be $false
        $r.ordemId | Should Be $null
        $r.decisaoFinal | Should Be "CANCELADO_THIAGO"
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "PlaceOrder throws: ordemId null + decisao ERRO_EXECUCAO" {
        Reset-Stubs
        $global:STUB_TG_APPROVAL = $true
        $global:STUB_PLACEORDER_THROW = $true
        $dir = New-FlagsDir -LiveMode -V6Live
        $r = Invoke-V6PostMentorExecution -Market "BTCUSDT" -Decisao "EXECUTAR" `
            -Mentor (New-MentorApprove) -Setup (New-Setup) -Side "buy" -Amount 10 `
            -JournalDir $dir -DryRun:$false
        $global:CALLED_TG_APPROVAL | Should Be $true
        $global:CALLED_PLACEORDER  | Should Be $true
        $r.ordemId | Should Be $null
        $r.decisaoFinal | Should Be "ERRO_EXECUCAO"
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Amount <= 0: skip PlaceOrder (safety)" {
        Reset-Stubs
        $dir = New-FlagsDir -LiveMode -V6Live
        $r = Invoke-V6PostMentorExecution -Market "BTCUSDT" -Decisao "EXECUTAR" `
            -Mentor (New-MentorApprove) -Setup (New-Setup) -Side "buy" -Amount 0 `
            -JournalDir $dir -DryRun:$false
        $global:CALLED_PLACEORDER | Should Be $false
        $r.ordemId | Should Be $null
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
