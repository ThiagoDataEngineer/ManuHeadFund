# orchestrator_whitelist_integration.Tests.ps1 -- Pester 3.x
# Wave 2: garante que Test-RegimeDirectionAllowed actua como gate no cascade
# entre Triagem e Mesa em Invoke-V6Cascade.
#
# Convencoes:
#   - sem em-dash, sem &&, sem acentos em nomes de teste
#   - DoW BRT: 0=Sunday..6=Saturday
#   - Mode: paper|live propagado via $Context.mode

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Stubs minimos de config (orchestrator usa estes globais via config.ps1)
$global:CLAUDE_MODEL      = "claude-sonnet-4"
$global:CLAUDE_MAX_TOKENS = 4000
$global:CLAUDE_TEMP_TRADE = 0.3
$global:ANTHROPIC_API_KEY = "test-key"
$global:SKIP_THURSDAY_ALTS = $false  # destrava paper

function Write-Host    { param() }
function Write-Warning { param() }

# Carrega o cascade + a whitelist real (NAO mockar a whitelist)
. (Join-Path (Split-Path $here -Parent) "agents\lib_operational_whitelist.ps1")
. (Join-Path (Split-Path $here -Parent) "agents\orchestrator_v6.ps1")

# ── Stubs apos dot-source ────────────────────────────────────────────────────

$global:STUB_TRIAGEM  = $null
$global:STUB_MESA     = $null
$global:STUB_MENTOR   = $null
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

# Helpers de construcao de stubs
function Set-Triagem {
    param([string]$Tier="B",[int]$Score=70,[string]$Razao="ok",
          [string]$Regime="BULL_STRONG",[string]$Direction="LONG")
    $global:STUB_TRIAGEM = [PSCustomObject]@{
        tier             = $Tier
        score_predicted  = $Score
        razao            = $Razao
        regime           = $Regime
        direction        = $Direction
        flags            = @()
        knowledge_cited  = @()
        setup            = $null
    }
}
function Set-Mesa {
    param([string]$Consensus="FORTE_3",[string]$Sinal="LONG",[int]$Avg=70)
    $global:STUB_MESA = [PSCustomObject]@{
        termal=[PSCustomObject]@{sinal=$Sinal;forca=70}
        radar =[PSCustomObject]@{sinal=$Sinal;forca=68}
        lidar =[PSCustomObject]@{sinal=$Sinal;forca=72}
        consensus=$Consensus; sinal_consenso=$Sinal; score_avg=$Avg; setup=$null
    }
}
function Set-Mentor {
    param([string]$Decision="APROVAR",[int]$Conf=80,[string]$Msg="ok")
    $global:STUB_MENTOR = [PSCustomObject]@{
        decision=$Decision; confianca=$Conf; mentor_mensagem=$Msg; knowledge_cited=@()
    }
}

function New-IntegrationContext {
    param(
        [string]$Mode="paper",
        [int]$DayOfWeekBRT=3,    # Wednesday default
        [int]$ScannerScore=70,
        [string]$MacroBias="NEUTRAL"
    )
    return [PSCustomObject]@{
        mode           = $Mode
        day_of_week_brt= $DayOfWeekBRT
        scanner_score  = $ScannerScore
        scanner        = [PSCustomObject]@{ score = $ScannerScore }
        macro          = [PSCustomObject]@{ macro_bias = $MacroBias }
        seasonal       = [PSCustomObject]@{ dayOfWeek = "Wednesday"; marketTier = "btc" }
    }
}

$setup = [PSCustomObject]@{ entry=100; stop=95; target=120; rr=4 }


Describe "Wave2 whitelist gate - EXECUTE em ambos modos" {
    BeforeEach {
        $global:CALLED_MESA = $false
        $global:CALLED_MENTOR = $false
        Set-Mentor "APROVAR" 80 "ok"
    }

    It "BULL_STRONG + LONG + live -> executa cascade completo" {
        Set-Triagem -Tier "B" -Regime "BULL_STRONG" -Direction "LONG"
        Set-Mesa "FORTE_3" "LONG" 70
        $ctx = New-IntegrationContext -Mode "live" -DayOfWeekBRT 3
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.decisao) | Should Be "EXECUTAR"
        ($out.telegramFire) | Should Be $true
    }

    It "BULL_STRONG + LONG + paper -> executa cascade completo" {
        Set-Triagem -Tier "B" -Regime "BULL_STRONG" -Direction "LONG"
        Set-Mesa "FORTE_3" "LONG" 70
        $ctx = New-IntegrationContext -Mode "paper" -DayOfWeekBRT 3
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.decisao) | Should Be "EXECUTAR"
        ($out.telegramFire) | Should Be $true
    }

    It "TRANSITION_UP + LONG + Monday BRT + live -> execute" {
        Set-Triagem -Tier "B" -Regime "TRANSITION_UP" -Direction "LONG"
        Set-Mesa "FORTE_3" "LONG" 70
        $ctx = New-IntegrationContext -Mode "live" -DayOfWeekBRT 1
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.decisao) | Should Be "EXECUTAR"
    }
}

Describe "Wave2 whitelist gate - SKIP em live, OBSERVE em paper" {
    BeforeEach {
        $global:CALLED_MESA = $false
        $global:CALLED_MENTOR = $false
        Set-Mentor "APROVAR" 80 "ok"
    }

    It "SHORT em qualquer regime + live -> ABORTAR com razao whitelist:skip" {
        Set-Triagem -Tier "B" -Regime "BULL_STRONG" -Direction "SHORT"
        Set-Mesa "FORTE_3" "SHORT" 70
        $ctx = New-IntegrationContext -Mode "live"
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.decisao) | Should Be "ABORTAR"
        ($out.motivo -match "whitelist:skip") | Should Be $true
        ($global:CALLED_MESA)   | Should Be $false
        ($global:CALLED_MENTOR) | Should Be $false
    }

    It "SHORT em SIDEWAYS + paper -> cascade roda MAS telegramFire=false (observe, v3)" {
        Set-Triagem -Tier "B" -Regime "SIDEWAYS" -Direction "SHORT"
        Set-Mesa "FORTE_3" "SHORT" 70
        $ctx = New-IntegrationContext -Mode "paper"
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.decisao) | Should Be "EXECUTAR"
        ($out.telegramFire) | Should Be $false
    }

    It "SIDEWAYS + LONG -> ABORTAR razao whitelist:skip em ambos modos" {
        Set-Triagem -Tier "B" -Regime "SIDEWAYS" -Direction "LONG"
        $ctx = New-IntegrationContext -Mode "paper"
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.decisao) | Should Be "ABORTAR"
        ($out.motivo -match "whitelist:skip") | Should Be $true
    }

    It "TRANSITION_UP + LONG + Tuesday BRT + paper -> observe (executa, sem tg)" {
        Set-Triagem -Tier "B" -Regime "TRANSITION_UP" -Direction "LONG"
        Set-Mesa "FORTE_3" "LONG" 70
        $ctx = New-IntegrationContext -Mode "paper" -DayOfWeekBRT 2
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.decisao) | Should Be "EXECUTAR"
        ($out.telegramFire) | Should Be $false
    }

    It "TRANSITION_UP + LONG + Tuesday BRT + live -> ABORTAR (fora da janela Mon)" {
        Set-Triagem -Tier "B" -Regime "TRANSITION_UP" -Direction "LONG"
        $ctx = New-IntegrationContext -Mode "live" -DayOfWeekBRT 2
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.decisao) | Should Be "ABORTAR"
        ($out.motivo -match "whitelist:skip") | Should Be $true
    }

    It "BULL_WEAK + LONG + paper -> observe (executa, sem tg)" {
        Set-Triagem -Tier "B" -Regime "BULL_WEAK" -Direction "LONG"
        Set-Mesa "FORTE_3" "LONG" 70
        $ctx = New-IntegrationContext -Mode "paper"
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.decisao) | Should Be "EXECUTAR"
        ($out.telegramFire) | Should Be $false
    }

    It "BULL_WEAK + LONG + live -> ABORTAR (blacklist)" {
        Set-Triagem -Tier "B" -Regime "BULL_WEAK" -Direction "LONG"
        $ctx = New-IntegrationContext -Mode "live"
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.decisao) | Should Be "ABORTAR"
        ($out.motivo -match "whitelist:skip") | Should Be $true
    }

    It "BEAR_STRONG + LONG + live -> skip" {
        Set-Triagem -Tier "B" -Regime "BEAR_STRONG" -Direction "LONG"
        $ctx = New-IntegrationContext -Mode "live"
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.decisao) | Should Be "ABORTAR"
        ($out.motivo -match "whitelist:skip") | Should Be $true
    }

    It "BEAR_STRONG + SHORT + live -> cascade roda (v3 bidirecional habilitado)" {
        Set-Triagem -Tier "B" -Regime "BEAR_STRONG" -Direction "SHORT"
        Set-Mesa "FORTE_3" "SHORT" 70
        $ctx = New-IntegrationContext -Mode "live"
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        # v3: SHORT em BEAR_STRONG agora vai a Mesa/Mentor (nao mais skip imediato)
        ($out.motivo -notmatch "whitelist:skip") | Should Be $true
    }
}

Describe "Wave2 whitelist gate - razao e fluxo" {
    BeforeEach {
        $global:CALLED_MESA = $false
        $global:CALLED_MENTOR = $false
        Set-Mentor "APROVAR" 80 "ok"
    }

    It "razao do skip contem regime e direction" {
        Set-Triagem -Tier "B" -Regime "SIDEWAYS" -Direction "LONG"
        $ctx = New-IntegrationContext -Mode "live"
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.motivo -match "SIDEWAYS") | Should Be $true
        ($out.motivo -match "LONG") | Should Be $true
    }

    It "observe paper preserva triagem/mesa/mentor no retorno" {
        Set-Triagem -Tier "B" -Regime "BULL_WEAK" -Direction "LONG"
        Set-Mesa "FORTE_3" "LONG" 70
        $ctx = New-IntegrationContext -Mode "paper"
        $out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($out.triagem) | Should Not BeNullOrEmpty
        ($out.mesa)    | Should Not BeNullOrEmpty
        ($out.mentor)  | Should Not BeNullOrEmpty
    }

    It "skip live nao chama Mesa nem Mentor (curto-circuito antes da Mesa)" {
        Set-Triagem -Tier "B" -Regime "BEAR_WEAK" -Direction "LONG"
        $ctx = New-IntegrationContext -Mode "live"
        $null = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup
        ($global:CALLED_MESA)   | Should Be $false
        ($global:CALLED_MENTOR) | Should Be $false
    }
}

Describe "Get-DayOfWeekBRT helper" {
    It "Converte UTC para BRT (UTC-3) e retorna 0..6 com 0=Sunday" {
        # 2026-05-14 03:00 UTC = 2026-05-14 00:00 BRT = Thursday (DoW=4)
        $utc = [DateTime]::SpecifyKind([DateTime]"2026-05-14T03:00:00", [DateTimeKind]::Utc)
        $dow = Get-DayOfWeekBRT -Utc $utc
        $dow | Should Be 4
    }

    It "Domingo BRT retorna 0" {
        # 2026-05-17 03:00 UTC = 2026-05-17 00:00 BRT = Sunday
        $utc = [DateTime]::SpecifyKind([DateTime]"2026-05-17T03:00:00", [DateTimeKind]::Utc)
        $dow = Get-DayOfWeekBRT -Utc $utc
        $dow | Should Be 0
    }

    It "Segunda BRT retorna 1" {
        # 2026-05-18 03:00 UTC = 2026-05-18 00:00 BRT
        $utc = [DateTime]::SpecifyKind([DateTime]"2026-05-18T03:00:00", [DateTimeKind]::Utc)
        $dow = Get-DayOfWeekBRT -Utc $utc
        $dow | Should Be 1
    }
}
