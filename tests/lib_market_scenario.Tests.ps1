# lib_market_scenario.Tests.ps1 -- Pester 3.x
# TDD 2026-06-24: motor de CENARIO (identifica regime -> estrategia com edge).
# "Sempre ganhar" = sempre escolher a estrategia certa pro cenario:
#   CAPITULACAO -> comprar fundo (LONG) | BEAR -> SHORT/caixa | BULL -> LONG | NEUTRO -> esperar.
# Capitulacao (BEAR_MARKET.md Fase 3 / Weinstein): RSI extremo + volume climatico + queda profunda.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_market_scenario.ps1")

Describe "Test-Capitulation - detecta o fundo (Fase 3)" {
    It "RSI extremo + volume climatico + abaixo da 200 -> CAPITULACAO" {
        (Test-Capitulation -Rsi 24 -VolRatio 2.2 -Price 52000 -Ema200 77000).is_capitulation | Should Be $true
    }
    It "RSI baixo mas SEM volume climatico -> NAO e capitulacao (so queda)" {
        (Test-Capitulation -Rsi 28 -VolRatio 1.0 -Price 52000 -Ema200 77000).is_capitulation | Should Be $false
    }
    It "Volume alto mas RSI nao extremo -> NAO" {
        (Test-Capitulation -Rsi 42 -VolRatio 2.5 -Price 60000 -Ema200 77000).is_capitulation | Should Be $false
    }
    It "Acima da 200 (nao e bear profundo) -> NAO" {
        (Test-Capitulation -Rsi 25 -VolRatio 2.0 -Price 80000 -Ema200 77000).is_capitulation | Should Be $false
    }
}

Describe "Test-Euphoria - detecta o topo (espelho de Test-Capitulation)" {
    # Achado real 2026-08-14 (owner pediu pra investigar se um SHORT no topo
    # do ACEUSDT teria sido pego): no candle exato do topo (08-14 22:00,
    # RSI~95, momentum30d=150%, vol_ratio=5.25x), Test-PumpDumpGate JA
    # liberava SHORT (reaccumulation), mas Resolve-MarketScenario bloqueava
    # incondicionalmente -- classificava BULL (preco>EMA20 + momentum
    # positivo) sem nenhuma nocao de exaustao. Existia Test-Capitulation
    # (fundo: RSI<=30 + volume climatico + preco<EMA200) mas nao o espelho
    # (topo: RSI>=70 + volume climatico + preco>EMA200 esticado) -- lacuna
    # estrutural, nao bug. Preco>EMA200 sozinho e normal em qualquer BULL
    # saudavel; a assimetria real e exigir DISTANCIA da EMA200 (esticado
    # demais), nao so estar acima dela.
    It "RSI extremo + volume climatico + esticado (>15%) acima da 200 -> EUFORIA" {
        (Test-Euphoria -Rsi 95 -VolRatio 5.25 -Price 0.350948 -Ema200 0.15).is_euphoria | Should Be $true
    }
    It "RSI alto mas SEM volume climatico -> NAO e euforia (so alta normal)" {
        (Test-Euphoria -Rsi 75 -VolRatio 1.0 -Price 0.35 -Ema200 0.15).is_euphoria | Should Be $false
    }
    It "Volume alto mas RSI nao extremo -> NAO" {
        (Test-Euphoria -Rsi 58 -VolRatio 2.5 -Price 0.35 -Ema200 0.15).is_euphoria | Should Be $false
    }
    It "Perto da 200 (nao esticado, BULL saudavel normal) -> NAO" {
        (Test-Euphoria -Rsi 75 -VolRatio 2.0 -Price 66000 -Ema200 64000).is_euphoria | Should Be $false
    }
    It "Abaixo da 200 (nao e topo esticado) -> NAO" {
        (Test-Euphoria -Rsi 80 -VolRatio 2.0 -Price 60000 -Ema200 64000).is_euphoria | Should Be $false
    }
}

Describe "Resolve-MarketScenario - cenario -> estrategia com edge" {
    It "Capitulacao -> ACUMULA LONG (compra o fundo)" {
        $r = Resolve-MarketScenario -Price 52000 -Ema20 64000 -Ema50 68000 -Ema200 77000 -Rsi 24 -Momentum30dPct -28 -VolRatio 2.2
        $r.scenario | Should Be "CAPITULACAO"
        $r.allow_long | Should Be $true
        $r.allow_short | Should Be $false
    }
    It "Bear sem capitulacao -> SHORT/caixa (bloqueia LONG)" {
        $r = Resolve-MarketScenario -Price 60800 -Ema20 64300 -Ema50 68200 -Ema200 77000 -Rsi 38 -Momentum30dPct -19.9 -VolRatio 1.0
        $r.scenario | Should Be "BEAR"
        $r.allow_long | Should Be $false
        $r.allow_short | Should Be $true
    }
    It "Bull -> LONG (sem short)" {
        $r = Resolve-MarketScenario -Price 72000 -Ema20 68000 -Ema50 66000 -Ema200 64000 -Rsi 58 -Momentum30dPct 12 -VolRatio 1.1
        $r.scenario | Should Be "BULL"
        $r.allow_long | Should Be $true
        $r.allow_short | Should Be $false
    }
    It "Neutro/chop -> ESPERA (nem long nem short)" {
        $r = Resolve-MarketScenario -Price 65000 -Ema20 65100 -Ema50 64900 -Ema200 66000 -Rsi 50 -Momentum30dPct 1 -VolRatio 1.0
        $r.scenario | Should Be "NEUTRO"
        $r.allow_long | Should Be $false
        $r.allow_short | Should Be $false
    }
    It "Dados invalidos -> UNKNOWN fail-safe (nao bloqueia por dado ruim)" {
        $r = Resolve-MarketScenario -Price 0 -Ema20 0 -Ema50 0 -Ema200 0 -Rsi 0 -Momentum30dPct 0 -VolRatio 0
        $r.scenario | Should Be "UNKNOWN"
        $r.allow_long | Should Be $true
    }

    It "Bounce de curto prazo DENTRO de bear estrutural -- regressao 2026-07-23" {
        # BTC real 2026-07-23: preco 10.36% abaixo da SMA200 (Fase 4 Weinstein,
        # bear estrutural), mas subiu +3.74% em 30d e ficou acima da EMA20 --
        # antes do fix isso classificava BULL (Ema200 recebido mas nunca usado
        # no ramo bull/bear), liberava o TORI LONG sweep, e o TechAgent (LLM,
        # ve 1W/1D completo) rejeitava os candidatos LONG gerados com SHORT
        # forte -- travando tudo no Quality Gate (sintoma: SPOT nunca abria).
        $r = Resolve-MarketScenario -Price 65074 -Ema20 64330 -Ema50 65130 -Ema200 72593 -Rsi 45 -Momentum30dPct 3.74 -VolRatio 1.0
        $r.scenario | Should Not Be "BULL"
        $r.allow_long | Should Be $false
    }

    It "EUFORIA (topo esticado) -> libera SHORT -- caso real ACEUSDT no pico antes do crash de -31% (2026-08-14 22h-23h)" {
        # Dado real do candle diario do pico (08-14, close=0.350948): RSI~95,
        # momentum30d=150%, vol_ratio=5.25x, preco ~134% acima da EMA200
        # estimada (0.15). Antes do fix, isso classificava BULL puro
        # (allow_short=false) -- o crash de -31% que aconteceu na hora
        # seguinte (23:00, close=0.251168) nunca teria sido pego por SHORT.
        $r = Resolve-MarketScenario -Price 0.350948 -Ema20 0.20 -Ema50 0.15 -Ema200 0.15 -Rsi 95 -Momentum30dPct 150 -VolRatio 5.25
        $r.scenario | Should Be "EUFORIA"
        $r.allow_short | Should Be $true
        $r.allow_long | Should Be $false
    }

    It "BULL saudavel normal (RSI moderado, sem volume climatico) continua liberando LONG, nao regride pra EUFORIA" {
        $r = Resolve-MarketScenario -Price 72000 -Ema20 68000 -Ema50 66000 -Ema200 64000 -Rsi 58 -Momentum30dPct 12 -VolRatio 1.1
        $r.scenario | Should Be "BULL"
        $r.allow_long | Should Be $true
        $r.allow_short | Should Be $false
    }
}
