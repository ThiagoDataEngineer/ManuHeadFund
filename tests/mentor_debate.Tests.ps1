# mentor_debate.Tests.ps1 -- Pester 3.x
# Contrato: Invoke-MentorDebate(Market, TriagemResult, MesaResult, Setup, [KnowledgeContext])
#   -> { decision="APROVAR"|"VETAR"; confianca=0-100; mentor_mensagem; knowledge_cited[] }
# Stub: Invoke-ClaudeJson e Track-ClaudeUsage para zero IO real.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Stubs de config minimos
$global:CLAUDE_MODEL       = "claude-sonnet-4"
$global:CLAUDE_MAX_TOKENS  = 4000
$global:CLAUDE_TEMP_TRADE  = 0.3
$global:ANTHROPIC_API_KEY  = "test-key"

function Write-Host    { param() }
function Write-Warning { param() }

# Stub Claude antes de dot-source para nao chamar API real
$global:MOCK_MENTOR_RESPONSE = $null
$global:LAST_MENTOR_AGENT    = ""
$global:LAST_MENTOR_PROMPT   = ""
$global:LAST_MENTOR_MAXTOK   = 0

. "$here\..\agents\mentor_agent.ps1"

# Re-stub APOS dot-source -- mentor_agent carrega lib_claude que define as funcoes reais
# Sem 'global:' -- script scope (mesmo escopo dos dot-sources) sobrepoe corretamente
function Invoke-Claude {
    param($SystemPrompt,$UserContent,$Model,$MaxTokens,$Temperature,$Agent)
    return ""
}
function Invoke-ClaudeJson {
    param($SystemPrompt,$UserContent,$Model,$MaxTokens,$Temperature,$MaxRetries,$Agent)
    $global:LAST_MENTOR_PROMPT = $UserContent
    $global:LAST_MENTOR_AGENT  = $Agent
    $global:LAST_MENTOR_MAXTOK = $MaxTokens
    return $global:MOCK_MENTOR_RESPONSE
}
# 2026-05-16: MentorAgent agora usa Invoke-MentorCascade (Anthropic->Groq->Gemini).
# Stub retorna JSON text (cascade retorna texto, agent parseia).
function Invoke-MentorCascade {
    param($SystemPrompt,$UserContent,$AnthropicModel,$MaxTokens,$Temperature,$Agent)
    $global:LAST_MENTOR_PROMPT = $UserContent
    $global:MENTOR_SYSTEM_PROMPT_USED = $SystemPrompt
    $global:LAST_MENTOR_AGENT  = $Agent
    $global:LAST_MENTOR_MAXTOK = $MaxTokens
    if ($null -eq $global:MOCK_MENTOR_RESPONSE) { return $null }
    return ($global:MOCK_MENTOR_RESPONSE | ConvertTo-Json -Depth 10 -Compress)
}
function Track-ClaudeUsage { param() }

# Helpers de construcao
function New-Triagem {
    param([string]$Tier="B",[int]$Score=65,[string]$Razao="")
    [PSCustomObject]@{ tier=$Tier; razao=$Razao; score_predicted=$Score; flags=@(); knowledge_cited=@() }
}
function New-Mesa {
    param([string]$Consensus="FORTE_3",[string]$Sinal="LONG",[int]$Avg=70)
    [PSCustomObject]@{
        termal=[PSCustomObject]@{sinal=$Sinal;forca=70;justificativa="t"}
        radar =[PSCustomObject]@{sinal=$Sinal;forca=68;justificativa="r"}
        lidar =[PSCustomObject]@{sinal=$Sinal;forca=72;justificativa="l"}
        consensus=$Consensus; sinal_consenso=$Sinal; score_avg=$Avg
    }
}
function New-Setup {
    param([double]$Entry=100,[double]$Stop=95,[double]$Target=120,[double]$Rr=4)
    [PSCustomObject]@{ entry=$Entry; stop=$Stop; target=$Target; rr=$Rr }
}

Describe "Invoke-MentorDebate - contrato basico" {

    It "retorna APROVAR quando Claude responde APROVAR" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=80
            mentor_mensagem="Setup limpo, Mesa unida, Tudor Jones aprovaria"
            knowledge_cited=@("MENTOR.md:tudor_risk_1pct")
        }
        $out = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem) `
            -MesaResult (New-Mesa) -Setup (New-Setup) -KnowledgeContext "mock"
        ($out.decision) | Should Be "APROVAR"
        ($out.confianca) | Should Be 80
    }

    It "retorna VETAR quando Claude responde VETAR" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="VETAR"; confianca=30
            mentor_mensagem="Macro contrario, FOMO classico"
            knowledge_cited=@("MENTOR.md:livermore_no_fight_trend")
        }
        $out = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "C") `
            -MesaResult (New-Mesa -Consensus "MEDIO_2" -Avg 60) -Setup (New-Setup) -KnowledgeContext "mock"
        ($out.decision) | Should Be "VETAR"
    }

    It "VETAR de seguranca quando Claude retorna null (Mentor indisponivel)" {
        $global:MOCK_MENTOR_RESPONSE = $null
        $out = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem) `
            -MesaResult (New-Mesa) -Setup (New-Setup) -KnowledgeContext "mock"
        ($out.decision) | Should Be "VETAR"
        ($out.confianca) | Should Be 0
    }

    It "mentor_mensagem nunca vazia mesmo em fallback" {
        $global:MOCK_MENTOR_RESPONSE = $null
        $out = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem) `
            -MesaResult (New-Mesa) -Setup (New-Setup) -KnowledgeContext "mock"
        ($out.mentor_mensagem.Length -gt 0) | Should Be $true
    }

    It "knowledge_cited sempre array (mesmo vazio)" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=70; mentor_mensagem="ok"; knowledge_cited=$null
        }
        $out = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem) `
            -MesaResult (New-Mesa) -Setup (New-Setup) -KnowledgeContext "mock"
        ($out.knowledge_cited -is [Array]) | Should Be $true
    }

    It "passa -Agent mentor para tracking de custo" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=70; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem) `
            -MesaResult (New-Mesa) -Setup (New-Setup) -KnowledgeContext "mock"
        ($global:LAST_MENTOR_AGENT) | Should Be "mentor"
    }

    It "prompt compacto: max tokens output <= 500 (custo baixo)" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=70; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem) `
            -MesaResult (New-Mesa) -Setup (New-Setup) -KnowledgeContext "mock"
        ($global:LAST_MENTOR_MAXTOK -le 500) | Should Be $true
    }

    It "prompt menciona tier da Triagem" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=70; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "A" -Score 85) `
            -MesaResult $null -Setup (New-Setup) -KnowledgeContext "mock"
        ($global:LAST_MENTOR_PROMPT -match "A") | Should Be $true
    }

    It "Mesa null (Tier A direto) - prompt indica skip de Mesa" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=70; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "A") `
            -MesaResult $null -Setup (New-Setup) -KnowledgeContext "mock"
        ($global:LAST_MENTOR_PROMPT -match "(Mesa|mesa).*(nao|skip|pulada|Tier A)") | Should Be $true
    }

    It "retorna PSCustomObject com 4 campos contratuais" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=70; mentor_mensagem="ok"
            knowledge_cited=@("MENTOR.md:x")
        }
        $out = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem) `
            -MesaResult (New-Mesa) -Setup (New-Setup) -KnowledgeContext "mock"
        ($out.PSObject.Properties.Name -contains "decision")       | Should Be $true
        ($out.PSObject.Properties.Name -contains "confianca")      | Should Be $true
        ($out.PSObject.Properties.Name -contains "mentor_mensagem")| Should Be $true
        ($out.PSObject.Properties.Name -contains "knowledge_cited")| Should Be $true
    }
}


# =============================================================================
# Fase 1A: FullContext + mode-aware (2026-05-20)
# Mentor recebe estrutura rica com FQS/beta/historical/regime/drawdown/gates
# pra parar de vetar por ignorancia. Backward-compat: sem FullContext, prompt
# atual mantido.
# =============================================================================

function New-FullContext {
    param(
        [string]$Mode="TIER_A_LIVE",
        [int]$Fqs=6,
        [string]$FqsCategory="BLUE_CHIP",
        [double]$BetaAsset=1.0,
        [double]$BetaPortfolioAfter=1.1,
        [double]$Dsr=0.95,
        [int]$NTrades=113,
        [double]$Sharpe30d=3.8,
        [string]$Phase="phase_3_bear",
        [string]$RegimeBias="TRANSITION->BEAR_WEAK",
        [double]$DdVsPeakPct=-3.2,
        [int]$FlagStreak=0,
        [string]$DdLevel="OK",
        [int]$GatesPassed=15,
        [int]$GatesTotal=15
    )
    [PSCustomObject]@{
        mode = $Mode
        fqs = [PSCustomObject]@{ score=$Fqs; category=$FqsCategory }
        beta = [PSCustomObject]@{ asset=$BetaAsset; portfolio_after=$BetaPortfolioAfter }
        historical = [PSCustomObject]@{ dsr=$Dsr; n_trades=$NTrades; sharpe_30d=$Sharpe30d }
        regime = [PSCustomObject]@{ phase=$Phase; bias=$RegimeBias }
        drawdown = [PSCustomObject]@{ vs_peak_pct=$DdVsPeakPct; flag_streak=$FlagStreak; level=$DdLevel }
        gates = [PSCustomObject]@{ passed=$GatesPassed; total=$GatesTotal }
    }
}


Describe "Invoke-MentorDebate FullContext" {

    It "FullContext.fqs aparece no prompt (BLUE_CHIP visivel)" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=85; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "A") `
            -MesaResult $null -Setup (New-Setup) -FullContext (New-FullContext)
        ($global:LAST_MENTOR_PROMPT -match "BLUE_CHIP|fqs=6") | Should Be $true
    }

    It "FullContext.beta portfolio_after aparece no prompt" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=80; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $ctx = New-FullContext -BetaPortfolioAfter 1.32
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "A") `
            -MesaResult $null -Setup (New-Setup) -FullContext $ctx
        ($global:LAST_MENTOR_PROMPT -match "1\.32|portfolio") | Should Be $true
    }

    It "FullContext.historical DSR + n_trades visiveis" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=85; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $ctx = New-FullContext -Dsr 0.98 -NTrades 113
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "A") `
            -MesaResult $null -Setup (New-Setup) -FullContext $ctx
        ($global:LAST_MENTOR_PROMPT -match "0\.98|113|dsr|trades") | Should Be $true
    }

    It "FullContext.regime phase + bias no prompt" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=70; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $ctx = New-FullContext -Phase "phase_3_bear" -RegimeBias "BEAR_WEAK"
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem) `
            -MesaResult (New-Mesa) -Setup (New-Setup) -FullContext $ctx
        ($global:LAST_MENTOR_PROMPT -match "phase_3_bear|BEAR_WEAK") | Should Be $true
    }

    It "FullContext.drawdown flag_streak 3+ alerta no prompt" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="VETAR"; confianca=20; mentor_mensagem="streak"; knowledge_cited=@()
        }
        $ctx = New-FullContext -FlagStreak 3 -DdLevel "FLAG"
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "A") `
            -MesaResult $null -Setup (New-Setup) -FullContext $ctx
        ($global:LAST_MENTOR_PROMPT -match "streak.*3|FLAG") | Should Be $true
    }

    It "FullContext.gates passed/total no prompt" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=80; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $ctx = New-FullContext -GatesPassed 14 -GatesTotal 15
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem) `
            -MesaResult (New-Mesa) -Setup (New-Setup) -FullContext $ctx
        ($global:LAST_MENTOR_PROMPT -match "14/15|gates") | Should Be $true
    }

    It "FullContext.mode TIER_A_LIVE no prompt (Mentor sabe que skip-debate eh by design)" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=85; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $ctx = New-FullContext -Mode "TIER_A_LIVE"
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "A") `
            -MesaResult $null -Setup (New-Setup) -FullContext $ctx
        ($global:LAST_MENTOR_PROMPT -match "TIER_A_LIVE|mode") | Should Be $true
    }

    It "FullContext.mode GEM no prompt (Mentor aplica tolerancia GEM)" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=70; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $ctx = New-FullContext -Mode "GEM" -Fqs 2 -FqsCategory "SPECULATIVE" -NTrades 0 -Dsr 0
        $null = Invoke-MentorDebate -Market "PEPEUSDT" -TriagemResult (New-Triagem -Tier "C") `
            -MesaResult $null -Setup (New-Setup) -FullContext $ctx
        ($global:LAST_MENTOR_PROMPT -match "GEM") | Should Be $true
    }

    It "Backward-compat: sem FullContext, prompt mantem campos antigos" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=70; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "B") `
            -MesaResult (New-Mesa) -Setup (New-Setup) -KnowledgeContext "rag-text"
        ($global:LAST_MENTOR_PROMPT.Length -gt 0) | Should Be $true
        # Sem FullContext, prompt nao quebra
        ($global:LAST_MENTOR_PROMPT -notmatch "FullContext|null-context") | Should Be $true
    }

    It "Token budget: prompt total <=1500 chars com FullContext completo (cost-aware)" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=70; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem) `
            -MesaResult (New-Mesa) -Setup (New-Setup) -FullContext (New-FullContext) `
            -KnowledgeContext "short rag text"
        # ~4 chars/token => 1500 chars ~ 375 tokens prompt. Permite +400 output. Total ~775 in+out.
        ($global:LAST_MENTOR_PROMPT.Length -le 1500) | Should Be $true
    }

    It "Mesa.confluencias agregadas das 3 drones aparecem no prompt (root cause veto 2026-05-20)" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=80; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $mesa = [PSCustomObject]@{
            termal = [PSCustomObject]@{sinal="LONG";forca=70;justificativa="t";confluencias=@("EMA9>EMA21","ADX=28")}
            radar  = [PSCustomObject]@{sinal="LONG";forca=68;justificativa="r";confluencias=@("DXY_down","F&G=greed")}
            lidar  = [PSCustomObject]@{sinal="LONG";forca=72;justificativa="l";confluencias=@("R:R=5","vol_ok")}
            consensus="FORTE_3"; sinal_consenso="LONG"; score_avg=70
        }
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "B") `
            -MesaResult $mesa -Setup (New-Setup) -KnowledgeContext "mock"
        # Mentor deve VER as 6 confluencias agregadas
        ($global:LAST_MENTOR_PROMPT -match "EMA9>EMA21|ADX|DXY") | Should Be $true
    }

    It "Mesa sem confluencias: prompt indica explicitamente (Mentor sabe que faltou)" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="VETAR"; confianca=20; mentor_mensagem="sem confluencias"; knowledge_cited=@()
        }
        $mesa = [PSCustomObject]@{
            termal = [PSCustomObject]@{sinal="LONG";forca=70;justificativa="t";confluencias=@()}
            radar  = [PSCustomObject]@{sinal="LONG";forca=68;justificativa="r";confluencias=@()}
            lidar  = [PSCustomObject]@{sinal="LONG";forca=72;justificativa="l";confluencias=@()}
            consensus="FORTE_3"; sinal_consenso="LONG"; score_avg=70
        }
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "B") `
            -MesaResult $mesa -Setup (New-Setup) -KnowledgeContext "mock"
        # 2026-05-20 PM refino: linguagem neutra "N/A" em vez de [ALERTA]
        ($global:LAST_MENTOR_PROMPT -match "confluencias=N/A|drone.silent|sem.*confluencia") | Should Be $true
    }

    It "TIPO A fix: Mesa skip Tier A NAO contem trigger word 'pulada/pulou' no prompt" {
        # 2026-05-20 hallucination fix: LLM ecoava 'Mesa pulou debate' como veto
        # Solucao: remover palavra do fallback string
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=80; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "A" -Score 85) `
            -MesaResult $null -Setup (New-Setup) -KnowledgeContext "mock"
        ($global:LAST_MENTOR_PROMPT -notmatch "pulada|pulou") | Should Be $true
        # Mas deve indicar que Tier A skip eh by design
        ($global:LAST_MENTOR_PROMPT -match "NAO_APLICAVEL|pre.?validad|by.?design") | Should Be $true
    }

    It "TIPO C fix: Mesa confluencias vazias usam linguagem neutra (sem [ALERTA])" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=70; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $mesa = [PSCustomObject]@{
            termal = [PSCustomObject]@{sinal="LONG";forca=70;justificativa="t";confluencias=@()}
            radar  = [PSCustomObject]@{sinal="LONG";forca=68;justificativa="r";confluencias=@()}
            lidar  = [PSCustomObject]@{sinal="LONG";forca=72;justificativa="l";confluencias=@()}
            consensus="FORTE_3"; sinal_consenso="LONG"; score_avg=70
        }
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "B") `
            -MesaResult $mesa -Setup (New-Setup) -KnowledgeContext "mock"
        # Sem palavra alarmante
        ($global:LAST_MENTOR_PROMPT -notmatch "ALERTA|nao documentou") | Should Be $true
        # Mas indica drone silent
        ($global:LAST_MENTOR_PROMPT -match "N/A|drone.silent|peso reduzido") | Should Be $true
    }

    It "TIPO B fix: KnowledgeContext vazio NAO injeta header KNOWLEDGE: em branco" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=70; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "B") `
            -MesaResult (New-Mesa) -Setup (New-Setup) -KnowledgeContext ""
        # Nao deve ter header KNOWLEDGE: seguido de linha vazia
        ($global:LAST_MENTOR_PROMPT -notmatch "KNOWLEDGE:\s*\n\s*\n") | Should Be $true
    }

    It "Mesa.degraded=true aparece no prompt (Mentor sabe que decisao eh com info parcial)" {
        # 2026-05-20 PM: antes Mesa.degraded vinha mas Mentor nao via -> decidia com info
        # parcial sem saber. Bug detectado em analise profunda v3.
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="VETAR"; confianca=30; mentor_mensagem="degraded"; knowledge_cited=@()
        }
        $mesa = [PSCustomObject]@{
            termal = [PSCustomObject]@{sinal="LONG";forca=70;justificativa="t";confluencias=@("c1")}
            radar  = [PSCustomObject]@{sinal="LONG";forca=68;justificativa="r";confluencias=@("c2")}
            lidar  = [PSCustomObject]@{sinal="LONG";forca=72;justificativa="l";confluencias=@("c3")}
            consensus="MEDIO_2"; sinal_consenso="LONG"; score_avg=70; degraded=$true
        }
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "B") `
            -MesaResult $mesa -Setup (New-Setup) -KnowledgeContext "mock"
        ($global:LAST_MENTOR_PROMPT -match "degraded|info parcial|drone falhou") | Should Be $true
    }

    It "Mesa.degraded=false (saudavel) NAO injeta warning de degradacao" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=80; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $mesa = [PSCustomObject]@{
            termal = [PSCustomObject]@{sinal="LONG";forca=70;justificativa="t";confluencias=@("c1")}
            radar  = [PSCustomObject]@{sinal="LONG";forca=68;justificativa="r";confluencias=@("c2")}
            lidar  = [PSCustomObject]@{sinal="LONG";forca=72;justificativa="l";confluencias=@("c3")}
            consensus="FORTE_3"; sinal_consenso="LONG"; score_avg=70; degraded=$false
        }
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "B") `
            -MesaResult $mesa -Setup (New-Setup) -KnowledgeContext "mock"
        ($global:LAST_MENTOR_PROMPT -notmatch "DEGRADED|info parcial") | Should Be $true
    }

    It "FQS proeminente no prompt: linha unica DESTACADA quando presente (anti-hallucination 'FQS nao declarado')" {
        # 2026-05-20 PM2: DYDX/CHZ tinham FQS=5/4 no registry, Build-MentorFullContext populava,
        # mas LLM citava "FQS nao declarado". Hipotese: FQS perdido entre demais ctx lines.
        # Fix: FQS no inicio do CONTEXTO bloco + uppercase pra unmissable.
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=80; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $ctx = New-FullContext -Fqs 5 -FqsCategory "QUALITY"
        $null = Invoke-MentorDebate -Market "DYDXUSDT" -TriagemResult (New-Triagem -Tier "B") `
            -MesaResult (New-Mesa) -Setup (New-Setup) -FullContext $ctx
        # FQS deve estar no prompt em formato facil de ver
        ($global:LAST_MENTOR_PROMPT -match "FQS=5/7\s*QUALITY|FQS=5") | Should Be $true
    }

    It "FQS=N/A_no_registry quando market nao no registry (em vez de skipar field)" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="VETAR"; confianca=20; mentor_mensagem="ok"; knowledge_cited=@()
        }
        # Build-MentorFullContext devolve fqs com score=$null + category=N/A_no_registry
        $ctx = [PSCustomObject]@{
            mode = "TIER_B_PAPER"
            fqs = [PSCustomObject]@{ score = $null; category = "N/A_no_registry"; reason = "market_not_in_registry" }
        }
        $null = Invoke-MentorDebate -Market "XCHUSDT" -TriagemResult (New-Triagem -Tier "B") `
            -MesaResult (New-Mesa) -Setup (New-Setup) -FullContext $ctx
        ($global:LAST_MENTOR_PROMPT -match "FQS=N/A_no_registry|fqs.*indispon") | Should Be $true
    }

    It "System prompt proibe explicitamente 'FQS nao declarado' quando ctx tem FQS" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=80; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $null = Invoke-MentorDebate -Market "DASHUSDT" -TriagemResult (New-Triagem -Tier "B") `
            -MesaResult (New-Mesa) -Setup (New-Setup) -FullContext (New-FullContext -Fqs 4 -FqsCategory "QUALITY")
        # System prompt deve conter regra explicita anti-hallucination FQS
        ($global:MENTOR_SYSTEM_PROMPT_USED -match "FQS.*nao.*declarad|FQS.*missing|NUNCA.*FQS") | Should Be $true
    }

    It "TIER_A_PAPER mode: Mesa skip permitido (Tier A by design) + paper-only (whitelist observe)" {
        # 2026-05-20 PM6: bug semantico fix -- triagem.tier=A + wl.tier=observe NAO eh
        # mutuamente exclusivo. Mode TIER_A_PAPER significa "Tier A quality MAS regime
        # current (BULL_WEAK/etc) limita pra paper". Mesa skip permitido, mas mode signals paper.
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=85; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $ctx = New-FullContext -Mode "TIER_A_PAPER" -Fqs 6 -FqsCategory "BLUE_CHIP"
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "A" -Score 92) `
            -MesaResult $null -Setup (New-Setup) -FullContext $ctx
        # Prompt deve indicar TIER_A_PAPER explicitamente
        ($global:LAST_MENTOR_PROMPT -match "TIER_A_PAPER") | Should Be $true
    }

    It "System prompt menciona TIER_A_PAPER (regime limita Tier A pra paper)" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=85; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $null = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "A") `
            -MesaResult $null -Setup (New-Setup) -FullContext (New-FullContext -Mode "TIER_A_PAPER")
        ($global:MENTOR_SYSTEM_PROMPT_USED -match "TIER_A_PAPER") | Should Be $true
    }

    It "FullContext null/missing fields: nao quebra, usa graceful skip" {
        $global:MOCK_MENTOR_RESPONSE = [PSCustomObject]@{
            decision="APROVAR"; confianca=70; mentor_mensagem="ok"; knowledge_cited=@()
        }
        $partial = [PSCustomObject]@{ mode="TIER_A_LIVE"; fqs=[PSCustomObject]@{score=6; category="BLUE_CHIP"} }
        $out = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult (New-Triagem -Tier "A") `
            -MesaResult $null -Setup (New-Setup) -FullContext $partial
        $out.decision | Should Be "APROVAR"
    }
}
