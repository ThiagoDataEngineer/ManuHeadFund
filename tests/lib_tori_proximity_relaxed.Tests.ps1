# lib_tori_proximity_relaxed.Tests.ps1 -- TDD Sprint 2
# Objetivo: Relaxar Tori thresholds para gerar events
# Hipótese: 4-AND → 3-AND ou 2-AND gera 10-50 events/ano
#
# Pester 3.x. PS 5.1. UTF-8 BOM.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

. "$root\agents\lib_tori_proximity.ps1"

Describe "Get-ToriProximityFromArrays - Relaxed Thresholds (3-AND)" {
    
    Context "Remover vol_drying requirement (4-AND → 3-AND)" {
        
        It "setup_ripening=TRUE quando proximity OK + RSI baixo (sem vol_drying)" {
            # Setup: trendline válida + proximity OK + RSI baixo + vol NÃO secando
            $closes = @(); $highs = @(); $lows = @(); $vols = @()
            
            # 15 candles: uptrend suave (trendline válida)
            for ($i = 0; $i -lt 15; $i++) {
                $base = 100 + $i * 0.5
                $closes += $base; $highs += $base + 0.5; $lows += $base - 0.5
                $vols += 1000.0  # vol constante (NÃO secando)
            }
            
            # 10 candles: decline até proximity zone
            for ($i = 0; $i -lt 10; $i++) {
                $base = 107 - $i * 0.3
                $closes += $base; $highs += $base + 0.5; $lows += $base - 0.5
                $vols += 1000.0  # vol constante
            }
            
            # Último candle: próximo da action_line, RSI baixo
            $closes[-1] = $lows[-1] * 1.02  # proximity ~2%
            
            # Atual (4-AND): vol_drying=FALSE → setup_ripening=FALSE
            $r1 = Get-ToriProximityFromArrays -Closes $closes -Highs $highs -Lows $lows -Volumes $vols
            $r1.valid | Should Be $true
            $r1.vol_drying | Should Be $false
            $r1.setup_ripening | Should Be $false  # BLOCKED by vol_drying
            
            # Relaxed (3-AND): ignora vol_drying → setup_ripening=TRUE
            # RED: Função Get-ToriProximityFromArraysRelaxed ainda não existe
            if (Get-Command Get-ToriProximityFromArraysRelaxed -ErrorAction SilentlyContinue) {
                $r2 = Get-ToriProximityFromArraysRelaxed -Closes $closes -Highs $highs -Lows $lows -Volumes $vols `
                    -Mode "3-AND"  # proximity + RSI + trendline (sem vol_drying)
                $r2.valid | Should Be $true
                $r2.setup_ripening | Should Be $true  # PASSA sem vol_drying
            } else {
                Set-TestInconclusive -Message "Get-ToriProximityFromArraysRelaxed not implemented yet (TDD RED)"
            }
        }
    }
    
    Context "Remover RSI requirement (4-AND → 3-AND alternative)" {
        
        It "setup_ripening=TRUE quando proximity OK + vol_drying (sem RSI check)" {
            # Setup: trendline + proximity + vol_drying + RSI ALTO (>40)
            $closes = @(); $highs = @(); $lows = @(); $vols = @()
            
            for ($i = 0; $i -lt 20; $i++) {
                $base = 100 + $i * 0.5
                $closes += $base; $highs += $base + 0.5; $lows += $base - 0.5
                $vols += 1000.0
            }
            
            # Últimos 5 candles: sideways (RSI neutro ~50)
            for ($i = 0; $i -lt 5; $i++) {
                $closes += 110.0; $highs += 110.5; $lows += 109.5
                $vols += 500.0  # vol secando
            }
            
            $closes[-1] = $lows[-1] * 1.03  # proximity ~3%
            
            # Atual (4-AND): RSI~50 > 40 → setup_ripening=FALSE
            $r1 = Get-ToriProximityFromArrays -Closes $closes -Highs $highs -Lows $lows -Volumes $vols
            $r1.valid | Should Be $true
            $r1.rsi | Should BeGreaterThan 40
            $r1.vol_drying | Should Be $true
            $r1.setup_ripening | Should Be $false  # BLOCKED by RSI
            
            # Relaxed (3-AND): ignora RSI → setup_ripening=TRUE
            if (Get-Command Get-ToriProximityFromArraysRelaxed -ErrorAction SilentlyContinue) {
                $r2 = Get-ToriProximityFromArraysRelaxed -Closes $closes -Highs $highs -Lows $lows -Volumes $vols `
                    -Mode "3-AND-NO-RSI"  # proximity + vol_drying + trendline (sem RSI)
                $r2.setup_ripening | Should Be $true
            } else {
                Set-TestInconclusive
            }
        }
    }
}


Describe "Get-ToriProximityFromArrays - Soft Gates (2-AND)" {
    
    Context "Proximity range expansion (-5% a +10% vs -3% a +5%)" {
        
        It "setup_ripening=TRUE quando proximity=-4% (fora do range atual)" {
            # Setup: trendline + proximity -4% (overshoot) + RSI baixo + vol secando
            $closes = @(); $highs = @(); $lows = @(); $vols = @()
            
            for ($i = 0; $i -lt 20; $i++) {
                $base = 100 + $i * 0.5
                $closes += $base; $highs += $base + 0.5; $lows += $base - 0.5
                $vols += 1000.0
            }
            
            for ($i = 0; $i -lt 5; $i++) {
                $base = 110 - $i * 0.8
                $closes += $base; $highs += $base + 0.5; $lows += $base - 0.5
                $vols += 500.0
            }
            
            # Overshoot: -4% abaixo da action_line
            $actionLine = $lows[-1]
            $closes[-1] = $actionLine * 0.96  # -4% proximity
            
            # Atual: proximity -4% < -3% → setup_ripening=FALSE
            $r1 = Get-ToriProximityFromArrays -Closes $closes -Highs $highs -Lows $lows -Volumes $vols
            $r1.valid | Should Be $true
            $r1.proximity_pct | Should BeLessThan -3.0
            $r1.setup_ripening | Should Be $false  # BLOCKED by proximity range
            
            # Soft gates: proximity -5% a +10% → setup_ripening=TRUE
            if (Get-Command Get-ToriProximityFromArraysRelaxed -ErrorAction SilentlyContinue) {
                $r2 = Get-ToriProximityFromArraysRelaxed -Closes $closes -Highs $highs -Lows $lows -Volumes $vols `
                    -Mode "SOFT-GATES" `
                    -ProximityMin -5.0 -ProximityMax 10.0 `
                    -RsiMax 50.0  # RSI < 50 (vs < 40)
                $r2.setup_ripening | Should Be $true
            } else {
                Set-TestInconclusive
            }
        }
        
        It "setup_ripening=TRUE quando proximity=+8% (acima do range atual)" {
            # Setup: proximity +8% (approaching from above)
            $closes = @(); $highs = @(); $lows = @(); $vols = @()
            
            for ($i = 0; $i -lt 25; $i++) {
                $base = 100 + $i * 0.5
                $closes += $base; $highs += $base + 0.5; $lows += $base - 0.5
                $vols += 1000.0
            }
            
            # Price 8% acima da action_line (approaching)
            $actionLine = $lows[-1]
            $closes[-1] = $actionLine * 1.08  # +8% proximity
            
            # Atual: proximity +8% > +5% → setup_ripening=FALSE
            $r1 = Get-ToriProximityFromArrays -Closes $closes -Highs $highs -Lows $lows -Volumes $vols
            $r1.proximity_pct | Should BeGreaterThan 5.0
            $r1.setup_ripening | Should Be $false
            
            # Soft gates: +10% max → setup_ripening=TRUE
            if (Get-Command Get-ToriProximityFromArraysRelaxed -ErrorAction SilentlyContinue) {
                $r2 = Get-ToriProximityFromArraysRelaxed -Closes $closes -Highs $highs -Lows $lows -Volumes $vols `
                    -Mode "SOFT-GATES" -ProximityMin -5.0 -ProximityMax 10.0 -RsiMax 50.0
                $r2.setup_ripening | Should Be $true
            } else {
                Set-TestInconclusive
            }
        }
    }
    
    Context "RSI threshold expansion (< 50 vs < 40)" {
        
        It "setup_ripening=TRUE quando RSI=45 (fora do range atual)" {
            # Setup: RSI=45 (oversold moderado, não extremo)
            $closes = @(); $highs = @(); $lows = @(); $vols = @()
            
            # Uptrend seguido de decline moderado (RSI ~45)
            for ($i = 0; $i -lt 15; $i++) {
                $closes += 100 + $i * 0.8
                $highs += 101 + $i * 0.8
                $lows += 99 + $i * 0.8
                $vols += 1000.0
            }
            for ($i = 0; $i -lt 10; $i++) {
                $closes += 112 - $i * 0.3
                $highs += 113 - $i * 0.3
                $lows += 111 - $i * 0.3
                $vols += 500.0
            }
            
            $closes[-1] = $lows[-1] * 1.02
            
            # Atual: RSI~45 > 40 → setup_ripening=FALSE
            $r1 = Get-ToriProximityFromArrays -Closes $closes -Highs $highs -Lows $lows -Volumes $vols
            $r1.rsi | Should BeGreaterThan 40
            $r1.rsi | Should BeLessThan 50
            $r1.setup_ripening | Should Be $false
            
            # Soft gates: RSI < 50 → setup_ripening=TRUE
            if (Get-Command Get-ToriProximityFromArraysRelaxed -ErrorAction SilentlyContinue) {
                $r2 = Get-ToriProximityFromArraysRelaxed -Closes $closes -Highs $highs -Lows $lows -Volumes $vols `
                    -Mode "SOFT-GATES" -ProximityMin -5.0 -ProximityMax 10.0 -RsiMax 50.0
                $r2.setup_ripening | Should Be $true
            } else {
                Set-TestInconclusive
            }
        }
    }
}


Describe "Get-ToriProximityFromArrays - Slope Range Expansion" {
    
    It "valid=TRUE quando slope=3deg (fora do range atual 5-35deg)" {
        # Setup: trendline muito gentil (3deg)
        $closes = @(); $highs = @(); $lows = @(); $vols = @()
        
        for ($i = 0; $i -lt 30; $i++) {
            $base = 100 + $i * 0.15  # slope ~3deg
            $closes += $base; $highs += $base + 0.5; $lows += $base - 0.5
            $vols += 1000.0
        }
        
        # Atual: slope 3deg < 5deg → valid=FALSE
        $r1 = Get-ToriProximityFromArrays -Closes $closes -Highs $highs -Lows $lows -Volumes $vols
        $r1.valid | Should Be $false
        $r1.reason | Should Be "slope_out_of_range"
        $r1.slope_deg | Should BeLessThan 5.0
        
        # Relaxed: slope 3-45deg → valid=TRUE
        if (Get-Command Get-ToriProximityFromArraysRelaxed -ErrorAction SilentlyContinue) {
            $r2 = Get-ToriProximityFromArraysRelaxed -Closes $closes -Highs $highs -Lows $lows -Volumes $vols `
                -Mode "SOFT-GATES" `
                -SlopeMin 3.0 -SlopeMax 45.0
            $r2.valid | Should Be $true
        } else {
            Set-TestInconclusive
        }
    }
    
    It "valid=TRUE quando slope=40deg (fora do range atual 5-35deg)" {
        # Setup: trendline steep (40deg)
        $closes = @(); $highs = @(); $lows = @(); $vols = @()
        
        for ($i = 0; $i -lt 25; $i++) {
            $base = 100 + $i * 1.2  # slope ~40deg
            $closes += $base; $highs += $base + 0.5; $lows += $base - 0.5
            $vols += 1000.0
        }
        
        # Atual: slope 40deg > 35deg → valid=FALSE
        $r1 = Get-ToriProximityFromArrays -Closes $closes -Highs $highs -Lows $lows -Volumes $vols
        $r1.valid | Should Be $false
        $r1.reason | Should Be "slope_out_of_range"
        $r1.slope_deg | Should BeGreaterThan 35.0
        
        # Relaxed: slope 3-45deg → valid=TRUE
        if (Get-Command Get-ToriProximityFromArraysRelaxed -ErrorAction SilentlyContinue) {
            $r2 = Get-ToriProximityFromArraysRelaxed -Closes $closes -Highs $highs -Lows $lows -Volumes $vols `
                -Mode "SOFT-GATES" -SlopeMin 3.0 -SlopeMax 45.0
            $r2.valid | Should Be $true
        } else {
            Set-TestInconclusive
        }
    }
}


Describe "Relaxed Mode Config Helper (NEW)" {
    
    It "Get-ToriRelaxedConfig retorna params por mode" {
        # RED: Função ainda não existe
        
        if (-not (Get-Command Get-ToriRelaxedConfig -ErrorAction SilentlyContinue)) {
            Set-TestInconclusive -Message "Get-ToriRelaxedConfig not implemented yet (TDD RED)"
            return
        }
        
        # Mode: 4-AND (atual, strict)
        $strict = Get-ToriRelaxedConfig -Mode "4-AND"
        $strict.ProximityMin | Should Be -3.0
        $strict.ProximityMax | Should Be 5.0
        $strict.RsiMax | Should Be 40.0
        $strict.RequireVolDrying | Should Be $true
        $strict.SlopeMin | Should Be 5.0
        $strict.SlopeMax | Should Be 35.0
        
        # Mode: 3-AND (remove vol_drying)
        $relaxed3 = Get-ToriRelaxedConfig -Mode "3-AND"
        $relaxed3.RequireVolDrying | Should Be $false
        $relaxed3.RsiMax | Should Be 40.0
        
        # Mode: SOFT-GATES (expand all ranges)
        $soft = Get-ToriRelaxedConfig -Mode "SOFT-GATES"
        $soft.ProximityMin | Should Be -5.0
        $soft.ProximityMax | Should Be 10.0
        $soft.RsiMax | Should Be 50.0
        $soft.RequireVolDrying | Should Be $false
        $soft.SlopeMin | Should Be 3.0
        $soft.SlopeMax | Should Be 45.0
    }
}

