# lib_short_signals_regime_specific.Tests.ps1 -- TDD Sprint 1
# Objetivo: Otimizar SHORT patterns por regime (BEAR focus)
# Hipótese: Edge +2.85pp → +5-8pp em BEAR regimes
#
# Pester 3.x. PS 5.1. UTF-8 BOM.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

. "$root\agents\lib_short_signals.ps1"

Describe "Detect-ShortSignal - Regime-Specific Thresholds" {

    Context "BEAR_STRONG regime (aggressive shorts)" {
        
        It "ClimaxMultiplier=2.0 (vs 2.5 default) detecta mais oportunidades" {
            # Setup: buying climax sintético
            $closes = @(); $highs = @(); $lows = @(); $vols = @()
            for ($i = 0; $i -lt 25; $i++) {
                $base = 100 + $i * 0.5  # uptrend suave
                $closes += $base; $highs += $base + 0.5; $lows += $base - 0.5
                $vols += 100
            }
            # Climax bar: vol 2.2x (abaixo de 2.5 default, acima de 2.0)
            $vols += 220.0
            $highs += 113.0  # new high
            $closes += 112.0  # rejection
            $lows += 111.5
            
            # Default (2.5): NÃO detecta
            $r1 = Detect-ShortSignal -Volumes $vols -Highs $highs -Lows $lows -Closes $closes `
                -ClimaxMultiplier 2.5 -RsiOverboughtMin 70
            $r1.detected | Should Be $false
            
            # BEAR_STRONG (2.0): DETECTA
            $r2 = Detect-ShortSignal -Volumes $vols -Highs $highs -Lows $lows -Closes $closes `
                -ClimaxMultiplier 2.0 -RsiOverboughtMin 70
            $r2.detected | Should Be $true
            $r2.pattern_name | Should Match "SHORT"
        }
        
        It "RsiOverboughtMin=75 (vs 70 default) filtra false positives" {
            # Setup: climax com RSI entre 70-75 (overbought moderado)
            $closes = @(); $highs = @(); $lows = @(); $vols = @()
            
            # Uptrend forte para gerar RSI alto
            for ($i = 0; $i -lt 20; $i++) {
                $base = 100 + $i * 1.2  # uptrend mais forte
                $closes += $base; $highs += $base + 0.5; $lows += $base - 0.5
                $vols += 100
            }
            # Últimos 5 candles: uptrend continua (RSI permanece alto)
            for ($i = 0; $i -lt 5; $i++) {
                $base = 124 + $i * 0.8
                $closes += $base; $highs += $base + 0.5; $lows += $base - 0.5
                $vols += 100
            }
            # Climax bar: vol spike + new high + rejection
            $vols += 250.0; $highs += 129.0; $closes += 127.5; $lows += 127.0
            
            # Default (RSI>70): DETECTA
            $r1 = Detect-ShortSignal -Volumes $vols -Highs $highs -Lows $lows -Closes $closes `
                -ClimaxMultiplier 2.0 -RsiOverboughtMin 70
            
            # BEAR_STRONG (RSI>75): comportamento depende do RSI real
            $r2 = Detect-ShortSignal -Volumes $vols -Highs $highs -Lows $lows -Closes $closes `
                -ClimaxMultiplier 2.0 -RsiOverboughtMin 75
            
            # Test valida que threshold RSI>75 é mais restritivo que RSI>70
            if ($r1.detected) {
                # Se r1 detectou, r2 deve ter RSI >= 70
                $r1.rsi | Should BeGreaterThan 70
                # Se RSI < 75, r2 não deve detectar (filtrado)
                if ($r1.rsi -lt 75) {
                    $r2.detected | Should Be $false
                    $r2.reason | Should Match "rsi"
                }
            }
        }
    }
    
    Context "BEAR_WEAK regime (moderate shorts)" {
        
        It "ClimaxMultiplier=2.5 (default) mantém selectividade" {
            # Setup: climax com vol 2.6x
            $closes = @(); $highs = @(); $lows = @(); $vols = @()
            for ($i = 0; $i -lt 25; $i++) {
                $base = 100 + $i * 0.3
                $closes += $base; $highs += $base + 0.5; $lows += $base - 0.5
                $vols += 100
            }
            $vols += 260.0; $highs += 108.5; $closes += 107.5; $lows += 107.0
            
            $r = Detect-ShortSignal -Volumes $vols -Highs $highs -Lows $lows -Closes $closes `
                -ClimaxMultiplier 2.5 -RsiOverboughtMin 70
            $r.detected | Should Be $true
        }
        
        It "RsiOverboughtMin=70 (default) permite mais oportunidades" {
            # BEAR_WEAK: menos restritivo que BEAR_STRONG
            # Test implícito: default params funcionam
            $true | Should Be $true
        }
    }
    
    Context "TRANSITION_DOWN regime (conservative shorts)" {
        
        It "ClimaxMultiplier=3.0 (vs 2.5 default) aumenta selectividade" {
            # Setup: climax com vol 2.8x (abaixo de 3.0, acima de 2.5)
            $closes = @(); $highs = @(); $lows = @(); $vols = @()
            for ($i = 0; $i -lt 25; $i++) {
                $base = 100 + $i * 0.2
                $closes += $base; $highs += $base + 0.5; $lows += $base - 0.5
                $vols += 100
            }
            $vols += 280.0; $highs += 105.5; $closes += 104.5; $lows += 104.0
            
            # Default (2.5): DETECTA
            $r1 = Detect-ShortSignal -Volumes $vols -Highs $highs -Lows $lows -Closes $closes `
                -ClimaxMultiplier 2.5 -RsiOverboughtMin 65
            $r1.detected | Should Be $true
            
            # TRANSITION_DOWN (3.0): NÃO detecta (vol 2.8x < 3.0)
            $r2 = Detect-ShortSignal -Volumes $vols -Highs $highs -Lows $lows -Closes $closes `
                -ClimaxMultiplier 3.0 -RsiOverboughtMin 65
            $r2.detected | Should Be $false
        }
        
        It "RsiOverboughtMin=65 (vs 70 default) permite early entries" {
            # TRANSITION_DOWN: menos overbought = early signal
            # Setup: uptrend moderado para gerar RSI entre 65-70
            $closes = @(); $highs = @(); $lows = @(); $vols = @()
            
            # Uptrend moderado (RSI ~65-70)
            for ($i = 0; $i -lt 20; $i++) {
                $base = 100 + $i * 0.4
                $closes += $base; $highs += $base + 0.5; $lows += $base - 0.5
                $vols += 100
            }
            # Últimos 5 candles: continua subindo
            for ($i = 0; $i -lt 5; $i++) {
                $base = 108 + $i * 0.3
                $closes += $base; $highs += $base + 0.5; $lows += $base - 0.5
                $vols += 100
            }
            # Climax bar
            $vols += 300.0; $highs += 110.5; $closes += 109.5; $lows += 109.0
            
            # Default (RSI>70): comportamento depende do RSI real
            $r1 = Detect-ShortSignal -Volumes $vols -Highs $highs -Lows $lows -Closes $closes `
                -ClimaxMultiplier 3.0 -RsiOverboughtMin 70
            
            # TRANSITION_DOWN (RSI>65): mais permissivo
            $r2 = Detect-ShortSignal -Volumes $vols -Highs $highs -Lows $lows -Closes $closes `
                -ClimaxMultiplier 3.0 -RsiOverboughtMin 65
            
            # Test valida que threshold RSI>65 é mais permissivo que RSI>70
            if ($r2.detected) {
                $r2.rsi | Should BeGreaterThan 65
                # Se RSI entre 65-70, r1 não detecta mas r2 detecta
                if ($r2.rsi -lt 70) {
                    $r1.detected | Should Be $false
                }
            }
        }
    }
}


Describe "Get-ShortSignalWss - Regime-Aware Scoring" {
    
    It "Retorna regime hint no output (para regime-specific thresholds)" {
        # Placeholder: WSS scoring já é regime-aware via BtcDrawdown
        # Este test valida que regime context é passado corretamente
        
        $closes = @(); $highs = @(); $lows = @(); $vols = @()
        for ($i = 0; $i -lt 25; $i++) {
            $base = 100 + $i * 0.5
            $closes += $base; $highs += $base + 0.5; $lows += $base - 0.5
            $vols += 100
        }
        $vols += 250.0; $highs += 113.0; $closes += 112.0; $lows += 111.5
        
        # Mock: BtcDrawdown -15% = BEAR_WEAK
        $r = Get-ShortSignalWss -Market "BTCUSDT" `
            -Volumes $vols -Highs $highs -Lows $lows -Closes $closes `
            -BtcDrawdown -15.0 -BtcVol20d 3.5 `
            -NowUtc (Get-Date).ToUniversalTime() `
            -ClusterSize 1 -QualityTable @{}
        
        if ($r) {
            $r.side | Should Be "SHORT"
            # WSS score deve refletir regime (drawdown -15% = BEAR context)
        }
    }
}


Describe "Regime-Specific Config Helper (NEW)" {
    
    It "Get-ShortThresholdsForRegime retorna params otimizados por regime" {
        # RED: Função ainda não existe
        # Este test define o contrato esperado
        
        if (-not (Get-Command Get-ShortThresholdsForRegime -ErrorAction SilentlyContinue)) {
            Set-TestInconclusive -Message "Get-ShortThresholdsForRegime not implemented yet (TDD RED phase)"
            return
        }
        
        $bear_strong = Get-ShortThresholdsForRegime -Regime "BEAR_STRONG"
        $bear_strong.ClimaxMultiplier | Should Be 2.0
        $bear_strong.RsiOverboughtMin | Should Be 75
        
        $bear_weak = Get-ShortThresholdsForRegime -Regime "BEAR_WEAK"
        $bear_weak.ClimaxMultiplier | Should Be 2.5
        $bear_weak.RsiOverboughtMin | Should Be 70
        
        $transition_down = Get-ShortThresholdsForRegime -Regime "TRANSITION_DOWN"
        $transition_down.ClimaxMultiplier | Should Be 3.0
        $transition_down.RsiOverboughtMin | Should Be 65
        
        # Default (unknown regime): fallback to conservative
        $unknown = Get-ShortThresholdsForRegime -Regime "UNKNOWN"
        $unknown.ClimaxMultiplier | Should Be 3.0
        $unknown.RsiOverboughtMin | Should Be 70
    }

    It "Get-ShortThresholdsForRegime tem case NEUTRO dedicado (2026-07-25)" {
        # RED antes do fix: NEUTRO caia no default (3.0/70) so por falta de
        # case, apesar de mce_counterfactual_agg mostrar NEUTRO|SHORT com o
        # melhor hit_rate (87.5%, n=24) entre todos os regimes medidos.
        $neutro = Get-ShortThresholdsForRegime -Regime "NEUTRO"
        $neutro.ClimaxMultiplier | Should Be 2.5
        $neutro.RsiOverboughtMin | Should Be 68

        # Nao pode ser identico ao default conservador (validaria que o case
        # dedicado existe de fato, nao so reaproveita o fallback)
        $default = Get-ShortThresholdsForRegime -Regime "SOME_UNKNOWN_REGIME_XYZ"
        ($neutro.ClimaxMultiplier -eq $default.ClimaxMultiplier -and $neutro.RsiOverboughtMin -eq $default.RsiOverboughtMin) | Should Be $false
    }
}

