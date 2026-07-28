# orchestrator_v6.Tests.ps1 -- Pester 3.x
# Testa Invoke-V6Cascade: triagem (Parte A) -> mesa (Parte B) -> mentor debate
# Funcao pura, testavel: stubs de Invoke-Triagem / Invoke-Mesa / Invoke-MentorDebate

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Stubs minimos de config
$global:CLAUDE_MODEL      = "claude-sonnet-4"
$global:CLAUDE_MAX_TOKENS = 4000
$global:CLAUDE_TEMP_TRADE = 0.3
$global:ANTHROPIC_API_KEY = "test-key"

function Write-Host    { param() }
function Write-Warning { param() }

# Carrega apenas o que precisamos: cascade isolada
. "$here\..\agents\orchestrator_v6.ps1"

# Stubs APOS dot-source (mesma razao do mentor_debate)
$global:STUB_TRIAGEM = $null
$global:STUB_MESA    = $null
$global:STUB_MENTOR  = $null
$global:CALLED_MESA   = $false
$global:CALLED_MENTOR = $false

function Invoke-Triagem {
    param([string]$Market, [PSCustomObject]$Context)
    return $global:STUB_TRIAGEM
}
function Invoke-Mesa {
    param([string]$Market, [PSCustomObject]$Context)
    $global:CALLED_MESA = $true
    return $global:STUB_MESA
}
function Invoke-MentorDebate {
    param([string]$Market, [PSCustomObject]$TriagemResult, [PSCustomObject]$MesaResult,
          [PSCustomObject]$Setup, [string]$KnowledgeContext)
    $global:CALLED_MENTOR = $true
    return $global:STUB_MENTOR
}

# 2026-07-28: captura o Direction recebido por Build-MentorFullContext --
# achado real: orchestrator_v6 passava $wlDirection (direcao da TRIAGEM) em
# vez da direcao EFETIVA (Mesa > Triagem, mesma precedencia de Resolve-
# MentorDirection), entao Test-BetaWithinCap nunca via Direction=SHORT
# quando a Triagem dizia LONG mas a Mesa mudava pra SHORT (caso comum:
# LONG bloqueado por breadth, Mentor reavalia SHORT).
$global:CAPTURED_FULLCTX_DIRECTION = $null
function Build-MentorFullContext {
    param([string]$Market, [string]$Mode = "STANDARD", [string]$RegimeBias = "", [string]$Direction = "")
    $global:CAPTURED_FULLCTX_DIRECTION = $Direction
    return $null
}

# Helpers
function Set-Triagem { param([string]$Tier="B",[int]$Score=65,[string]$Razao="",[string]$Direction="")
    $global:STUB_TRIAGEM = [PSCustomObject]@{
        tier=$Tier; score_predicted=$Score; razao=$Razao; direction=$Direction
        flags=@(); knowledge_cited=@(); setup=$null
    }
}
function Set-Mesa { param([string]$Consensus="FORTE_3",[string]$Sinal="LONG",[int]$Avg=70)
    $global:STUB_MESA = [PSCustomObject]@{
        termal=[PSCustomObject]@{sinal=$Sinal;forca=70}
        radar =[PSCustomObject]@{sinal=$Sinal;forca=68}
        lidar =[PSCustomObject]@{sinal=$Sinal;forca=72}
        consensus=$Consensus; sinal_consenso=$Sinal; score_avg=$Avg; setup=$null
    }
}
function Set-Mentor { param([string]$Decision="APROVAR",[int]$Conf=80,[string]$Msg="ok")
    $global:STUB_MENTOR = [PSCustomObject]@{
        decision=$Decision; confianca=$Conf; mentor_mensagem=$Msg; knowledge_cited=@()
    }
}

$ctx   = [PSCustomObject]@{ macro="NEUTRO"; capital=1000 }
$setup = [PSCustomObject]@{ entry=100; stop=95; target=120; rr=4 }

Describe "Invoke-V6Cascade - cascata Triagem -> Mesa -> Mentor" {

    BeforeEach {
        $global:CALLED_MESA = $false
        $global:CALLED_MENTOR = $false
        Set-Mentor "APROVAR" 80 "ok"
    }

    It "Tier D aborta SEM chamar Mesa nem Mentor" {
        Set-Triagem -Tier "D" -Razao "tendencia ausente"
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.decisao) | Should Be "ABORTAR"
        ($global:CALLED_MESA)   | Should Be $false
        ($global:CALLED_MENTOR) | Should Be $false
    }

    It "Tier D motivo vem da razao da Triagem" {
        Set-Triagem -Tier "D" -Razao "macro hostil"
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.motivo) | Should Be "macro hostil"
    }

    It "Tier A pula Mesa e vai direto ao Mentor" {
        Set-Triagem -Tier "A" -Score 85
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($global:CALLED_MESA)   | Should Be $false
        ($global:CALLED_MENTOR) | Should Be $true
    }

    It "Tier B faz pipeline completo (Triagem -> Mesa -> Mentor)" {
        Set-Triagem -Tier "B"; Set-Mesa "FORTE_3" "LONG" 70
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($global:CALLED_MESA)   | Should Be $true
        ($global:CALLED_MENTOR) | Should Be $true
    }

    It "Mesa CAOS aborta SEM chamar Mentor" {
        Set-Triagem -Tier "B"; Set-Mesa "CAOS" "MISTO" 50
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.decisao) | Should Be "ABORTAR"
        ($global:CALLED_MENTOR) | Should Be $false
    }

    It "Mesa CAOS motivo menciona Mesa dividida" {
        Set-Triagem -Tier "B"; Set-Mesa "CAOS" "MISTO" 50
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.motivo -match "Mesa") | Should Be $true
    }

    It "Mentor APROVAR -> decisao EXECUTAR" {
        Set-Triagem -Tier "B"; Set-Mesa
        Set-Mentor "APROVAR" 85 "limpo"
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.decisao) | Should Be "EXECUTAR"
    }

    It "Mentor VETAR -> decisao ABORTAR" {
        Set-Triagem -Tier "B"; Set-Mesa
        Set-Mentor "VETAR" 20 "macro contra"
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.decisao) | Should Be "ABORTAR"
    }

    It "Mentor VETAR -> telegramFire = false (nao dispara TG)" {
        Set-Triagem -Tier "B"; Set-Mesa
        Set-Mentor "VETAR" 20 "FOMO classico"
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.telegramFire) | Should Be $false
    }

    It "Mentor APROVAR -> telegramFire = true (dispara TG)" {
        Set-Triagem -Tier "B"; Set-Mesa
        Set-Mentor "APROVAR" 85 "ok"
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.telegramFire) | Should Be $true
    }

    It "Tier D -> telegramFire = false" {
        Set-Triagem -Tier "D" -Razao "x"
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.telegramFire) | Should Be $false
    }

    It "resultado inclui triagem, mesa e mentor objetos" {
        Set-Triagem -Tier "B"; Set-Mesa; Set-Mentor
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.triagem) | Should Not BeNullOrEmpty
        ($out.mesa)    | Should Not BeNullOrEmpty
        ($out.mentor)  | Should Not BeNullOrEmpty
    }

    It "Tier A retorna mesa = null" {
        Set-Triagem -Tier "A" -Score 85; Set-Mentor
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.mesa -eq $null) | Should Be $true
    }

    It "Tier D retorna mentor = null (curto-circuito)" {
        Set-Triagem -Tier "D" -Razao "x"
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.mentor -eq $null) | Should Be $true
    }

    It "Mesa CAOS retorna mentor = null" {
        Set-Triagem -Tier "B"; Set-Mesa "CAOS" "MISTO" 50
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.mentor -eq $null) | Should Be $true
    }
}

# 2026-07-28: achado real em producao -- Test-BetaWithinCap so aplica a
# excecao "SHORT em bear = beta alto e edge" quando recebe Direction=SHORT,
# mas Build-MentorFullContext era chamada com $wlDirection (direcao da
# TRIAGEM), nao a direcao EFETIVA que o Mentor de fato avalia (Mesa tem
# precedencia sobre Triagem, mesma regra de Resolve-MentorDirection). Caso
# real: Triagem=LONG (breadth_long_blocked), Mesa muda pra SHORT -- o
# contexto do beta ficava calculado pra LONG, entao o guard corretivo nunca
# tinha chance de disparar mesmo com o Mentor vetando SHORT incorretamente.
Describe "Invoke-V6Cascade - Direction efetiva passada pro Build-MentorFullContext" {
    BeforeEach {
        $global:CALLED_MESA = $false
        $global:CALLED_MENTOR = $false
        $global:CAPTURED_FULLCTX_DIRECTION = $null
        Set-Mentor "APROVAR" 80 "ok"
    }

    It "Triagem=LONG + Mesa=SHORT -> Direction efetiva passada e SHORT (Mesa vence)" {
        Set-Triagem -Tier "B" -Direction "LONG"; Set-Mesa "FORTE_3" "SHORT" 70
        Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup | Out-Null
        $global:CAPTURED_FULLCTX_DIRECTION | Should Be "SHORT"
    }

    It "Triagem=SHORT + Mesa=LONG -> Direction efetiva passada e LONG (Mesa vence)" {
        Set-Triagem -Tier "B" -Direction "SHORT"; Set-Mesa "FORTE_3" "LONG" 70
        Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup | Out-Null
        $global:CAPTURED_FULLCTX_DIRECTION | Should Be "LONG"
    }

    It "Tier A (sem Mesa) usa Direction da Triagem" {
        Set-Triagem -Tier "A" -Score 85 -Direction "SHORT"
        Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup | Out-Null
        $global:CAPTURED_FULLCTX_DIRECTION | Should Be "SHORT"
    }
}
