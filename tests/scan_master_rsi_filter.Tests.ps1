# scan_master_rsi_filter.Tests.ps1 -- Pester 3.x
# TDD: Bug A (pre-screen RSI trend-aware) + Bug B (top-N ranking por score composto).
#
# Bug A: Pre-screen RSI <= 78 era estatico. Breakouts saudaveis (HYPE 14/05: RSI 80,
# vol 4.46x, ADX 29) eram rejeitados antes do orchestrator V6.
# KB-fix RSI trend-aware ja aplicada em backtest/signal_generator.py, mas NAO no scanner.
#
# Bug B: Top-N usava Sort-Object adx -Descending puro. Pegava ADX 88-100 (exausto)
# em vez de 19-50 (breakout fresco). Substituido por score composto.

$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptsDir = Join-Path (Split-Path $here -Parent) 'scripts'
$scanMaster = Join-Path $scriptsDir 'scan_master.ps1'

# Importa funcoes puras de scan_master.ps1 sem rodar o loop (Once + flags abrem
# conexoes). Estrategia: extrair as duas funcoes via regex e dot-source via
# Invoke-Expression. Padrao Pester 3.x para scripts com ParseTree complexo.

$scanMasterContent = Get-Content -Raw -Path $scanMaster

# Extrai Test-ScanPreScreen (fix Bug A)
if ($scanMasterContent -match '(?ms)(^function Test-ScanPreScreen\s*\{.*?^\})') {
    Invoke-Expression $Matches[1]
}

# Extrai Get-ScannerCompositeScore (fix Bug B)
if ($scanMasterContent -match '(?ms)(^function Get-ScannerCompositeScore\s*\{.*?^\})') {
    Invoke-Expression $Matches[1]
}


Describe 'scan_master Bug A - Pre-screen RSI trend-aware (KB-fix)' {

    It 'Pre-screen passa RSI=82 quando ADX e Volume tambem passam (trend-aware)' {
        Test-ScanPreScreen -Rsi 82 -Adx 28 -Vol 2.0 | Should Be $true
    }

    It 'Pre-screen passa RSI=86 (breakout extremo) com vol 4x+ e ADX 25+' {
        # Cenario HYPE 14/05: vol 4.46x, ADX ~29, RSI ~80.
        Test-ScanPreScreen -Rsi 86 -Adx 26 -Vol 4.0 | Should Be $true
    }

    It 'Pre-screen REJEITA RSI=85 sem volume (vol menor que 1.5x)' {
        Test-ScanPreScreen -Rsi 85 -Adx 30 -Vol 1.0 | Should Be $false
    }

    It 'Pre-screen REJEITA RSI maior que 88 (overextended)' {
        Test-ScanPreScreen -Rsi 90 -Adx 35 -Vol 3.0 | Should Be $false
    }

    It 'Mantem compat: RSI=50 + ADX 25 + vol 1x continua passando' {
        Test-ScanPreScreen -Rsi 50 -Adx 25 -Vol 1.0 | Should Be $true
    }

    It 'RSI menor que 28 (oversold extremo) continua rejeitado' {
        Test-ScanPreScreen -Rsi 20 -Adx 30 -Vol 2.0 | Should Be $false
    }
}


# ─────────────────────────────────────────────────────────────────────────────
# Bug C (2026-05-15) - Desacoplar vol/ADX do gate de RSI saudavel
#
# Sintoma: ciclo 04:06 BRT 15/05 bloqueou 100% (20/20) candidatos no pre-screen.
# Logs reais (snapshot 10:13): RSI gate falhou em 14/14 blocks; 10/14 com razao
# "rsi_healthy_band missing=vol<1.0x". Janela SLOW (madrugada) tem vol relativo
# universalmente baixo, e o Bug A fix amarrou exigencia de vol>=1.0x DENTRO do
# gate de RSI -- redundante com o gate vol>=0.5x do array passes, e gerando
# bloqueio em cascata.
#
# Fix: Test-ScanPreScreen julga APENAS RSI. Faixa saudavel (28-78) retorna $true
# sempre. Confluencia vol/ADX so se aplica em faixa de breakout (78-88), onde
# a confluencia E o sinal. Os gates ADX>=18 e vol>=0.5x do array passes filtram
# o resto separadamente.
# ─────────────────────────────────────────────────────────────────────────────

Describe 'scan_master Bug C - RSI gate desacoplado de vol/ADX em faixa saudavel' {

    It 'RSI 28-78 (saudavel): passa SEMPRE -- vol e ADX nao sao do RSI gate' {
        # Cenario ciclo 04:06 SLOW: HYPE RSI=43 vol=0.31x ADX=34.8 -- gate vol
        # do array passes (>=0.5) decide isolado, RSI nao deve bloquear.
        Test-ScanPreScreen -Rsi 43 -Adx 34.8 -Vol 0.31 | Should Be $true
    }

    It 'RSI 54 com vol baixo (0.4x): RSI gate passa (faixa saudavel)' {
        # DUSKUSDT no snapshot 10:13: RSI 54.4, vol 0.36x.
        Test-ScanPreScreen -Rsi 54.4 -Adx 27.3 -Vol 0.36 | Should Be $true
    }

    It 'RSI saudavel com ADX baixo: RSI gate passa (ADX gate eh separado)' {
        Test-ScanPreScreen -Rsi 50 -Adx 5 -Vol 0.1 | Should Be $true
    }

    It 'RSI 78 boundary (saudavel): passa sem confluencia obrigatoria' {
        Test-ScanPreScreen -Rsi 78 -Adx 18 -Vol 0.5 | Should Be $true
    }

    It 'RSI 28 boundary inferior (saudavel): passa sem confluencia' {
        Test-ScanPreScreen -Rsi 28 -Adx 10 -Vol 0.1 | Should Be $true
    }

    It 'RSI 78-88 breakout: AINDA exige confluencia vol+ADX (breakout = confluencia E o sinal)' {
        # Faixa de breakout: vol>=1.5 AND adx>=25 (regra existente preservada)
        Test-ScanPreScreen -Rsi 82 -Adx 28 -Vol 2.0 | Should Be $true
        Test-ScanPreScreen -Rsi 82 -Adx 28 -Vol 1.0 | Should Be $false
        Test-ScanPreScreen -Rsi 82 -Adx 20 -Vol 2.0 | Should Be $false
    }

    It 'RSI > 88: rejeita sempre (overextended)' {
        Test-ScanPreScreen -Rsi 90 -Adx 50 -Vol 5.0 | Should Be $false
    }

    It 'RSI < 28: rejeita sempre (oversold sem trigger)' {
        Test-ScanPreScreen -Rsi 25 -Adx 50 -Vol 5.0 | Should Be $false
    }
}


Describe 'scan_master Bug B - Top-N ranking via score composto' {

    It 'Funcao Get-ScannerCompositeScore esta definida' {
        (Get-Command Get-ScannerCompositeScore -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
    }

    It 'ADX=30+vol=4x+momentum=10 vence ADX=95+vol=0.2x+momentum=1' {
        $fresh = Get-ScannerCompositeScore -VolSpike 4.0 -MomentumPct 10.0 -Adx 30
        $stale = Get-ScannerCompositeScore -VolSpike 0.2 -MomentumPct 1.0  -Adx 95
        ($fresh -gt $stale) | Should Be $true
    }

    It 'Score composto considera vol_spike, momentum e ADX saudavel' {
        $zero = Get-ScannerCompositeScore -VolSpike 0 -MomentumPct 0 -Adx 0
        $real = Get-ScannerCompositeScore -VolSpike 2.0 -MomentumPct 5.0 -Adx 40
        $zero | Should Be 0
        ($real -gt 0) | Should Be $true
    }

    It 'ADX maior que 90 PENALIZA score (exausto, nao amplifica)' {
        $exhausted = Get-ScannerCompositeScore -VolSpike 2.0 -MomentumPct 5.0 -Adx 95
        $healthy   = Get-ScannerCompositeScore -VolSpike 2.0 -MomentumPct 5.0 -Adx 70
        ($healthy -gt $exhausted) | Should Be $true
    }

    It 'Empate em ADX/momentum quebra por volume descendente' {
        $hiVol = Get-ScannerCompositeScore -VolSpike 5.0 -MomentumPct 3.0 -Adx 40
        $loVol = Get-ScannerCompositeScore -VolSpike 1.0 -MomentumPct 3.0 -Adx 40
        ($hiVol -gt $loVol) | Should Be $true
    }

    It 'Cenario HYPE 14/05: vol=4.46x momentum=20 adx=29 vence ADX-saturado 95' {
        $hype  = Get-ScannerCompositeScore -VolSpike 4.46 -MomentumPct 20.0 -Adx 29
        $stale = Get-ScannerCompositeScore -VolSpike 0.5  -MomentumPct 1.0  -Adx 95
        ($hype -gt $stale) | Should Be $true
    }
}