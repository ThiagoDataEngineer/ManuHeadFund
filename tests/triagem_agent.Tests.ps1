# triagem_agent.Tests.ps1 -- Pester 3.x -- Invoke-Triagem
# TDD: testes escritos antes da implementacao
# Sem acentos. Sem em-dash. Sem operadores pipeline '&&'.

$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir  = Join-Path (Split-Path $here -Parent) "agents"

# ── Mocks que substituem funcoes externas (definidos ANTES de dot-source) ─────

$global:MOCK_GROQ_RESPONSE = $null   # default: null (= LLM falha, fallback)
$global:MOCK_GROQ_CALLS    = @()

function Invoke-GroqJson {
    param(
        [string]$SystemPrompt, [string]$UserContent,
        [string]$Model, [int]$MaxTokens, [double]$Temperature,
        [int]$MaxRetries, [string]$Agent
    )
    $global:MOCK_GROQ_CALLS += [PSCustomObject]@{
        agent = $Agent
        model = $Model
        userContent = $UserContent
    }
    return $global:MOCK_GROQ_RESPONSE
}

# Knowledge retriever mock: retorna array vazio por default (override por teste)
$global:MOCK_KB_RESPONSE = @()
function Get-RelevantKnowledge {
    param([string[]]$Tags, [int]$MaxChunks = 3)
    return $global:MOCK_KB_RESPONSE
}

. (Join-Path $agentsDir "triagem_agent.ps1")


# ── Helpers para construir Context ────────────────────────────────────────────

function New-MockContext {
    param(
        [int]$ScannerScore = 70,
        [string]$MacroBias = "NEUTRAL",
        [int]$SeasonalMomentScore = 70,
        [string]$DayOfWeek = "Wednesday",
        [string]$MarketTier = "btc",
        [int]$SeasonalScoreAdjustment = 0,
        [double]$PairChange24h = 0.0    # v3 2026-05-16: regime per-pair
    )
    return [PSCustomObject]@{
        scanner   = [PSCustomObject]@{ score = $ScannerScore; change = $PairChange24h }
        prescreen = [PSCustomObject]@{ passed = $true; reason = "OK" }
        macro     = [PSCustomObject]@{ macro_bias = $MacroBias; score = 50 }
        seasonal  = [PSCustomObject]@{
            momentScore     = $SeasonalMomentScore
            dayOfWeek       = $DayOfWeek
            marketTier      = $MarketTier
            scoreAdjustment = $SeasonalScoreAdjustment
        }
    }
}

# ── Setup helper: reset mocks antes de cada bloco que precisa ─────────────────

function Reset-Mocks {
    $global:MOCK_GROQ_RESPONSE = $null
    $global:MOCK_GROQ_CALLS    = @()
    $global:MOCK_KB_RESPONSE   = @()
}


Describe "Invoke-Triagem - contrato de saida obrigatorio" {
    It "Retorna campo tier" {
        Reset-Mocks
        $r = Invoke-Triagem -Market "BTCUSDT" -Context (New-MockContext)
        $r.tier | Should Not BeNullOrEmpty
        ("A","B","C","D" -contains $r.tier) | Should Be $true
    }

    It "Retorna campo razao nao vazio" {
        Reset-Mocks
        $r = Invoke-Triagem -Market "BTCUSDT" -Context (New-MockContext)
        $r.razao | Should Not BeNullOrEmpty
    }

    It "Retorna campo score_predicted entre 0 e 100" {
        Reset-Mocks
        $r = Invoke-Triagem -Market "BTCUSDT" -Context (New-MockContext)
        ($r.score_predicted -ge 0) | Should Be $true
        ($r.score_predicted -le 100) | Should Be $true
    }

    It "Retorna campo flags como array (pode ser vazio)" {
        Reset-Mocks
        $r = Invoke-Triagem -Market "BTCUSDT" -Context (New-MockContext)
        ($r.flags -is [array]) | Should Be $true
    }

    It "Retorna campo knowledge_cited como array (pode ser vazio)" {
        Reset-Mocks
        $r = Invoke-Triagem -Market "BTCUSDT" -Context (New-MockContext)
        ($r.knowledge_cited -is [array]) | Should Be $true
    }

    It "Retorna campo latency_ms numerico" {
        Reset-Mocks
        $r = Invoke-Triagem -Market "BTCUSDT" -Context (New-MockContext)
        ($r.latency_ms -ge 0) | Should Be $true
    }
}


Describe "Invoke-Triagem - regras de tier" {

    BeforeEach {
        # Garante thresholds default (50/60/75) para testes legados; isola contra
        # leak de $global:TRIAGEM_THRESHOLDS de outros test files (override OPT-IN).
        if (Test-Path variable:global:TRIAGEM_THRESHOLDS) {
            Remove-Variable -Name TRIAGEM_THRESHOLDS -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It "tier A: score alto + macro BULLISH + DoW favoravel" {
        Reset-Mocks
        $ctx = New-MockContext -ScannerScore 80 -MacroBias "BULLISH" -DayOfWeek "Monday"
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        $r.tier | Should Be "A"
    }

    It "tier B: score medio + macro NEUTRAL + DoW neutro" {
        Reset-Mocks
        $ctx = New-MockContext -ScannerScore 65 -MacroBias "NEUTRAL" -DayOfWeek "Wednesday"
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        $r.tier | Should Be "B"
    }

    It "tier C: score baixo (50-59)" {
        Reset-Mocks
        $ctx = New-MockContext -ScannerScore 55 -MacroBias "NEUTRAL"
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        $r.tier | Should Be "C"
    }

    It "tier C: macro BEARISH com score medio rebaixa para C" {
        Reset-Mocks
        $ctx = New-MockContext -ScannerScore 65 -MacroBias "BEARISH"
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        ("C","D" -contains $r.tier) | Should Be $true
    }

    It "tier D: score muito baixo (< 50)" {
        Reset-Mocks
        $ctx = New-MockContext -ScannerScore 35 -MacroBias "NEUTRAL"
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        $r.tier | Should Be "D"
    }

    It "tier D: quinta-feira em ALT com flag SKIP_THURSDAY_ALTS=true rebaixa para D" {
        Reset-Mocks
        $global:SKIP_THURSDAY_ALTS = $true
        $ctx = New-MockContext -ScannerScore 70 -MacroBias "NEUTRAL" `
                               -DayOfWeek "Thursday" -MarketTier "alt"
        $r = Invoke-Triagem -Market "PEPEUSDT" -Context $ctx
        $r.tier | Should Be "D"
        $global:SKIP_THURSDAY_ALTS = $false
    }

    It "tier A NAO acontece em Thursday + alt mesmo com score alto (penalidade leve)" {
        Reset-Mocks
        $global:SKIP_THURSDAY_ALTS = $false
        $ctx = New-MockContext -ScannerScore 90 -MacroBias "BULLISH" `
                               -DayOfWeek "Thursday" -MarketTier "alt"
        $r = Invoke-Triagem -Market "PEPEUSDT" -Context $ctx
        ($r.tier -ne "A") | Should Be $true
    }
}


Describe "Invoke-Triagem - robustez com LLM falhando" {
    It "Groq retorna null: fallback com razao deterministica" {
        Reset-Mocks
        $global:MOCK_GROQ_RESPONSE = $null
        $r = Invoke-Triagem -Market "BTCUSDT" -Context (New-MockContext)
        $r.razao | Should Not BeNullOrEmpty
        $r.tier  | Should Not BeNullOrEmpty
    }

    It "Groq retorna objeto sem campos esperados: fallback funciona" {
        Reset-Mocks
        $global:MOCK_GROQ_RESPONSE = [PSCustomObject]@{ outro = "lixo" }
        $r = Invoke-Triagem -Market "BTCUSDT" -Context (New-MockContext)
        $r.razao | Should Not BeNullOrEmpty
        $r.tier  | Should Not BeNullOrEmpty
    }

    It "Groq retorna razao valida: usada no output" {
        Reset-Mocks
        $global:MOCK_GROQ_RESPONSE = [PSCustomObject]@{
            razao = "macro bullish + segunda-feira favorece long"
            flags = @("macro_aligned","monday_strong")
        }
        $r = Invoke-Triagem -Market "BTCUSDT" -Context (New-MockContext -ScannerScore 80 -MacroBias "BULLISH" -DayOfWeek "Monday")
        $r.razao | Should Match "bullish"
    }

    It "Groq retorna flags: incluidas no output" {
        Reset-Mocks
        $global:MOCK_GROQ_RESPONSE = [PSCustomObject]@{
            razao = "ok"
            flags = @("aligned","trending")
        }
        $r = Invoke-Triagem -Market "BTCUSDT" -Context (New-MockContext)
        $r.flags.Count | Should BeGreaterThan 0
    }
}


Describe "Invoke-Triagem - tracking via lib_claude" {
    It "Chama Invoke-GroqJson com Agent='triagem'" {
        Reset-Mocks
        Invoke-Triagem -Market "BTCUSDT" -Context (New-MockContext) | Out-Null
        $global:MOCK_GROQ_CALLS.Count | Should BeGreaterThan 0
        $global:MOCK_GROQ_CALLS[0].agent | Should Be "triagem"
    }

    It "UserContent enviado ao Groq inclui o market" {
        Reset-Mocks
        Invoke-Triagem -Market "ETHUSDT" -Context (New-MockContext) | Out-Null
        $global:MOCK_GROQ_CALLS.Count | Should BeGreaterThan 0
        $global:MOCK_GROQ_CALLS[0].userContent | Should Match "ETHUSDT"
    }

    It "UserContent enviado ao Groq inclui macro_bias" {
        Reset-Mocks
        Invoke-Triagem -Market "BTCUSDT" -Context (New-MockContext -MacroBias "BULLISH") | Out-Null
        $global:MOCK_GROQ_CALLS[0].userContent | Should Match "BULLISH"
    }
}


Describe "Invoke-Triagem - Knowledge retrieval integration" {
    It "knowledge_cited reflete o que Get-RelevantKnowledge retornou" {
        Reset-Mocks
        $global:MOCK_KB_RESPONSE = @(
            [PSCustomObject]@{ source = "BEAR_MARKET.md"; tag = "rebound_trap"; text = "tx" }
        )
        $r = Invoke-Triagem -Market "BTCUSDT" -Context (New-MockContext -MacroBias "BEARISH")
        $r.knowledge_cited.Count | Should BeGreaterThan 0
    }

    It "knowledge_cited tem formato 'source:tag' ou ao menos contem source" {
        Reset-Mocks
        $global:MOCK_KB_RESPONSE = @(
            [PSCustomObject]@{ source = "MENTOR.md"; tag = "livermore"; text = "tx" }
        )
        $r = Invoke-Triagem -Market "BTCUSDT" -Context (New-MockContext)
        $r.knowledge_cited[0] | Should Match "MENTOR\.md"
    }
}


Describe "Invoke-Triagem - edge cases" {
    It "Context com campos faltando nao quebra (graceful)" {
        Reset-Mocks
        $minimal = [PSCustomObject]@{ scanner = [PSCustomObject]@{ score = 50 } }
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $minimal
        $r.tier | Should Not BeNullOrEmpty
    }

    It "Market vazio nao quebra" {
        Reset-Mocks
        $r = Invoke-Triagem -Market "" -Context (New-MockContext)
        $r.tier | Should Not BeNullOrEmpty
    }

    It "Score predicted alinhado com score scanner (proximidade)" {
        Reset-Mocks
        $ctx = New-MockContext -ScannerScore 80
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        # score_predicted nao deve estar absurdamente longe do scanner score
        ([math]::Abs($r.score_predicted - 80) -lt 50) | Should Be $true
    }

    It "Latency reportado (>=0)" {
        Reset-Mocks
        $r = Invoke-Triagem -Market "BTCUSDT" -Context (New-MockContext)
        ($r.latency_ms -ge 0) | Should Be $true
    }
}


# ── Wave 2: Thursday-veto opcional + scanner.score propagation ────────────────
# Bug 1: hoje (quinta) + alt sempre forca Tier D (independe de flag), 100% ABORTAR.
# Bug 2: Triagem usa default 50 quando scanner.score nao chega via Context.

Describe "Invoke-Triagem - Thursday-veto flag (default OFF)" {

    It "Quinta-feira + alt sem flag ($SKIP_THURSDAY_ALTS=$false) NAO forca Tier D" {
        Reset-Mocks
        $global:SKIP_THURSDAY_ALTS = $false
        $ctx = New-MockContext -ScannerScore 70 -MacroBias "NEUTRAL" `
                               -DayOfWeek "Thursday" -MarketTier "alt"
        $r = Invoke-Triagem -Market "PEPEUSDT" -Context $ctx
        ($r.tier -ne "D") | Should Be $true
    }

    It "Quinta-feira + alt com flag ($SKIP_THURSDAY_ALTS=$true) DEVE forcar Tier D" {
        Reset-Mocks
        $global:SKIP_THURSDAY_ALTS = $true
        $ctx = New-MockContext -ScannerScore 70 -MacroBias "NEUTRAL" `
                               -DayOfWeek "Thursday" -MarketTier "alt"
        $r = Invoke-Triagem -Market "PEPEUSDT" -Context $ctx
        $r.tier | Should Be "D"
        $global:SKIP_THURSDAY_ALTS = $false
    }

    It "Quinta-feira + BTC nao e afetado pelo flag (Thursday afeta so alt)" {
        Reset-Mocks
        $global:SKIP_THURSDAY_ALTS = $true
        $ctx = New-MockContext -ScannerScore 70 -MacroBias "NEUTRAL" `
                               -DayOfWeek "Thursday" -MarketTier "btc"
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        ($r.tier -ne "D") | Should Be $true
        $global:SKIP_THURSDAY_ALTS = $false
    }

    It "Quinta-feira + alt com flag OFF e score 80 + BULLISH chega ao menos a Tier B" {
        Reset-Mocks
        $global:SKIP_THURSDAY_ALTS = $false
        $ctx = New-MockContext -ScannerScore 80 -MacroBias "BULLISH" `
                               -DayOfWeek "Thursday" -MarketTier "alt"
        $r = Invoke-Triagem -Market "PEPEUSDT" -Context $ctx
        ("A","B" -contains $r.tier) | Should Be $true
    }

    It "Sexta-feira + alt nunca cai em Thursday-veto (mesmo com flag)" {
        Reset-Mocks
        $global:SKIP_THURSDAY_ALTS = $true
        $ctx = New-MockContext -ScannerScore 70 -MacroBias "NEUTRAL" `
                               -DayOfWeek "Friday" -MarketTier "alt"
        $r = Invoke-Triagem -Market "PEPEUSDT" -Context $ctx
        ($r.tier -ne "D") | Should Be $true
        $global:SKIP_THURSDAY_ALTS = $false
    }
}

Describe "Invoke-Triagem - scanner.score propaga (nao usa default 50)" {

    It "ScannerScore=82 propaga: tier nao deve ser C (default 50 daria C)" {
        Reset-Mocks
        $ctx = New-MockContext -ScannerScore 82 -MacroBias "NEUTRAL" -DayOfWeek "Wednesday"
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        # Com score 82 + macro neutral + DoW favoravel -> deve chegar a A
        # Com default 50, ficaria em C.
        ($r.tier -ne "C") | Should Be $true
    }

    It "ScannerScore=30 propaga: tier deve ser D (default 50 daria C)" {
        Reset-Mocks
        $ctx = New-MockContext -ScannerScore 30 -MacroBias "NEUTRAL"
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        $r.tier | Should Be "D"
    }
}


# ── Wave 2.5: regime + direction propagation ──────────────────────────────────
# Risco 1: Invoke-Triagem precisa retornar regime/direction reais (nao apenas
# tier) para a whitelist gate funcionar end-to-end no cascade.

Describe "Invoke-Triagem - regime e direction (Wave 2.5)" {

    It "Retorna campo regime BULL_STRONG quando macro BULLISH + score >= 75 + change forte" {
        Reset-Mocks
        # v3 2026-05-16: regime usa PairChange24h. +18% = BULL_STRONG independente
        $ctx = New-MockContext -ScannerScore 80 -MacroBias "BULLISH" -DayOfWeek "Monday" -PairChange24h 18.0
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        $r.regime | Should Be "BULL_STRONG"
    }

    It "Retorna campo regime BULL_WEAK quando macro BULLISH + score 50-74" {
        Reset-Mocks
        $ctx = New-MockContext -ScannerScore 65 -MacroBias "BULLISH" -DayOfWeek "Monday"
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        $r.regime | Should Be "BULL_WEAK"
    }

    It "Retorna campo regime BEAR_STRONG quando change <= -8 percent" {
        Reset-Mocks
        # v3 2026-05-16: regime usa PairChange24h. -13% = BEAR_STRONG independente
        $ctx = New-MockContext -ScannerScore 20 -MacroBias "BEARISH" -PairChange24h -13.0
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        $r.regime | Should Be "BEAR_STRONG"
    }

    It "Retorna campo regime BEAR_WEAK quando macro BEARISH + score 30-49" {
        Reset-Mocks
        $ctx = New-MockContext -ScannerScore 40 -MacroBias "BEARISH"
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        $r.regime | Should Be "BEAR_WEAK"
    }

    It "Retorna campo regime TRANSITION_UP quando change +2-5 percent" {
        Reset-Mocks
        # v3 2026-05-16: TRANSITION_UP = change [+2, +5)
        $ctx = New-MockContext -ScannerScore 70 -MacroBias "NEUTRAL" -PairChange24h 3.0
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        $r.regime | Should Be "TRANSITION_UP"
    }

    It "Retorna campo regime SIDEWAYS quando macro NEUTRAL + score 40-59" {
        Reset-Mocks
        $ctx = New-MockContext -ScannerScore 50 -MacroBias "NEUTRAL"
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        $r.regime | Should Be "SIDEWAYS"
    }

    It "Retorna campo direction LONG quando regime e BULL_STRONG" {
        Reset-Mocks
        $ctx = New-MockContext -ScannerScore 80 -MacroBias "BULLISH" -DayOfWeek "Monday"
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        $r.direction | Should Be "LONG"
    }

    It "Retorna campo direction LONG quando regime e BULL_WEAK" {
        Reset-Mocks
        $ctx = New-MockContext -ScannerScore 65 -MacroBias "BULLISH"
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        $r.direction | Should Be "LONG"
    }

    It "Retorna campo direction SHORT quando regime e BEAR_STRONG" {
        Reset-Mocks
        $ctx = New-MockContext -ScannerScore 20 -MacroBias "BEARISH"
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        $r.direction | Should Be "SHORT"
    }

    It "Retorna campo direction SHORT quando regime e BEAR_WEAK" {
        Reset-Mocks
        $ctx = New-MockContext -ScannerScore 40 -MacroBias "BEARISH"
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        $r.direction | Should Be "SHORT"
    }

    It "Retorna direction LONG (default) quando regime e TRANSITION_UP" {
        Reset-Mocks
        $ctx = New-MockContext -ScannerScore 70 -MacroBias "NEUTRAL"
        $r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
        $r.direction | Should Be "LONG"
    }

    It "Regime esta no conjunto valido da whitelist" {
        Reset-Mocks
        $validRegimes = @(
            "BULL_STRONG","BULL_WEAK","SIDEWAYS","TRANSITION_UP",
            "TRANSITION_DOWN","BEAR_WEAK","BEAR_STRONG","CAPITULATION"
        )
        $r = Invoke-Triagem -Market "BTCUSDT" -Context (New-MockContext)
        ($validRegimes -contains $r.regime) | Should Be $true
    }

    It "Direction esta no conjunto valido (LONG ou SHORT)" {
        Reset-Mocks
        $r = Invoke-Triagem -Market "BTCUSDT" -Context (New-MockContext)
        (@("LONG","SHORT") -contains $r.direction) | Should Be $true
    }
}
