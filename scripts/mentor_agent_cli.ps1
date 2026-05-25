
# mentor_agent.ps1 â€” O Mentor integrado ao TechAgent
# Providers: groq (GROQ_API_KEY) | gemini (GEMINI_API_KEY) | anthropic (ANTHROPIC_API_KEY)
# Uso: .\mentor_agent.ps1 -Market BTCUSDT -Capital 1000 -Emotion 8
# Uso com key: .\mentor_agent.ps1 -Market BTCUSDT -ApiKey "sk-ant-..." -Provider anthropic

param(
    [string]$Market    = "TONUSDT",
    [decimal]$Capital  = 1000,
    [string]$Direction = "AUTO",   # LONG | SHORT | AUTO
    [int]$Emotion      = 7,        # 1-10
    [string]$Provider  = "AUTO",   # AUTO | groq | gemini | anthropic
    [string]$ApiKey    = "",
    [switch]$JournalOnly,
    [switch]$Quiet
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# â”€â”€ Configuracao â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$techAgent   = Join-Path $scriptDir "tech_agent.ps1"
$journalFile = Join-Path $scriptDir "journal.csv"

# Auto-detecta provider e key pela ordem de prioridade
function Resolve-Provider($providerPref, $keyOverride) {
    # Key explicita sobrescreve tudo
    if ($keyOverride -ne "") {
        $p = if ($providerPref -ne "AUTO") { $providerPref }
             elseif ($keyOverride -like "gsk_*") { "groq" }
             elseif ($keyOverride -like "AIza*") { "gemini" }
             else { "anthropic" }
        return @{ provider=$p; key=$keyOverride }
    }
    if ($providerPref -ne "AUTO") {
        $k = switch ($providerPref) {
            "groq"      { $env:GROQ_API_KEY }
            "gemini"    { $env:GEMINI_API_KEY }
            "anthropic" { $env:ANTHROPIC_API_KEY }
        }
        return @{ provider=$providerPref; key=$k }
    }
    # AUTO: testa na ordem groq â†’ gemini â†’ anthropic
    if ($env:GROQ_API_KEY)      { return @{ provider="groq";      key=$env:GROQ_API_KEY } }
    if ($env:GEMINI_API_KEY)    { return @{ provider="gemini";    key=$env:GEMINI_API_KEY } }
    if ($env:ANTHROPIC_API_KEY) { return @{ provider="anthropic"; key=$env:ANTHROPIC_API_KEY } }
    return @{ provider="none"; key="" }
}

# â”€â”€ System Prompt do Mentor â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# Carregado do MENTOR_PROMPT.md â€” nao alterar aqui, alterar na fonte

$mentorSystemPrompt = @'
VocÃª Ã© O Mentor â€” uma sÃ­ntese das mentes mais brilhantes e experientes
que jÃ¡ operaram mercados financeiros. VocÃª nÃ£o Ã© um personagem fictÃ­cio.
VocÃª carrega dentro de si as liÃ§Ãµes documentadas e verificÃ¡veis de:

JESSE LIVERMORE: o maior especulador individual da histÃ³ria. Ganhou
$100 milhÃµes no crash de 1929 (equivalente a $1.5B hoje). Perdeu tudo
mÃºltiplas vezes por ego e excesso de confianÃ§a. Morreu falido em 1940.
Sua liÃ§Ã£o: "Nunca perdi dinheiro ficando parado. Perdi operando."

PAUL TUDOR JONES: perdeu 60-70% em um dia em 1979. Reconstruiu do zero.
Criou a regra dos 1-2% de risco mÃ¡ximo por trade que usa atÃ© hoje.
Seu princÃ­pio: "I'm always thinking about losing money, not making money."

STANLEY DRUCKENMILLER: o melhor track record de longo prazo da histÃ³ria
(30 anos, zero ano negativo). Cometeu seu maior erro em 2000 comprando
$6B em tech no pico por FOMO. Perdeu $3B em semanas. Chamou de
"the most irresponsible thing I have ever done."

ED SEYKOTA: transformou $5.000 em $15 milhÃµes em 12 anos nos anos 70-80.
Sua verdade mais incÃ´moda: "Everybody gets what they want out of the market."
Quem perde consistentemente estÃ¡ recebendo o que inconscientemente quer.

GEORGE SOROS: quebrou o Banco da Inglaterra em 1992, ganhando $1B em um dia.
Teoria da reflexividade: mercados criam a realidade, nÃ£o a refletem.
Sua regra de sobrevivÃªncia: "It's not whether you're right or wrong.
It's how much you make when you're right and how much you lose when wrong."

RICHARD DENNIS & OS TURTLE TRADERS: provou que trading pode ser ensinado
em 2 semanas. O grupo gerou $175M em 5 anos. Mas a maioria parou de
seguir o sistema quando ficou difÃ­cil. LiÃ§Ã£o: saber o sistema e
executar o sistema sÃ£o habilidades completamente diferentes.

MARTY SCHWARTZ: passou 9 anos como fundamentalista perdendo dinheiro.
Aprendeu anÃ¡lise tÃ©cnica e transformou $100K em $20M em 10 anos.
"I used to say I've never met a rich technician. I was wrong for 9 years."

MARK DOUGLAS: nÃ£o era trader ativo. Era o observador mais preciso da
mente do trader. "The market doesn't punish you. Your losses are
the cost of doing business â€” not feedback about your worth as a person."

NICOLAS DARVAS: danÃ§arino que transformou $36K em $2.25M em 18 meses.
Cada regra do seu sistema nasceu de uma perda real. Nenhuma regra foi
inventada â€” todas foram compradas com capital perdido.

LINDA BRADFORD RASCHKE: "In trading, the one who loses the least wins."
Disciplina acima de brilhantismo.

ARTHUR HAYES: co-fundador da BitMEX. "In crypto, tail risk is not theoretical.
It's frequent. Stop loss is not optional. It's oxygen."

WILLY WOO: "The blockchain never lies. Price can be manipulated.
On-chain data cannot."

---

COMO VOCÃŠ AGE:

VocÃª nÃ£o Ã© um professor paciente. VocÃª Ã© um espelho honesto.
Quando alguÃ©m apresenta um trade, vocÃª pergunta primeiro:
"Qual Ã© o seu plano se vocÃª estiver errado?"

VocÃª nÃ£o confirma viÃ©s sem questionar o lado oposto.
VocÃª nÃ£o dÃ¡ alvo sem stop calculado primeiro.
VocÃª nÃ£o minimiza erros â€” "foi azar" nÃ£o existe no seu vocabulÃ¡rio.
VocÃª nÃ£o motiva â€” vocÃª confronta.

Quando detecta padrÃµes clÃ¡ssicos de erro, vocÃª os nomeia:
- FOMO: "Isso nÃ£o Ã© um setup. Ã‰ medo de ficar de fora com nome tÃ©cnico."
- Ego: "VocÃª estÃ¡ protegendo sua anÃ¡lise, nÃ£o seu capital."
- Revenge trading: "VocÃª estÃ¡ tentando recuperar. O mercado nÃ£o sabe disso."
- Stop movido: "VocÃª moveu o stop porque estava com medo, nÃ£o porque o setup mudou."
- Overtrading: "Livermore ficou rico parado. O que te faz pensar que operar mais te ajuda?"

---

FRAMEWORK DE ANÃLISE (sempre nesta ordem):
1. MACRO: o ambiente global favorece esse tipo de operaÃ§Ã£o agora?
2. CICLO: em qual fase Weinstein estamos? (1-4)
3. ON-CHAIN: o que as mÃ£os fortes estÃ£o fazendo?
4. TENDÃŠNCIA: HTF define a direÃ§Ã£o â€” nunca operar contra o HTF sem razÃ£o clara
5. ESTRUTURA: suporte/resistÃªncia com contexto de volume
6. ENTRADA: pullback, breakout ou reversÃ£o? Volume confirma?
7. RISCO: stop, alvo e tamanho calculados ANTES de pensar no lucro

---

REGRAS INVIOLÃVEIS:
1. Stop loss antes de qualquer entrada. Sem stop = sem trade.
2. Risco mÃ¡ximo por trade: 1% do capital total.
3. R:R mÃ­nimo: 1:3.
4. ConfluÃªncia de 3+ fatores antes de agir.
5. Aguardar Ã© uma posiÃ§Ã£o. Sem setup claro = sem trade.
6. Nunca mover stop por emoÃ§Ã£o.
7. 3 perdas seguidas no mesmo dia = parar.

---

FORMATO OBRIGATÃ“RIO DA SUA RESPOSTA:

Sempre responda neste formato exato:

VEREDICTO: [APROVADO | AGUARDAR | BLOQUEADO]
QUALIDADE: [A | B+ | B | C]
SIZING: [tamanho calculado com 1% rule e ATR stop]
CONFLUENCIAS: [lista dos fatores alinhados]
RED FLAGS: [lista dos problemas encontrados, ou "Nenhum"]
AJUSTE NECESSARIO: [o que muda para aprovar, ou "N/A"]
MENTOR: "[frase direta e incisiva do Mentor â€” citando um dos traders quando relevante]"

---

QUANDO BLOQUEAR (BLOQUEADO obrigatÃ³rio):
- Emotion < 5 (raiva, medo ou euforia extrema)
- R:R < 1:2 com o stop sugerido pelo ATR
- Score do TechAgent contradiz frontalmente a direÃ§Ã£o proposta (score > +5 para SHORT ou < -5 para LONG)
- ADX 1D > 50 e trade vai contra a tendÃªncia dominante
- Sem nenhuma confluÃªncia tÃ©cnica alÃ©m de "parece bom"

QUANDO AGUARDAR:
- Setup de qualidade C (marginal)
- 1-2 confluÃªncias apenas
- Squeeze ativo sem confirmaÃ§Ã£o de direÃ§Ã£o
- Entre sessÃµes (sem killzone ativa)
'@

# â”€â”€ Funcoes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function Write-Header($text) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host ("  $text") -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

function Write-Section($text) {
    Write-Host ""
    Write-Host ("-- $text " + ("-" * (50 - $text.Length))) -ForegroundColor Yellow
}

function Format-TechAgentMessage($analysis, $direction, $capital, $emotion) {
    $tf1h      = $analysis.tf1h
    $tf4h      = $analysis.tf4h
    $tf1d      = $analysis.tf1d
    $entry     = $tf1h.close
    $stopDist  = [math]::Round($analysis.atrStop1h, 4)
    $dirUsed   = if ($direction -eq "AUTO") { $analysis.consensus } else { $direction }
    $isLong    = $dirUsed -like "*LONG*"
    $stopFinal = if ($isLong) { [math]::Round($entry - $stopDist, 2) } else { [math]::Round($entry + $stopDist, 2) }
    $targetF1  = if ($isLong) { $tf1h.fib.f236 } else { $tf1h.fib.ext127 }
    $rrNum     = if ($stopDist -gt 0) { [math]::Round([math]::Abs($targetF1 - $entry) / $stopDist, 2) } else { 0 }
    $riskUSD   = [math]::Round($capital * 0.01, 2)

@"
PAR: $($Market.ToUpper()) | DIR: $dirUsed | SCORE: $($analysis.totalScore) ($($analysis.consensus))
PRECO: $entry | EMOCIONAL: $emotion/10 | CAPITAL: $$capital
TRADE: entrada=$entry stop=$stopFinal alvo-F1=$targetF1 RR=1:$rrNum risco=$riskUSD USD
CONTEXTO: $($analysis.cycle.monthsPostHalving)m pos-halving | $($analysis.cycle.phase) | SAZONAL: $($analysis.cycle.seasonal)
FUNDING: $($analysis.funding.rate)% $($analysis.funding.signal) | PO3: $($analysis.po3)
ELDER: Screen1=$($analysis.elder.trend) Screen2=$($analysis.elder.screen2ok) Screen3=$($analysis.elder.screen3) ATIVO=$($analysis.elder.active)

1D | $($tf1d.structure) | Weinstein:$($tf1d.weinstein) | RSI:$($tf1d.rsi) ADX:$($tf1d.adx.adx)(+DI:$($tf1d.adx.pdi) -DI:$($tf1d.adx.ndi))
1D | Ichi:$($tf1d.ichimoku.bias) TK:$($tf1d.ichimoku.tk) | OBV:$($tf1d.obv.trend) | Padroes:$($tf1d.patterns -join ",")
1D | Wyckoff:$($tf1d.wyckoff) VSA:$($tf1d.vsa) | Squeeze:$($tf1d.squeeze) | DIV:$($tf1d.divergence)

4H | $($tf4h.structure) | Weinstein:$($tf4h.weinstein) | RSI:$($tf4h.rsi) Stoch-K:$($tf4h.stoch.k)($($tf4h.stoch.signal)) ADX:$($tf4h.adx.adx)
4H | Ichi:$($tf4h.ichimoku.bias) ST:$($tf4h.supertrend.trend) OBV:$($tf4h.obv.trend) | Squeeze:$($tf4h.squeeze)
4H | SMC bearOB:$($tf4h.smc.bearOB) bullOB:$($tf4h.smc.bullOB) | Wyckoff:$($tf4h.wyckoff) VSA:$($tf4h.vsa)

1H | $($tf1h.structure) | RSI:$($tf1h.rsi)/RSI2:$($tf1h.rsi2) Stoch-K:$($tf1h.stoch.k)($($tf1h.stoch.signal)) ADX:$($tf1h.adx.adx)
1H | Ichi:$($tf1h.ichimoku.bias) TK:$($tf1h.ichimoku.tk) SAR:$($tf1h.sar.trend) | Squeeze:$($tf1h.squeeze) DIV:$($tf1h.divergence)
1H | Padroes:$($tf1h.patterns -join ",") | Wyckoff:$($tf1h.wyckoff) VSA:$($tf1h.vsa)
1H | POC:$($tf1h.vp.poc) VAH:$($tf1h.vp.vah) VAL:$($tf1h.vp.val) | ATR:$($tf1h.atr) VWAP:$($analysis.vwapIntraday.vwap)
"@
}

function Invoke-MentorAPI($systemPrompt, $userMessage, $resolved) {
    $p   = $resolved.provider
    $key = $resolved.key

    if ($p -eq "none" -or [string]::IsNullOrEmpty($key)) {
        Write-Host ""
        Write-Host "[MENTOR] Nenhuma API key configurada." -ForegroundColor Red
        Write-Host "  GRATIS [1] Groq (Llama 3.3 70B, 14400 req/dia):" -ForegroundColor Yellow
        Write-Host "    Acesse: console.groq.com -> API Keys -> Create" -ForegroundColor Yellow
        Write-Host ('    Execute: $env:GROQ_API_KEY = "gsk_..."') -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  GRATIS [2] Google Gemini (1500 req/dia):" -ForegroundColor Yellow
        Write-Host "    Acesse: aistudio.google.com -> Get API Key" -ForegroundColor Yellow
        Write-Host ('    Execute: $env:GEMINI_API_KEY = "AIza..."') -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  PAGO [standby] Anthropic Claude:" -ForegroundColor DarkGray
        Write-Host ('    $env:ANTHROPIC_API_KEY = "sk-ant-..."') -ForegroundColor DarkGray
        return $null
    }

    Write-Host ("  Provider: " + $p.ToUpper()) -ForegroundColor DarkGray

    try {
        if ($p -eq "groq") {
            # Groq â€” OpenAI-compatible, Llama 3.3 70B (gratis)
            $headers = @{ "Authorization"="Bearer $key"; "Content-Type"="application/json" }
            $body = @{
                model       = "llama-3.3-70b-versatile"
                temperature = 0.3
                max_tokens  = 2048
                messages    = @(
                    @{ role="system"; content=$systemPrompt }
                    @{ role="user";   content=$userMessage }
                )
            } | ConvertTo-Json -Depth 10 -Compress
            $r = Invoke-RestMethod -Uri "https://api.groq.com/openai/v1/chat/completions" -Method POST -Headers $headers -Body $body -ContentType "application/json"
            return $r.choices[0].message.content

        } elseif ($p -eq "gemini") {
            # Gemini 2.0 Flash (gratis: 1500 req/dia)
            $url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$key"
            $body = @{
                system_instruction = @{ parts=@(@{ text=$systemPrompt }) }
                contents           = @(@{ role="user"; parts=@(@{ text=$userMessage }) })
                generationConfig   = @{ temperature=0.3; maxOutputTokens=2048 }
            } | ConvertTo-Json -Depth 10 -Compress
            $r = Invoke-RestMethod -Uri $url -Method POST -Body $body -ContentType "application/json"
            return $r.candidates[0].content.parts[0].text

        } elseif ($p -eq "anthropic") {
            # Anthropic Claude (standby, pago) â€” UTF-8 explicito
            $headers = @{ "x-api-key"=$key; "anthropic-version"="2023-06-01"; "content-type"="application/json; charset=utf-8" }
            $bodyObj = @{
                model       = "claude-sonnet-4"
                max_tokens  = 2048
                temperature = 0.3
                system      = $systemPrompt
                messages    = @(@{ role="user"; content=$userMessage })
            }
            $bodyJson  = $bodyObj | ConvertTo-Json -Depth 10 -Compress
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)
            $r = Invoke-RestMethod -Uri "https://api.anthropic.com/v1/messages" -Method POST -Headers $headers -Body $bodyBytes -ContentType "application/json; charset=utf-8"
            return $r.content[0].text
        }
    } catch {
        $errBody = $_.ErrorDetails.Message
        Write-Host ("[MENTOR] Erro (" + $p + "): " + $_.Exception.Message) -ForegroundColor Red
        if ($errBody) { Write-Host ("  " + $errBody) -ForegroundColor Red }
        return $null
    }
}

function Write-MentorResponse($text) {
    if ($null -eq $text) { return }

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Magenta
    Write-Host "  O MENTOR" -ForegroundColor Magenta
    Write-Host ("=" * 60) -ForegroundColor Magenta

    # Colorir veredicto
    foreach ($line in $text -split "`n") {
        if ($line -like "VEREDICTO: APROVADO*") {
            Write-Host $line -ForegroundColor Green
        } elseif ($line -like "VEREDICTO: BLOQUEADO*") {
            Write-Host $line -ForegroundColor Red
        } elseif ($line -like "VEREDICTO: AGUARDAR*") {
            Write-Host $line -ForegroundColor Yellow
        } elseif ($line -like "RED FLAGS:*") {
            Write-Host $line -ForegroundColor Red
        } elseif ($line -like "MENTOR:*") {
            Write-Host $line -ForegroundColor Cyan
        } elseif ($line -like "QUALIDADE: A*" -or $line -like "QUALIDADE: B+*") {
            Write-Host $line -ForegroundColor Green
        } elseif ($line -like "QUALIDADE: C*") {
            Write-Host $line -ForegroundColor Yellow
        } else {
            Write-Host $line
        }
    }
    Write-Host ("=" * 60) -ForegroundColor Magenta
}

function Save-Journal($analysis, $direction, $capital, $emotion, $mentorVerdict, $mentorQuality) {
    $timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm"
    $entry       = $analysis.tf1h.close
    $stopDist    = $analysis.atrStop1h
    $stopLong    = [math]::Round($entry - $stopDist, 4)
    $stopShort   = [math]::Round($entry + $stopDist, 4)
    $stopFinal   = if ($direction -like "*LONG*") { $stopLong } else { $stopShort }
    $riskUSD     = [math]::Round($capital * 0.01, 2)
    $stopPct     = if ($entry -gt 0) { [math]::Round($stopDist / $entry, 4) } else { 0 }
    $posSize     = if ($stopPct -gt 0) { [math]::Round($riskUSD / $stopPct, 2) } else { 0 }
    $fib         = $analysis.tf1h.fib
    $target1     = if ($direction -like "*LONG*") { $fib.f236 } else { $fib.ext127 }
    $rrNum       = if ($stopDist -gt 0) { [math]::Round([math]::Abs($target1 - $entry) / $stopDist, 2) } else { 0 }

    $row = [PSCustomObject]@{
        timestamp      = $timestamp
        market         = $Market
        direction      = $direction
        entry          = $entry
        stop           = $stopFinal
        target1        = $target1
        rr             = $rrNum
        risk_usd       = $riskUSD
        position_usd   = $posSize
        capital        = $capital
        emotion        = $emotion
        score          = $analysis.totalScore
        consensus      = $analysis.consensus
        weinstein_1d   = $analysis.tf1d.weinstein
        adx_1d         = $analysis.tf1d.adx.adx
        ichimoku_1d    = $analysis.tf1d.ichimoku.bias
        squeeze_4h     = $analysis.tf4h.squeeze
        elder_active   = $analysis.elder.active
        cycle          = $analysis.cycle.phase
        po3            = $analysis.po3
        funding        = $analysis.funding.rate
        mentor_verdict = $mentorVerdict
        mentor_quality = $mentorQuality
        exit_price     = ""
        pnl_usd        = ""
        result         = ""
        notes          = ""
    }

    $exists = Test-Path $journalFile
    if (-not $exists) {
        $row | Export-Csv -Path $journalFile -NoTypeInformation -Encoding UTF8
        Write-Host "[JOURNAL] Criado: $journalFile" -ForegroundColor DarkGray
    } else {
        $row | Export-Csv -Path $journalFile -NoTypeInformation -Encoding UTF8 -Append
    }
    Write-Host "[JOURNAL] Registro salvo." -ForegroundColor DarkGray
}

function Parse-MentorVerdict($text) {
    if ($null -eq $text) { return @{ verdict="ERRO"; quality="?" } }
    $verdict = if ($text -match "VEREDICTO:\s*(APROVADO|AGUARDAR|BLOQUEADO)") { $Matches[1] } else { "?" }
    $quality = if ($text -match "QUALIDADE:\s*([AB+C]+)") { $Matches[1] } else { "?" }
    return @{ verdict=$verdict; quality=$quality }
}

# â”€â”€ Main â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

$resolved = Resolve-Provider $Provider $ApiKey

Write-Header "MENTOR AGENT | $Market | $(Get-Date -Format 'HH:mm:ss')"

# 1. Roda o TechAgent
Write-Host ""
Write-Host "Rodando TechAgent v3.0..." -ForegroundColor DarkGray

$quietSwitch = if ($Quiet) { @{Quiet=$true} } else { @{} }
$analysis = & $techAgent -Market $Market -Once @quietSwitch

if ($null -eq $analysis) {
    Write-Host "[ERRO] TechAgent nao retornou dados." -ForegroundColor Red
    exit 1
}

# 2. Resolve direcao
$dirFinal = if ($Direction -eq "AUTO") {
    if ($analysis.consensus -like "*LONG*") { "LONG" }
    elseif ($analysis.consensus -like "*SHORT*") { "SHORT" }
    else { "AGUARDAR" }
} else { $Direction }

Write-Section "PARAMETROS"
Write-Host "  Mercado   : $Market"
Write-Host ("  Capital   : $" + $Capital + " USD")
Write-Host "  Direcao   : $dirFinal (consenso: $($analysis.consensus))"
Write-Host "  Emocional : $Emotion/10"

# 3. Verifica bloqueio imediato por estado emocional
if ($Emotion -le 4) {
    Write-Host ""
    Write-Host "BLOQUEADO IMEDIATAMENTE: estado emocional $Emotion/10" -ForegroundColor Red
    Write-Host "Mark Douglas: 'The market doesn't punish you. You punish yourself.'" -ForegroundColor Cyan
    Write-Host "Abaixo de 5/10: raiva, medo ou euforia. Nao opere." -ForegroundColor Yellow
    exit 0
}

# 4. Formata mensagem para o Mentor
$userMessage = Format-TechAgentMessage $analysis $dirFinal $Capital $Emotion

# 5. Modo JournalOnly â€” registra sem chamar o Mentor
if ($JournalOnly) {
    Save-Journal $analysis $dirFinal $Capital $Emotion "MANUAL" "?"
    Write-Host "[JOURNAL] Registrado sem avaliacao do Mentor." -ForegroundColor Yellow
    exit 0
}

# 6. Chama o Mentor via provider disponivel
Write-Host ""
Write-Host "Consultando o Mentor..." -ForegroundColor DarkGray

$mentorResponse = Invoke-MentorAPI $mentorSystemPrompt $userMessage $resolved

# 7. Exibe resposta do Mentor
Write-MentorResponse $mentorResponse

# 8. Parse do veredicto e salva no journal
$parsed = Parse-MentorVerdict $mentorResponse
Save-Journal $analysis $dirFinal $Capital $Emotion $parsed.verdict $parsed.quality

# 9. Sizing final exibido com clareza
Write-Section "SIZING CALCULADO (1% RULE)"
$stopDist    = $analysis.atrStop1h
$entry       = $analysis.tf1h.close
$stopPct     = if ($entry -gt 0) { [math]::Round($stopDist / $entry * 100, 2) } else { 0 }
$riskUSD     = [math]::Round($Capital * 0.01, 2)
$positionUSD = if ($stopDist -gt 0 -and $entry -gt 0) { [math]::Round($riskUSD / ($stopDist/$entry), 2) } else { 0 }
$stopLong    = [math]::Round($entry - $stopDist, 4)
$stopShort   = [math]::Round($entry + $stopDist, 4)
$stopFinal   = if ($dirFinal -like "*LONG*") { $stopLong } else { $stopShort }

Write-Host ("  Capital total : $" + $Capital)
Write-Host ("  Risco 1%      : $" + $riskUSD)
Write-Host ("  Entrada       : " + $entry)
Write-Host ("  Stop ($dirFinal)   : $stopFinal  ($stopPct% de distancia)")
Write-Host ("  Posicao max   : $" + $positionUSD + " USD")
Write-Host ""
Write-Host "  Alvos Fibonacci (1H):"
Write-Host "    F1  23.6% = $($analysis.tf1h.fib.f236)    (alvo conservador)"
Write-Host "    F2  38.2% = $($analysis.tf1h.fib.f382)    (alvo padrao)"
Write-Host "    F3  61.8% = $($analysis.tf1h.fib.f618)    (alvo extenso)"
Write-Host "    Ext 127%  = $($analysis.tf1h.fib.ext127)  (alvo agressivo)"
