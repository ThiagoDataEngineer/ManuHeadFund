# dsr_forbidden_phrases.Tests.ps1 -- 4b TDD 2026-05-28
#
# Problema: LLM do Mentor usava "DSR n_trades=0 e track record inexistente"
# como razao de ABORTAR mesmo com [DSR_HISTORY] INFO-ONLY no gate block e
# regra 5 explicita no system prompt. O guard pos-resposta nao detectava
# porque as frases DSR nao estavam na MENTOR_FORBIDDEN_PHRASES.
#
# Solucao (4b): adicionar frases DSR ao guard. Estes testes cobrem:
#   1. Cada frase proibida nova e detectada individualmente
#   2. Frases legitimas sobre DSR (informativas) NAO sao detectadas
#   3. Frases proibidas antigas continuam funcionando (regressao)
#   4. Combinacoes reais de razao de ABORTAR dos logs sao detectadas
#   5. Frases permitidas sobre historico limitado NAO disparam o guard
#
# Pester 3.x. UTF-8 BOM.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_mentor_gate_block.ps1")

# ─── helpers ──────────────────────────────────────────────────────────────────

function _GateBlockWithDSR {
    # Gate block com DSR presente (INFO-ONLY) -- contexto normal de operacao
    return "=== GATE STATUS (this trade) ===`n[DSR_HISTORY]  n_trades=0 dsr=0.5 sharpe_30d=0 [INFO-ONLY: nao bloqueia]`n=== END GATE STATUS ==="
}

function _GateBlockDSRAbsent {
    # Gate block sem DSR (campo ausente)
    return "=== GATE STATUS (this trade) ===`n[DSR_HISTORY]  ABSENT [INFO-ONLY: nao bloqueia -- sistema em fase de acumulo de historico]`n=== END GATE STATUS ==="
}

# ─── Suite 1: cada frase proibida nova detectada individualmente ──────────────

Describe "4b: frases DSR proibidas detectadas pelo guard" {

    It "'track record inexistente' e detectada" {
        $r = Test-PromptForbiddenPhrases -Text "DSR n_trades=0 e track record inexistente neste ativo"
        $r.has_forbidden | Should Be $true
        $r.found -contains "track record inexistente" | Should Be $true
    }

    It "'track record zerado' e detectada" {
        $r = Test-PromptForbiddenPhrases -Text "track record zerado impede aprovacao Tier B"
        $r.has_forbidden | Should Be $true
        $r.found -contains "track record zerado" | Should Be $true
    }

    It "'zero track record' e detectada" {
        $r = Test-PromptForbiddenPhrases -Text "zero track record validado neste ativo"
        $r.has_forbidden | Should Be $true
        $r.found -contains "zero track record" | Should Be $true
    }

    It "'sem track record' e detectada" {
        $r = Test-PromptForbiddenPhrases -Text "sem track record validado para justificar risco"
        $r.has_forbidden | Should Be $true
        $r.found -contains "sem track record" | Should Be $true
    }

    It "'DSR n_trades=0' e detectada" {
        $r = Test-PromptForbiddenPhrases -Text "DSR n_trades=0 com dsr=0.5 e track record inexistente"
        $r.has_forbidden | Should Be $true
        $r.found -contains "DSR n_trades=0" | Should Be $true
    }

    It "'n_trades=0 elimina' e detectada" {
        $r = Test-PromptForbiddenPhrases -Text "n_trades=0 elimina qualquer edge historico verificavel"
        $r.has_forbidden | Should Be $true
        $r.found -contains "n_trades=0 elimina" | Should Be $true
    }

    It "'n_trades=0 significa' e detectada" {
        $r = Test-PromptForbiddenPhrases -Text "n_trades=0 significa zero track record validado"
        $r.has_forbidden | Should Be $true
        $r.found -contains "n_trades=0 significa" | Should Be $true
    }

    It "'n_trades=0 e track' e detectada" {
        $r = Test-PromptForbiddenPhrases -Text "n_trades=0 e track record inexistente para TIER_B"
        $r.has_forbidden | Should Be $true
        $r.found -contains "n_trades=0 e track" | Should Be $true
    }

    It "'track record validado' afirmativo NAO e detectado (falso positivo evitado)" {
        # "track record validado por 15 trades" e contexto legitimo -- nao deve disparar.
        # A negacao "sem track record validado" ja e coberta por "sem track record".
        $r = Test-PromptForbiddenPhrases -Text "track record validado por 15 trades confirma edge"
        $r.has_forbidden | Should Be $false
    }
}

# ─── Suite 2: frases legitimas sobre DSR NAO disparam o guard ─────────────────

Describe "4b: frases legitimas sobre DSR NAO sao forbidden" {

    It "mencao informativa 'historico limitado' e permitida" {
        $r = Test-PromptForbiddenPhrases -Text "historico limitado -- monitorar evolucao do ativo"
        $r.has_forbidden | Should Be $false
    }

    It "mencao 'DSR=0.5' sem frase proibida e permitida" {
        $r = Test-PromptForbiddenPhrases -Text "DSR=0.5 indica fase de acumulo de historico"
        $r.has_forbidden | Should Be $false
    }

    It "mencao '[DSR_HISTORY] INFO-ONLY' e permitida" {
        $r = Test-PromptForbiddenPhrases -Text "[DSR_HISTORY] INFO-ONLY: nao bloqueia -- sistema em fase de acumulo"
        $r.has_forbidden | Should Be $false
    }

    It "mencao 'n_trades=6' (com trades) e permitida" {
        $r = Test-PromptForbiddenPhrases -Text "n_trades=6 insuficiente para Kelly graduation (min 10)"
        $r.has_forbidden | Should Be $false
    }

    It "mencao 'acumulo de historico' e permitida" {
        $r = Test-PromptForbiddenPhrases -Text "sistema em fase de acumulo de historico -- monitorar"
        $r.has_forbidden | Should Be $false
    }

    It "razao de ABORTAR sem DSR e permitida" {
        $r = Test-PromptForbiddenPhrases -Text "Mesa dividida CAOS -- desacordo genuino entre personas (1/1/1 vote split)"
        $r.has_forbidden | Should Be $false
    }

    It "razao de ABORTAR por BETA viola BLOCK e permitida" {
        $r = Test-PromptForbiddenPhrases -Text "BETA 1.497 viola BLOCK 1.4 em fase BEAR_STRONG -- hard rule inviolavel"
        $r.has_forbidden | Should Be $false
    }
}

# ─── Suite 3: razoes reais dos logs que devem ser detectadas ──────────────────

Describe "4b: razoes reais dos logs de 28/05 detectadas como forbidden" {

    It "razao real XMRUSDT 09:13 e detectada" {
        $razao = "TIER_B exige Mesa consensus FORTE (T+R+L) mas L=NEUTRO/28 quebra o requisito -- sem consenso completo, o trade nao qualifica pelo design do sistema. DSR n_trades=0 com dsr=0.5 e track record zerado neste ativo, e TORI ABSENT remove confirmacao de timing de entrada critica para SHORT."
        $r = Test-PromptForbiddenPhrases -Text $razao
        $r.has_forbidden | Should Be $true
    }

    It "razao real BCHUSDT 09:13 e detectada" {
        $razao = "Triagem B exige Mesa consensus FORTE (T+R+L) -- L=NEUTRO/28 quebra o requisito hard. DSR n_trades=0 com dsr=0.5 e track record inexistente neste ativo, e TORI SHORT a -7.86% com RSI=20 sinaliza exaustao vendedora iminente que invalida entrada short aqui."
        $r = Test-PromptForbiddenPhrases -Text $razao
        $r.has_forbidden | Should Be $true
    }

    It "razao real SKYUSDT 09:54 e detectada" {
        $razao = "TIER_B exige Mesa consensus FORTE (T+R+L) mas L=LONG/72 quebra o consenso -- sem alinhamento completo, SHORT aqui e aposta, nao edge. DSR n_trades=0 significa zero track record validado neste ativo; FQS=5/7 QUALITY e solido mas nao compensa ausencia de historico + dissidencia da Mesa."
        $r = Test-PromptForbiddenPhrases -Text $razao
        $r.has_forbidden | Should Be $true
    }

    It "razao real XRPUSDT 10:03 e detectada" {
        $razao = "Triagem=B exige Mesa consensus FORTE (T+R+L) mas L=NEUTRO/35 quebra o requisito -- TIER_B_PAPER sem consensus forte nao passa. DSR n_trades=0 + RSI2=88.8 (extremo de sobrevenda em SHORT = timing perigoso) + TORI SHORT proximity=-1.89% com 63 toques = suporte real imediato abaixo do entry."
        $r = Test-PromptForbiddenPhrases -Text $razao
        $r.has_forbidden | Should Be $true
    }

    It "razao real RENDERUSDT 11:05 e detectada" {
        $razao = "TIER_B exige Mesa consensus FORTE (T+R+L) -- L=NEUTRO/28 quebra o requisito, tornando o sinal MEDIO_2 insuficiente para aprovacao. DSR n_trades=0 + ALPHA_HIST ABSENT = zero track record validado neste ativo; RSI 25.9 oversold extremo em SHORT e capitulacao ja consumada, nao topo."
        $r = Test-PromptForbiddenPhrases -Text $razao
        $r.has_forbidden | Should Be $true
    }
}

# ─── Suite 4: regressao -- frases antigas continuam funcionando ───────────────

Describe "4b: regressao -- frases proibidas pre-existentes ainda detectadas" {

    It "'Mesa pulou' ainda detectada" {
        $r = Test-PromptForbiddenPhrases -Text "Mesa pulou o debate por Tier A skip"
        $r.has_forbidden | Should Be $true
        $r.found -contains "Mesa pulou" | Should Be $true
    }

    It "'FQS indisponivel' ainda detectada quando gate nao e ABSENT" {
        $block = "=== GATE STATUS ===`n[FQS] score=4/7 QUALITY`n=== END ==="
        $r = Test-PromptForbiddenPhrases -Text "FQS indisponivel para este market" -GateStatusBlock $block
        $r.has_forbidden | Should Be $true
    }

    It "'FQS indisponivel' ainda justificada quando gate e ABSENT" {
        $block = "=== GATE STATUS ===`n[FQS] ABSENT (no data)`n=== END ==="
        $r = Test-PromptForbiddenPhrases -Text "FQS indisponivel para este market" -GateStatusBlock $block
        $r.has_forbidden | Should Be $false
    }

    It "'Mesa pulada' ainda detectada" {
        $r = Test-PromptForbiddenPhrases -Text "Mesa pulada por regime Tier A"
        $r.has_forbidden | Should Be $true
    }
}

# ─── Suite 5: lista de frases contem todas as novas entradas ──────────────────

Describe "4b: lista MENTOR_FORBIDDEN_PHRASES contem frases DSR" {

    It "lista contem 'track record inexistente'" {
        $list = Get-MentorForbiddenPhrasesList
        $list -contains "track record inexistente" | Should Be $true
    }

    It "lista contem 'track record zerado'" {
        $list = Get-MentorForbiddenPhrasesList
        $list -contains "track record zerado" | Should Be $true
    }

    It "lista contem 'zero track record'" {
        $list = Get-MentorForbiddenPhrasesList
        $list -contains "zero track record" | Should Be $true
    }

    It "lista contem 'sem track record'" {
        $list = Get-MentorForbiddenPhrasesList
        $list -contains "sem track record" | Should Be $true
    }

    It "lista contem 'DSR n_trades=0'" {
        $list = Get-MentorForbiddenPhrasesList
        $list -contains "DSR n_trades=0" | Should Be $true
    }

    It "lista contem 'n_trades=0 elimina'" {
        $list = Get-MentorForbiddenPhrasesList
        $list -contains "n_trades=0 elimina" | Should Be $true
    }

    It "lista contem 'n_trades=0 significa'" {
        $list = Get-MentorForbiddenPhrasesList
        $list -contains "n_trades=0 significa" | Should Be $true
    }

    It "lista contem 'n_trades=0 e track'" {
        $list = Get-MentorForbiddenPhrasesList
        $list -contains "n_trades=0 e track" | Should Be $true
    }

    It "lista NAO contem 'track record validado' (afirmativo -- falso positivo evitado)" {
        # Afirmativo e contexto legitimo. Negacao ja coberta por "sem track record".
        $list = Get-MentorForbiddenPhrasesList
        $list -contains "track record validado" | Should Be $false
    }

    It "lista tem pelo menos 13 entradas (antigas + novas)" {
        $list = Get-MentorForbiddenPhrasesList
        $list.Count | Should BeGreaterThan 12
    }
}

# ─── Suite 6: propriedades -- multiplas frases na mesma razao ─────────────────

Describe "4b: multiplas frases DSR na mesma razao sao todas reportadas" {

    It "razao com 2 frases proibidas DSR reporta ambas" {
        $razao = "DSR n_trades=0 e track record inexistente -- zero track record validado neste ativo"
        $r = Test-PromptForbiddenPhrases -Text $razao
        $r.has_forbidden | Should Be $true
        $r.found.Count | Should BeGreaterThan 1
    }

    It "razao com frase DSR + frase antiga reporta ambas" {
        $razao = "Mesa pulou o debate e DSR n_trades=0 e track record inexistente"
        $r = Test-PromptForbiddenPhrases -Text $razao
        $r.has_forbidden | Should Be $true
        ($r.found -contains "Mesa pulou") | Should Be $true
        ($r.found -contains "track record inexistente") | Should Be $true
    }

    It "razao limpa com gate block DSR presente nao dispara" {
        $block = _GateBlockWithDSR
        $razao = "Mesa dividida CAOS -- desacordo genuino entre personas. BETA 1.497 viola BLOCK 1.4 em fase BEAR_STRONG."
        $r = Test-PromptForbiddenPhrases -Text $razao -GateStatusBlock $block
        $r.has_forbidden | Should Be $false
    }
}
