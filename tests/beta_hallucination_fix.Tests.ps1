# beta_hallucination_fix.Tests.ps1 -- TDD 2026-05-28
#
# Fix 1: LLM nao pode escrever "viola BLOCK" quando beta < cap_block (erro matematico).
#   Regra adicionada em lib_mentor_rules.Get-MentorAntiHallucinationRules (regra 6)
#   e em mentor_agent.ps1 MENTOR_DEBATE_SYSTEM (regra 5).
#
# Fix 2: BETA_CAP_PER_PHASE_ENABLED=1 ativa caps dinamicos em lib_promotion_gates.
#   bear phase: BLOCK=1.4 (nao 1.2 default). PENDLE beta=1.38 = WARN, nao BLOCK.
#
# Pester 3.x. Zero IO real.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

. (Join-Path $root "agents\lib_mentor_rules.ps1")
. (Join-Path $root "agents\lib_beta_cap_per_phase.ps1")
. (Join-Path $root "agents\lib_mentor_hallucination_detector.ps1")

# ─── Fix 1: regra anti-hallucination beta no system prompt ───────────────────

Describe "Fix1 - Get-MentorAntiHallucinationRules contem regra beta matematica" {

    It "regra 6 presente: menciona comparacao numerica beta vs cap_block" {
        $rules = Get-MentorAntiHallucinationRules
        ($rules -match "BETA.*MATEMATICO|beta.*compare|compare.*numeri") | Should Be $true
    }

    It "regra proibe 'viola BLOCK' quando beta < cap_block" {
        $rules = Get-MentorAntiHallucinationRules
        ($rules -match "NUNCA.*viola BLOCK.*beta.*cap_block|viola BLOCK.*quando beta") | Should Be $true
    }

    It "regra fornece exemplo concreto: beta=1.38 < cap_block=1.4 = NAO viola" {
        $rules = Get-MentorAntiHallucinationRules
        ($rules -match "1\.38.*1\.4|1\.4.*1\.38") | Should Be $true
    }

    It "regra menciona formato correto de citacao (WARN, nao BLOCK)" {
        $rules = Get-MentorAntiHallucinationRules
        ($rules -match "WARN|abaixo do BLOCK") | Should Be $true
    }
}

Describe "Fix1 - MENTOR_DEBATE_SYSTEM em mentor_agent.ps1 contem regra beta" {

    It "system prompt carregado contem regra beta anti-hallucination" {
        $src = Get-Content (Join-Path $root "agents\mentor_agent.ps1") -Raw -Encoding UTF8
        # Extrai o MENTOR_DEBATE_SYSTEM here-string
        $match = [regex]::Match($src, "MENTOR_DEBATE_SYSTEM\s*=\s*@'([\s\S]+?)'@")
        $sysPrompt = if ($match.Success) { $match.Groups[1].Value } else { "" }
        ($sysPrompt -match "BETA.*MATEMATICO|beta.*compare.*numeri|viola BLOCK.*beta") | Should Be $true
    }

    It "system prompt proibe 'viola BLOCK' quando beta < cap_block" {
        $src = Get-Content (Join-Path $root "agents\mentor_agent.ps1") -Raw -Encoding UTF8
        $match = [regex]::Match($src, "MENTOR_DEBATE_SYSTEM\s*=\s*@'([\s\S]+?)'@")
        $sysPrompt = if ($match.Success) { $match.Groups[1].Value } else { "" }
        ($sysPrompt -match "NUNCA.*viola BLOCK|viola BLOCK.*erro matematico") | Should Be $true
    }
}

# ─── Fix 2: BETA_CAP_PER_PHASE_ENABLED ativa caps dinamicos ──────────────────

Describe "Fix2 - BETA_CAP_PER_PHASE_ENABLED ativo em config.local.ps1" {

    It "config.local.ps1 seta BETA_CAP_PER_PHASE_ENABLED=1" {
        # config.local.ps1 e gitignored (credenciais reais) -- nao existe no
        # checkout do CI por design. So valida quando presente (dev local).
        $configPath = Join-Path $root "agents\config.local.ps1"
        if (-not (Test-Path $configPath)) {
            Write-Host "  [SKIP] config.local.ps1 nao existe neste ambiente (esperado no CI)" -ForegroundColor Yellow
            return
        }
        $src = Get-Content $configPath -Raw -Encoding UTF8
        ($src -match 'BETA_CAP_PER_PHASE_ENABLED\s*=\s*"1"') | Should Be $true
    }
}

Describe "Fix2 - caps dinamicos por fase (lib_beta_cap_per_phase)" {

    It "fase bear: BLOCK=1.4 (nao 1.2 default)" {
        $cap = Get-BetaCapForPhase -Phase "h24_p3_bear"
        $cap.block | Should Be 1.4
    }

    It "fase bear: WARN=1.1" {
        $cap = Get-BetaCapForPhase -Phase "h24_p3_bear"
        $cap.warn | Should Be 1.1
    }

    It "fase bull: BLOCK=1.6 (mais permissivo)" {
        $cap = Get-BetaCapForPhase -Phase "h24_p1_bull"
        $cap.block | Should Be 1.6
    }

    It "PENDLE beta=1.3816 em bear = WARN, nao BLOCK" {
        $result = Test-BetaWithinCap -Beta 1.3816 -Phase "h24_p3_bear"
        $result.level | Should Be "WARN"
        $result.level | Should Not Be "BLOCK"
    }

    It "SUI beta=1.497 em bear = BLOCK (correto)" {
        $result = Test-BetaWithinCap -Beta 1.497 -Phase "h24_p3_bear"
        $result.level | Should Be "BLOCK"
    }

    It "ZEC beta=1.5634 em bear = BLOCK (correto)" {
        $result = Test-BetaWithinCap -Beta 1.5634 -Phase "h24_p3_bear"
        $result.level | Should Be "BLOCK"
    }

    It "XRP beta=1.186 em bear = WARN, nao BLOCK" {
        $result = Test-BetaWithinCap -Beta 1.186 -Phase "h24_p3_bear"
        $result.level | Should Be "WARN"
        $result.level | Should Not Be "BLOCK"
    }

    It "INJ beta=1.1976 em bear = WARN, nao BLOCK" {
        $result = Test-BetaWithinCap -Beta 1.1976 -Phase "h24_p3_bear"
        $result.level | Should Be "WARN"
    }

    It "BCH beta=0.9096 em bear = OK" {
        $result = Test-BetaWithinCap -Beta 0.9096 -Phase "h24_p3_bear"
        $result.level | Should Be "OK"
    }

    It "XMR beta=0.9463 em bear = OK" {
        $result = Test-BetaWithinCap -Beta 0.9463 -Phase "h24_p3_bear"
        $result.level | Should Be "OK"
    }

    It "regime semantico BEAR_STRONG traduz para h24_p3_bear (cap 1.4)" {
        $cap = Get-BetaCapForPhase -Phase "BEAR_STRONG"
        $cap.block | Should Be 1.4
    }

    It "regime semantico BEAR_WEAK traduz para h24_p3_bear (cap 1.4)" {
        $cap = Get-BetaCapForPhase -Phase "BEAR_WEAK"
        $cap.block | Should Be 1.4
    }

    It "regime semantico BULL_STRONG usa phase da DATA ATUAL (translator ignora nome do regime)" {
        # O translator usa meses pos-halving (data objetiva), nao o nome do regime.
        # Hoje = h24_p3_bear (25 meses). Para testar cap 1.6 de bull, passar phase direta.
        $cap_direct = Get-BetaCapForPhase -Phase "h24_p1_bull"
        $cap_direct.block | Should Be 1.6
        # Regime semantico hoje -> phase bear (data-driven), source = per_phase_table
        $cap_semantic = Get-BetaCapForPhase -Phase "BULL_STRONG"
        $cap_semantic.source | Should Be "per_phase_table"
    }

    It "phase desconhecida usa default conservador 1.2" {
        $cap = Get-BetaCapForPhase -Phase "UNKNOWN_PHASE_XYZ"
        $cap.block | Should Be 1.2
        $cap.source | Should Be "default"
    }

    It "Strict mode: WARN tratado como BLOCK" {
        $result = Test-BetaWithinCap -Beta 1.3816 -Phase "h24_p3_bear" -Strict
        $result.level | Should Be "BLOCK"
    }

    It "lib_promotion_gates usa cap dinamico quando BETA_CAP_PER_PHASE_ENABLED=1" {
        $src = Get-Content (Join-Path $root "agents\lib_promotion_gates.ps1") -Raw -Encoding UTF8
        ($src -match 'BETA_CAP_PER_PHASE_ENABLED.*eq.*"1"') | Should Be $true
    }
}

# ─── Fix 3 (2026-07-28): Test-BetaWithinCap conectada ao Mentor real ─────────
#
# Achado em producao: Test-BetaWithinCap ja resolvia corretamente a excecao
# "SHORT em bear = beta alto e edge, nao risco" desde 2026-07-03, mas NUNCA
# era chamada em nenhum caminho real -- o Mentor so recebia a mesma regra em
# TEXTO no prompt, e com Mistral (fallback por falta de credito Anthropic) a
# instrucao era ignorada em vetos reais (TIA/OP/SUI, todos SHORT em
# BEAR_STRONG vetados citando "beta viola protecao LONG").

Describe "Fix3 - Test-BetaWithinCap com Direction=SHORT em fase bear" {
    It "beta alto + SHORT + bear = level OK (excecao direcional, nao BLOCK)" {
        $result = Test-BetaWithinCap -Beta 1.7981 -Phase "h24_p3_bear" -Direction "SHORT"
        $result.level | Should Be "OK"
    }

    It "reason cita explicitamente que o cap protege LONG, nao SHORT" {
        $result = Test-BetaWithinCap -Beta 1.5128 -Phase "h24_p3_bear" -Direction "SHORT"
        ($result.reason -match "favoravel para SHORT|protege LONG") | Should Be $true
    }

    It "mesmo beta, SEM Direction=SHORT explicito, continua BLOCK (fail-safe)" {
        $result = Test-BetaWithinCap -Beta 1.7981 -Phase "h24_p3_bear"
        $result.level | Should Be "BLOCK"
    }

    It "Direction=LONG em bear NAO ganha a excecao (cap continua protegendo LONG)" {
        $result = Test-BetaWithinCap -Beta 1.7981 -Phase "h24_p3_bear" -Direction "LONG"
        $result.level | Should Be "BLOCK"
    }
}

Describe "Fix3 - Test-MentorBetaDirectionalHallucination" {
    It "detecta: SHORT + verdict=OK + Mentor cita beta como violacao de BLOCK" {
        $reason = "SHORT em TIA com beta=1.5128 > cap_block=1.2 viola regra de protecao LONG"
        $result = Test-MentorBetaDirectionalHallucination -MentorReason $reason -Direction "SHORT" `
            -FullContextBetaVerdict "OK" -FullContextBetaVerdictReason "beta=1.5128 favoravel para SHORT em bear"
        $result.is_hallucination | Should Be $true
        $result.evidence | Should Be "beta_used_as_risk_for_short_in_bear"
    }

    It "NAO detecta quando Direction=LONG (cap deveria mesmo bloquear)" {
        $reason = "LONG em TIA com beta=1.5128 > cap_block=1.2 viola regra de protecao"
        $result = Test-MentorBetaDirectionalHallucination -MentorReason $reason -Direction "LONG" `
            -FullContextBetaVerdict "BLOCK" -FullContextBetaVerdictReason "beta acima do cap"
        $result.is_hallucination | Should Be $false
    }

    It "NAO detecta quando verdict NAO e OK (veto legitimo, beta realmente violou)" {
        $reason = "SHORT em TIA com beta=1.9 > cap_block=1.4 viola regra"
        $result = Test-MentorBetaDirectionalHallucination -MentorReason $reason -Direction "SHORT" `
            -FullContextBetaVerdict "BLOCK" -FullContextBetaVerdictReason "beta acima do cap mesmo com excecao"
        $result.is_hallucination | Should Be $false
    }

    It "NAO detecta quando o motivo nao menciona beta como violacao (outro motivo de veto)" {
        $reason = "Mesa dividida (CAOS) -- desacordo genuino entre personas"
        $result = Test-MentorBetaDirectionalHallucination -MentorReason $reason -Direction "SHORT" `
            -FullContextBetaVerdict "OK" -FullContextBetaVerdictReason "beta favoravel"
        $result.is_hallucination | Should Be $false
    }
}

Describe "Fix3 - Build-MentorFullContext aceita e usa parametro Direction" {
    BeforeAll {
        . (Join-Path $root "agents\mentor_agent.ps1")
    }

    It "funcao Build-MentorFullContext tem o parametro Direction" {
        $cmd = Get-Command Build-MentorFullContext
        $cmd.Parameters.ContainsKey("Direction") | Should Be $true
    }

    It "nao lanca erro quando Direction e passado (mesmo sem dado real de beta)" {
        { Build-MentorFullContext -Market "SMOKE_TEST_MARKET_XYZ" -Direction "SHORT" } | Should Not Throw
    }
}
