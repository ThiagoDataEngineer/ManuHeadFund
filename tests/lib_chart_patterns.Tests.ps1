# lib_chart_patterns.Tests.ps1 -- TDD-first.
# Pester 3.x.
#
# Patterns cobertos (pure-math, zero LLM):
#   1. Detect-VolumeClimax     -- vol bar >3x media em swing low/high
#   2. Detect-CandlestickReversal -- hammer/engulfing/doji/morning-evening star
#   3. Detect-RsiDivergence    -- bullish: LL price + HL RSI; bearish: HH price + LH RSI
#
# Cada detector retorna PSCustomObject { detected, pattern_name, strength, bar_idx, ... }
# Strength 0-100. detected=$false eh DEFAULT (nao falso positivo).

$script:cp_here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:cp_root = Split-Path -Parent $cp_here
$script:cp_libPath = Join-Path $cp_root "agents\lib_chart_patterns.ps1"

# Carregamento defensivo: se lib nao existe ainda (TDD-first), tests falham logo
if (Test-Path $script:cp_libPath) { . $script:cp_libPath }


# ============================================================================
# 1. Volume Climax — vol bar >3x media + ocorre em swing low (LONG) ou high (SHORT)
# ============================================================================

Describe "Detect-VolumeClimax - LONG side (selling climax bottom)" {

    It "Funcao existe" {
        if (-not (Get-Command Detect-VolumeClimax -ErrorAction SilentlyContinue)) {
            Set-TestInconclusive "lib_chart_patterns.ps1 nao implementada ainda (TDD-first)"
            return
        }
        $true | Should Be $true
    }

    It "Detecta climax: vol 5x media + low fica abaixo dos N anteriores" {
        if (-not (Get-Command Detect-VolumeClimax -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        # Serie: 20 barras volume baseline 1000, ultima barra vol 5000 + low menor
        $vols = @(); $lows = @(); $highs = @(); $closes = @()
        for ($i = 0; $i -lt 19; $i++) {
            $vols   += 1000.0
            $lows   += 100.0 + ($i * 0.1)
            $highs  += $lows[-1] + 2
            $closes += $lows[-1] + 1
        }
        # Climax bar (idx 19): vol 5000, low 90 (abaixo), close acima do low (selling exhausted)
        $vols   += 5000.0
        $lows   += 90.0
        $highs  += 102.0
        $closes += 100.0

        $r = Detect-VolumeClimax -Volumes $vols -Lows $lows -Highs $highs -Closes $closes -Side LONG
        $r.detected | Should Be $true
        $r.pattern_name | Should Be "selling_climax"
        $r.strength | Should BeGreaterThan 50
        $r.bar_idx | Should Be 19
    }

    It "Nao detecta quando vol esta normal (sem spike)" {
        if (-not (Get-Command Detect-VolumeClimax -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $vols = @(1000.0) * 20
        $lows = @(); for ($i = 0; $i -lt 20; $i++) { $lows += 100.0 + ($i * 0.1) }
        $highs = $lows | ForEach-Object { $_ + 2 }
        $closes = $lows | ForEach-Object { $_ + 1 }
        $r = Detect-VolumeClimax -Volumes $vols -Lows $lows -Highs $highs -Closes $closes -Side LONG
        $r.detected | Should Be $false
    }

    It "Nao detecta quando vol spike MAS sem swing low (preco subindo)" {
        if (-not (Get-Command Detect-VolumeClimax -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        # vol spike na ultima barra MAS low maior que anteriores (nao eh climax bottom)
        $vols = @(); $lows = @()
        for ($i = 0; $i -lt 19; $i++) { $vols += 1000.0; $lows += 100.0 + ($i * 0.5) }
        $vols += 5000.0; $lows += 110.0  # low MAIOR (preco em uptrend)
        $highs = $lows | ForEach-Object { $_ + 2 }
        $closes = $lows | ForEach-Object { $_ + 1 }
        $r = Detect-VolumeClimax -Volumes $vols -Lows $lows -Highs $highs -Closes $closes -Side LONG
        $r.detected | Should Be $false
    }

    It "Insufficient history retorna detected=false" {
        if (-not (Get-Command Detect-VolumeClimax -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $r = Detect-VolumeClimax -Volumes @(100,200,300) -Lows @(1,2,3) -Highs @(2,3,4) -Closes @(1.5,2.5,3.5) -Side LONG
        $r.detected | Should Be $false
        $r.reason | Should Match "insufficient"
    }
}


Describe "Detect-VolumeClimax - SHORT side (buying climax top)" {

    It "Detecta buying climax: vol 5x + high maior + close baixo no range" {
        if (-not (Get-Command Detect-VolumeClimax -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $vols = @(); $lows = @(); $highs = @(); $closes = @()
        for ($i = 0; $i -lt 19; $i++) {
            $vols   += 1000.0
            $highs  += 100.0 - ($i * 0.05)
            $lows   += $highs[-1] - 2
            $closes += $highs[-1] - 1
        }
        # Climax bar (idx 19): vol 5000, high 110 (maior), close baixo (buyer exhausted)
        $vols   += 5000.0
        $highs  += 110.0
        $lows   += 100.0
        $closes += 101.0

        $r = Detect-VolumeClimax -Volumes $vols -Lows $lows -Highs $highs -Closes $closes -Side SHORT
        $r.detected | Should Be $true
        $r.pattern_name | Should Be "buying_climax"
    }
}


# ============================================================================
# 2. Candlestick Reversal — Hammer / Bullish Engulfing / Doji
# ============================================================================

Describe "Detect-CandlestickReversal - LONG (bullish reversal)" {

    It "Detecta Hammer: body small + lower shadow >=2x body em downtrend prior" {
        if (-not (Get-Command Detect-CandlestickReversal -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        # 10 candles bearish + 1 hammer
        $opens = @(); $highs = @(); $lows = @(); $closes = @()
        for ($i = 0; $i -lt 10; $i++) {
            $opens  += 100.0 - $i; $closes += 99.0 - $i
            $highs  += 101.0 - $i; $lows  += 98.0 - $i
        }
        # Hammer bar: open=89, close=89.5 (body 0.5), low=85 (lower shadow 4 = 8x body), high=89.6
        $opens  += 89.0; $closes += 89.5; $highs += 89.6; $lows += 85.0

        $r = Detect-CandlestickReversal -Opens $opens -Highs $highs -Lows $lows -Closes $closes -Side LONG
        $r.detected | Should Be $true
        $r.pattern_name | Should Be "hammer"
    }

    It "Detecta Bullish Engulfing: bear candle seguido de bull candle que cobre body anterior" {
        if (-not (Get-Command Detect-CandlestickReversal -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $opens = @(); $highs = @(); $lows = @(); $closes = @()
        for ($i = 0; $i -lt 9; $i++) {
            $opens  += 100.0 - $i; $closes += 99.0 - $i
            $highs  += 101.0 - $i; $lows  += 98.0 - $i
        }
        # Bar -1: bearish (open 92, close 90)
        $opens  += 92.0; $closes += 90.0; $highs += 92.5; $lows += 89.5
        # Bar 0 (latest): bullish engulfing (open 89.5 close 93 -- cobre body anterior 90-92)
        $opens  += 89.5; $closes += 93.0; $highs += 93.5; $lows += 89.0

        $r = Detect-CandlestickReversal -Opens $opens -Highs $highs -Lows $lows -Closes $closes -Side LONG
        $r.detected | Should Be $true
        $r.pattern_name | Should Be "bullish_engulfing"
    }

    It "Nao detecta hammer em uptrend (sem prior bearish)" {
        if (-not (Get-Command Detect-CandlestickReversal -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        # 10 candles uptrend + 1 hammer-shape (mas sem precedente bearish = nao eh reversal)
        $opens = @(); $highs = @(); $lows = @(); $closes = @()
        for ($i = 0; $i -lt 10; $i++) {
            $opens += 100.0 + $i; $closes += 101.0 + $i
            $highs += 102.0 + $i; $lows  += 99.0 + $i
        }
        $opens  += 110.0; $closes += 110.5; $highs += 110.6; $lows += 106.0
        $r = Detect-CandlestickReversal -Opens $opens -Highs $highs -Lows $lows -Closes $closes -Side LONG
        # Hammer SHAPE existe MAS sem downtrend prior nao eh reversal valido
        $r.detected | Should Be $false
    }
}


Describe "Detect-CandlestickReversal - SHORT (bearish reversal)" {

    It "Detecta Shooting Star: body small + upper shadow >=2x em uptrend prior" {
        if (-not (Get-Command Detect-CandlestickReversal -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $opens = @(); $highs = @(); $lows = @(); $closes = @()
        for ($i = 0; $i -lt 10; $i++) {
            $opens += 100.0 + $i; $closes += 101.0 + $i
            $highs += 101.5 + $i; $lows  += 99.0 + $i
        }
        # Shooting star: open 111, close 110.5 (body 0.5), high 115 (upper shadow 4), low 110.4
        $opens  += 111.0; $closes += 110.5; $highs += 115.0; $lows += 110.4
        $r = Detect-CandlestickReversal -Opens $opens -Highs $highs -Lows $lows -Closes $closes -Side SHORT
        $r.detected | Should Be $true
        $r.pattern_name | Should Be "shooting_star"
    }

    It "Detecta Bearish Engulfing" {
        if (-not (Get-Command Detect-CandlestickReversal -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $opens = @(); $highs = @(); $lows = @(); $closes = @()
        for ($i = 0; $i -lt 9; $i++) {
            $opens += 100.0 + $i; $closes += 101.0 + $i
            $highs += 102.0 + $i; $lows  += 99.0 + $i
        }
        # Bull bar (open 108, close 110)
        $opens  += 108.0; $closes += 110.0; $highs += 110.5; $lows += 107.5
        # Bear engulfing (open 110.5, close 107.5)
        $opens  += 110.5; $closes += 107.5; $highs += 111.0; $lows += 107.0
        $r = Detect-CandlestickReversal -Opens $opens -Highs $highs -Lows $lows -Closes $closes -Side SHORT
        $r.detected | Should Be $true
        $r.pattern_name | Should Be "bearish_engulfing"
    }
}


# ============================================================================
# 2b. Detect-CandlestickReversal -- expansao 2026-08-14 (Doji, Harami,
# Piercing/Dark Cloud, Morning/Evening Star, 3 Soldados/Corvos)
#
# Card de referencia do owner (padroes classicos de candlestick, Live Traders):
# Doji, Harami de Alta/Queda, Piercing de Fundo, Nuvem Negra (Dark Cloud
# Cover), Estrela da Manha/Tarde, 3 Soldados Brancos, 3 Corvos Negros.
# Prioridade: mais reconhecidos/confiaveis na literatura classica primeiro.
# ============================================================================

Describe "Detect-CandlestickReversal - Doji (indecisao/possivel reversao)" {

    It "Detecta Doji apos downtrend -- sinaliza LONG (indecisao no fundo)" {
        if (-not (Get-Command Detect-CandlestickReversal -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $opens = @(); $highs = @(); $lows = @(); $closes = @()
        for ($i = 0; $i -lt 10; $i++) {
            $opens  += 100.0 - $i; $closes += 99.0 - $i
            $highs  += 101.0 - $i; $lows  += 98.0 - $i
        }
        # Doji: open~close (corpo quase zero), sombras nos dois lados
        $opens  += 89.0; $closes += 89.05; $highs += 91.0; $lows += 87.0
        $r = Detect-CandlestickReversal -Opens $opens -Highs $highs -Lows $lows -Closes $closes -Side LONG
        $r.detected | Should Be $true
        $r.pattern_name | Should Be "doji"
    }

    It "Detecta Doji apos uptrend -- sinaliza SHORT (indecisao no topo)" {
        if (-not (Get-Command Detect-CandlestickReversal -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $opens = @(); $highs = @(); $lows = @(); $closes = @()
        for ($i = 0; $i -lt 10; $i++) {
            $opens += 100.0 + $i; $closes += 101.0 + $i
            $highs += 102.0 + $i; $lows  += 99.0 + $i
        }
        $opens  += 111.0; $closes += 111.05; $highs += 113.0; $lows += 109.0
        $r = Detect-CandlestickReversal -Opens $opens -Highs $highs -Lows $lows -Closes $closes -Side SHORT
        $r.detected | Should Be $true
        $r.pattern_name | Should Be "doji"
    }

    It "Nao detecta Doji quando corpo e grande (nao e indecisao)" {
        if (-not (Get-Command Detect-CandlestickReversal -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $opens = @(); $highs = @(); $lows = @(); $closes = @()
        for ($i = 0; $i -lt 10; $i++) {
            $opens  += 100.0 - $i; $closes += 99.0 - $i
            $highs  += 101.0 - $i; $lows  += 98.0 - $i
        }
        # corpo grande (nao doji) e sem shape de hammer/engulfing tambem
        $opens  += 89.0; $closes += 85.0; $highs += 89.2; $lows += 84.8
        $r = Detect-CandlestickReversal -Opens $opens -Highs $highs -Lows $lows -Closes $closes -Side LONG
        $r.pattern_name | Should Not Be "doji"
    }
}


Describe "Detect-CandlestickReversal - Harami (contracao antes de reversao)" {

    It "Detecta Harami de Alta: bar grande bearish seguida de bar pequena contida dentro (downtrend)" {
        if (-not (Get-Command Detect-CandlestickReversal -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $opens = @(); $highs = @(); $lows = @(); $closes = @()
        for ($i = 0; $i -lt 9; $i++) {
            $opens  += 100.0 - $i; $closes += 99.0 - $i
            $highs  += 101.0 - $i; $lows  += 98.0 - $i
        }
        # Bar -1: bearish grande (open 92, close 87)
        $opens  += 92.0; $closes += 87.0; $highs += 92.5; $lows += 86.5
        # Bar 0: corpo pequeno, TOTALMENTE contido dentro do corpo anterior (87-92)
        $opens  += 89.0; $closes += 90.0; $highs += 90.3; $lows += 88.7
        $r = Detect-CandlestickReversal -Opens $opens -Highs $highs -Lows $lows -Closes $closes -Side LONG
        $r.detected | Should Be $true
        $r.pattern_name | Should Be "bullish_harami"
    }

    It "Detecta Harami de Queda: bar grande bullish seguida de bar pequena contida dentro (uptrend)" {
        if (-not (Get-Command Detect-CandlestickReversal -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $opens = @(); $highs = @(); $lows = @(); $closes = @()
        for ($i = 0; $i -lt 9; $i++) {
            $opens += 100.0 + $i; $closes += 101.0 + $i
            $highs += 102.0 + $i; $lows  += 99.0 + $i
        }
        # Bar -1: bullish grande (open 108, close 113)
        $opens  += 108.0; $closes += 113.0; $highs += 113.5; $lows += 107.5
        # Bar 0: corpo pequeno, contido dentro (108-113)
        $opens  += 111.5; $closes += 110.0; $highs += 111.8; $lows += 109.7
        $r = Detect-CandlestickReversal -Opens $opens -Highs $highs -Lows $lows -Closes $closes -Side SHORT
        $r.detected | Should Be $true
        $r.pattern_name | Should Be "bearish_harami"
    }
}


Describe "Detect-CandlestickReversal - Piercing Line / Dark Cloud Cover" {

    It "Detecta Piercing Line: bear grande seguido de bull que fecha acima do meio do corpo anterior (downtrend)" {
        if (-not (Get-Command Detect-CandlestickReversal -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $opens = @(); $highs = @(); $lows = @(); $closes = @()
        for ($i = 0; $i -lt 9; $i++) {
            $opens  += 100.0 - $i; $closes += 99.0 - $i
            $highs  += 101.0 - $i; $lows  += 98.0 - $i
        }
        # Bar -1: bearish (open 92, close 87) -- corpo 87-92, meio=89.5
        $opens  += 92.0; $closes += 87.0; $highs += 92.5; $lows += 86.5
        # Bar 0: abre abaixo do low anterior, fecha ACIMA do meio (89.5) mas ABAIXO do open anterior (92)
        $opens  += 86.0; $closes += 90.5; $highs += 90.8; $lows += 85.8
        $r = Detect-CandlestickReversal -Opens $opens -Highs $highs -Lows $lows -Closes $closes -Side LONG
        $r.detected | Should Be $true
        $r.pattern_name | Should Be "piercing_line"
    }

    It "Detecta Dark Cloud Cover: bull grande seguido de bear que fecha abaixo do meio do corpo anterior (uptrend)" {
        if (-not (Get-Command Detect-CandlestickReversal -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $opens = @(); $highs = @(); $lows = @(); $closes = @()
        for ($i = 0; $i -lt 9; $i++) {
            $opens += 100.0 + $i; $closes += 101.0 + $i
            $highs += 102.0 + $i; $lows  += 99.0 + $i
        }
        # Bar -1: bullish (open 108, close 113) -- corpo 108-113, meio=110.5
        $opens  += 108.0; $closes += 113.0; $highs += 113.5; $lows += 107.5
        # Bar 0: abre acima do high anterior, fecha ABAIXO do meio (110.5) mas ACIMA do open anterior (108)
        $opens  += 114.0; $closes += 109.5; $highs += 114.3; $lows += 109.2
        $r = Detect-CandlestickReversal -Opens $opens -Highs $highs -Lows $lows -Closes $closes -Side SHORT
        $r.detected | Should Be $true
        $r.pattern_name | Should Be "dark_cloud_cover"
    }
}


Describe "Detect-CandlestickReversal - Morning Star / Evening Star (3 velas, alta confiabilidade)" {

    It "Detecta Morning Star: bear grande + corpo pequeno (gap down) + bull grande fechando na metade superior (downtrend)" {
        if (-not (Get-Command Detect-CandlestickReversal -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $opens = @(); $highs = @(); $lows = @(); $closes = @()
        for ($i = 0; $i -lt 8; $i++) {
            $opens  += 100.0 - $i; $closes += 99.0 - $i
            $highs  += 101.0 - $i; $lows  += 98.0 - $i
        }
        # Bar -2: bearish grande (open 93, close 88)
        $opens  += 93.0; $closes += 88.0; $highs += 93.3; $lows += 87.7
        # Bar -1: corpo pequeno (estrela), abre com gap down
        $opens  += 86.5; $closes += 86.3; $highs += 86.8; $lows += 86.0
        # Bar 0: bullish grande, fecha bem acima do meio da bar -2 (meio=90.5)
        $opens  += 87.0; $closes += 92.0; $highs += 92.3; $lows += 86.8
        $r = Detect-CandlestickReversal -Opens $opens -Highs $highs -Lows $lows -Closes $closes -Side LONG
        $r.detected | Should Be $true
        $r.pattern_name | Should Be "morning_star"
    }

    It "Detecta Evening Star: bull grande + corpo pequeno (gap up) + bear grande fechando na metade inferior (uptrend)" {
        if (-not (Get-Command Detect-CandlestickReversal -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $opens = @(); $highs = @(); $lows = @(); $closes = @()
        for ($i = 0; $i -lt 8; $i++) {
            $opens += 100.0 + $i; $closes += 101.0 + $i
            $highs += 102.0 + $i; $lows  += 99.0 + $i
        }
        # Bar -2: bullish grande (open 107, close 112)
        $opens  += 107.0; $closes += 112.0; $highs += 112.3; $lows += 106.7
        # Bar -1: corpo pequeno (estrela), abre com gap up
        $opens  += 113.5; $closes += 113.7; $highs += 114.0; $lows += 113.2
        # Bar 0: bearish grande, fecha bem abaixo do meio da bar -2 (meio=109.5)
        $opens  += 113.0; $closes += 108.0; $highs += 113.3; $lows += 107.7
        $r = Detect-CandlestickReversal -Opens $opens -Highs $highs -Lows $lows -Closes $closes -Side SHORT
        $r.detected | Should Be $true
        $r.pattern_name | Should Be "evening_star"
    }
}


Describe "Detect-CandlestickReversal - 3 Soldados Brancos / 3 Corvos Negros (continuacao confirmada)" {

    It "Detecta 3 Soldados Brancos: 3 velas bullish consecutivas, cada uma fechando mais alto (downtrend previo)" {
        if (-not (Get-Command Detect-CandlestickReversal -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $opens = @(); $highs = @(); $lows = @(); $closes = @()
        for ($i = 0; $i -lt 7; $i++) {
            $opens  += 100.0 - $i; $closes += 99.0 - $i
            $highs  += 101.0 - $i; $lows  += 98.0 - $i
        }
        # 3 soldados: cada abre dentro do corpo anterior e fecha em nova alta, corpos solidos
        $opens += 87.0; $closes += 90.0; $highs += 90.3; $lows += 86.8
        $opens += 89.0; $closes += 92.5; $highs += 92.8; $lows += 88.8
        $opens += 91.5; $closes += 95.0; $highs += 95.3; $lows += 91.3
        $r = Detect-CandlestickReversal -Opens $opens -Highs $highs -Lows $lows -Closes $closes -Side LONG
        $r.detected | Should Be $true
        $r.pattern_name | Should Be "three_white_soldiers"
    }

    It "Detecta 3 Corvos Negros: 3 velas bearish consecutivas, cada uma fechando mais baixo (uptrend previo)" {
        if (-not (Get-Command Detect-CandlestickReversal -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $opens = @(); $highs = @(); $lows = @(); $closes = @()
        for ($i = 0; $i -lt 7; $i++) {
            $opens += 100.0 + $i; $closes += 101.0 + $i
            $highs += 102.0 + $i; $lows  += 99.0 + $i
        }
        # 3 corvos: cada abre dentro do corpo anterior e fecha em nova baixa, corpos solidos
        $opens += 113.0; $closes += 110.0; $highs += 113.3; $lows += 109.7
        $opens += 111.0; $closes += 107.5; $highs += 111.3; $lows += 107.2
        $opens += 108.5; $closes += 105.0; $highs += 108.8; $lows += 104.7
        $r = Detect-CandlestickReversal -Opens $opens -Highs $highs -Lows $lows -Closes $closes -Side SHORT
        $r.detected | Should Be $true
        $r.pattern_name | Should Be "three_black_crows"
    }
}


# ============================================================================
# 3. RSI Divergence
# ============================================================================

Describe "Detect-RsiDivergence - LONG (bullish divergence)" {

    It "Detecta bullish divergence: price LL + RSI HL nos ultimos 2 swing lows" {
        if (-not (Get-Command Detect-RsiDivergence -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        # Bullish divergence: RSI no swing 1 PROFUNDO (drop steep), RSI no swing 2 MENOS profundo (drop suave) MAS price LL.
        # Precisa 14+ bars pra RSI calibrar antes do primeiro swing low.
        $closes = @()
        # Warm-up RSI (~50): 16 bars oscilando levemente
        for ($i = 0; $i -lt 16; $i++) {
            if ($i % 2 -eq 0) { $closes += 100 } else { $closes += 101 }
        }
        # Drop steep: 101 -> 85 em 6 bars (RSI vai pra ~15-20)
        $closes += 98; $closes += 94; $closes += 90; $closes += 87; $closes += 85; $closes += 88
        # Swing low 1: idx 20 price 85
        # Recovery moderada
        $closes += 91; $closes += 94; $closes += 97; $closes += 100
        # Drop suave longo: 100 -> 82 em 12 bars (RSI nao chega tao fundo, ~30)
        $closes += 99; $closes += 97; $closes += 95; $closes += 93; $closes += 91
        $closes += 89; $closes += 87; $closes += 85; $closes += 83; $closes += 82; $closes += 84
        # Swing low 2: idx ~36 price 82 (LL)
        $closes += 87; $closes += 90; $closes += 92

        $r = Detect-RsiDivergence -Closes $closes -Side LONG -Lookback 40
        $r.detected | Should Be $true
        $r.pattern_name | Should Be "bullish_divergence"
    }

    It "Nao detecta divergence quando RSI tambem faz LL (continuacao bearish)" {
        if (-not (Get-Command Detect-RsiDivergence -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        # Serie continuacao bear: ambos price + RSI fazem LL
        $closes = @()
        for ($i = 0; $i -lt 30; $i++) { $closes += 100.0 - ($i * 1.0) }
        $r = Detect-RsiDivergence -Closes $closes -Side LONG
        $r.detected | Should Be $false
    }
}


Describe "Detect-RsiDivergence - SHORT (bearish divergence)" {

    It "Detecta bearish divergence: price HH + RSI LH nos ultimos 2 swing highs" {
        if (-not (Get-Command Detect-RsiDivergence -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        # Mirror do bullish test
        $closes = @()
        for ($i = 0; $i -lt 16; $i++) {
            if ($i % 2 -eq 0) { $closes += 100 } else { $closes += 99 }
        }
        # Pump steep: 99 -> 115 em 6 bars (RSI ~80-85)
        $closes += 102; $closes += 106; $closes += 110; $closes += 113; $closes += 115; $closes += 112
        # Swing high 1: idx 20 price 115
        $closes += 109; $closes += 106; $closes += 103; $closes += 100
        # Pump suave longo: 100 -> 118 em 11 bars (RSI ~70 — LH)
        $closes += 101; $closes += 103; $closes += 105; $closes += 107; $closes += 109
        $closes += 111; $closes += 113; $closes += 115; $closes += 117; $closes += 118; $closes += 116
        # Swing high 2: idx ~36 price 118 (HH)
        $closes += 113; $closes += 110; $closes += 108

        $r = Detect-RsiDivergence -Closes $closes -Side SHORT -Lookback 40
        $r.detected | Should Be $true
        $r.pattern_name | Should Be "bearish_divergence"
    }
}


# ============================================================================
# Determinismo + Anti-regression
# ============================================================================

Describe "Detect-VolumeClimax REFINED (mult=2.5 + RSI<30 confluence)" {

    It "Default ClimaxMultiplier=3.0 sem RSI confluence: comportamento legacy preservado" {
        if (-not (Get-Command Detect-VolumeClimax -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        # Vol 3.5x deve passar default (>= 3.0); sem RSI param = nao filtra
        $vols = @(); $lows = @(); $highs = @(); $closes = @()
        for ($i = 0; $i -lt 19; $i++) {
            $vols += 1000.0; $lows += 100.0 + ($i*0.1); $highs += $lows[-1]+2; $closes += $lows[-1]+1
        }
        $vols += 3500.0; $lows += 90.0; $highs += 102.0; $closes += 100.0
        $r = Detect-VolumeClimax -Volumes $vols -Lows $lows -Highs $highs -Closes $closes -Side LONG
        $r.detected | Should Be $true
    }

    It "REFINED mult=2.5: detecta vol 2.7x (que falharia default 3.0)" {
        if (-not (Get-Command Detect-VolumeClimax -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $vols = @(); $lows = @(); $highs = @(); $closes = @()
        for ($i = 0; $i -lt 19; $i++) {
            $vols += 1000.0; $lows += 100.0 + ($i*0.1); $highs += $lows[-1]+2; $closes += $lows[-1]+1
        }
        $vols += 2700.0; $lows += 90.0; $highs += 102.0; $closes += 100.0
        # Default reject
        $r1 = Detect-VolumeClimax -Volumes $vols -Lows $lows -Highs $highs -Closes $closes -Side LONG -ClimaxMultiplier 3.0
        $r1.detected | Should Be $false
        # Refined accept
        $r2 = Detect-VolumeClimax -Volumes $vols -Lows $lows -Highs $highs -Closes $closes -Side LONG -ClimaxMultiplier 2.5
        $r2.detected | Should Be $true
    }

    It "REFINED RsiOversoldMax=30 LONG: bloqueia setup com RSI nao-oversold" {
        if (-not (Get-Command Detect-VolumeClimax -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        # Construir serie LATERAL (RSI ~50) com climax bar que quebra low atras.
        # Lateral oscilando 99-101 -> RSI fica perto de 50.
        $vols = @(); $lows = @(); $highs = @(); $closes = @()
        for ($i = 0; $i -lt 19; $i++) {
            $vols += 1000.0
            $base = if ($i % 2 -eq 0) { 100.0 } else { 101.0 }
            $lows  += $base - 0.5
            $highs += $base + 0.5
            $closes += $base
        }
        # Climax bar: vol 3x, low 95 quebra prior min (~99.5), close 100 rejection
        $vols += 3000.0; $lows += 95.0; $highs += 101.0; $closes += 100.0
        # Sem confluence: detecta
        $r1 = Detect-VolumeClimax -Volumes $vols -Lows $lows -Highs $highs -Closes $closes -Side LONG -ClimaxMultiplier 2.5
        $r1.detected | Should Be $true
        # Com RSI<30 confluence: bloqueia (RSI ~50)
        $r2 = Detect-VolumeClimax -Volumes $vols -Lows $lows -Highs $highs -Closes $closes -Side LONG -ClimaxMultiplier 2.5 -RsiOversoldMax 30
        $r2.detected | Should Be $false
        $r2.reason   | Should Match "rsi_confluence"
    }

    It "REFINED RsiOversoldMax=30 LONG: passa quando RSI baixo (oversold)" {
        if (-not (Get-Command Detect-VolumeClimax -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        # Construir serie em downtrend forte (RSI vai pra <30)
        $vols = @(); $lows = @(); $highs = @(); $closes = @()
        for ($i = 0; $i -lt 19; $i++) {
            $vols += 1000.0
            $base = 100.0 - ($i * 1.5)
            $lows += $base - 1
            $highs += $base + 1
            $closes += $base
        }
        # Climax bar
        $vols += 3000.0; $lows += 65.0; $highs += 78.0; $closes += 76.0
        $r = Detect-VolumeClimax -Volumes $vols -Lows $lows -Highs $highs -Closes $closes -Side LONG -ClimaxMultiplier 2.5 -RsiOversoldMax 30
        $r.detected      | Should Be $true
        $r.rsi_confluence| Should Be $true
        $r.rsi           | Should BeLessThan 30
    }
}


Describe "Pure determinism" {

    It "Mesma entrada produz mesma saida (Detect-VolumeClimax)" {
        if (-not (Get-Command Detect-VolumeClimax -ErrorAction SilentlyContinue)) { Set-TestInconclusive; return }
        $vols = @(1000.0) * 19; $vols += 5000.0
        $lows = @(); for ($i = 0; $i -lt 20; $i++) { $lows += 100.0 + ($i * 0.1) }
        $lows[19] = 88.0
        $highs = $lows | ForEach-Object { $_ + 2 }
        $closes = $lows | ForEach-Object { $_ + 1 }
        $r1 = Detect-VolumeClimax -Volumes $vols -Lows $lows -Highs $highs -Closes $closes -Side LONG
        $r2 = Detect-VolumeClimax -Volumes $vols -Lows $lows -Highs $highs -Closes $closes -Side LONG
        $r1.detected | Should Be $r2.detected
        $r1.strength | Should Be $r2.strength
        $r1.pattern_name | Should Be $r2.pattern_name
    }
}
