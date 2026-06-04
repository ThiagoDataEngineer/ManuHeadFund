# tests/lib_chart_patterns_rsi.Tests.ps1
# Validar RSI calculation em lib_chart_patterns.ps1
# Criado: 2026-05-23 (após descoberta do RSI bug em Python)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. "$root\agents\lib_chart_patterns.ps1"

Describe "RSI Calculation - lib_chart_patterns (_CP-CalcRsiArray)" {
    
    Context "Uptrend (prices rising)" {
        It "Should return RSI > 70 for strong uptrend" {
            # Generate uptrend: 100, 102, 104, 106, ..., 158
            $closes = @(0..29 | ForEach-Object { 100 + $_ * 2 })
            
            $rsi = _CP-CalcRsiArray -Closes $closes -Period 14
            
            # Last RSI should be > 70 (overbought)
            $rsi[-1] | Should BeGreaterThan 70

        }
        
        It "Should return RSI = 100 for pure uptrend (no losses)" {
            # Pure uptrend: every candle closes higher
            $closes = @(0..29 | ForEach-Object { 100 + $_ * 5 })
            
            $rsi = _CP-CalcRsiArray -Closes $closes -Period 14
            
            # Pure uptrend should approach RSI = 100
            $rsi[-1] | Should BeGreaterThan 95
        }
    }
    
    Context "Downtrend (prices falling)" {
        It "Should return RSI < 30 for strong downtrend" {
            # Generate downtrend: 100, 98, 96, 94, ..., 42
            $closes = @(0..29 | ForEach-Object { 100 - $_ * 2 })
            
            $rsi = _CP-CalcRsiArray -Closes $closes -Period 14
            
            # Last RSI should be < 30 (oversold)
            $rsi[-1] | Should BeLessThan 30

        }
        
        It "Should return RSI = 0 for pure downtrend (no gains)" {
            # Pure downtrend: every candle closes lower
            $closes = @(0..29 | ForEach-Object { 100 - $_ * 5 })
            
            $rsi = _CP-CalcRsiArray -Closes $closes -Period 14
            
            # Pure downtrend should approach RSI = 0
            $rsi[-1] | Should BeLessThan 5
        }
    }
    
    Context "Sideways (prices oscillating)" {
        It "Should return RSI ~50 for sideways market" {
            # Sideways: 100, 101, 100, 101, 100, ...
            $closes = @(0..29 | ForEach-Object { 100 + ($_ % 2) })
            
            $rsi = _CP-CalcRsiArray -Closes $closes -Period 14
            
            # Sideways should have RSI around 50
            $rsi[-1] | Should BeGreaterThan 40
            $rsi[-1] | Should BeLessThan 60
        }
    }
    
    Context "Real BTC-like volatility" {
        It "Should return valid RSI for realistic price action" {
            # BTC-like: uptrend with pullbacks
            $closes = @(
                100, 102, 101, 105, 103, 108, 106, 110, 108, 112,
                115, 113, 118, 116, 120, 118, 122, 120, 125, 123,
                128, 126, 130, 128, 132, 130, 135, 133, 138, 136
            )
            
            $rsi = _CP-CalcRsiArray -Closes $closes -Period 14
            
            # Should be in valid range (0-100)
            $rsi[-1] | Should BeGreaterThan 0
            $rsi[-1] | Should BeLessThan 100
            
            # Should be bullish (uptrend with pullbacks)
            $rsi[-1] | Should BeGreaterThan 50
        }
    }
    
    Context "Edge cases" {
        It "Should return 50.0 for insufficient history" {
            # Less than period+1 candles
            $closes = @(100, 101, 102, 103, 104)
            
            $rsi = _CP-CalcRsiArray -Closes $closes -Period 14
            
            # Should return default 50.0 for all values
            $rsi | ForEach-Object { $_ | Should Be 50.0 }
        }
        
        It "Should handle exact period+1 candles" {
            # Exactly 15 candles (period=14)
            $closes = @(0..14 | ForEach-Object { 100 + $_ })
            
            $rsi = _CP-CalcRsiArray -Closes $closes -Period 14
            
            # Should calculate RSI for last value
            $rsi[-1] | Should Not Be 50.0
            $rsi[-1] | Should BeGreaterThan 0
            $rsi[-1] | Should BeLessThan 100
        }
        
        It "Should return array of same length as input" {
            $closes = @(0..29 | ForEach-Object { 100 + $_ })
            
            $rsi = _CP-CalcRsiArray -Closes $closes -Period 14
            
            # Output array should have same length as input
            $rsi.Length | Should Be $closes.Length
        }
    }
    
    Context "Comparison with Python implementation" {
        It "Should match Python RSI for uptrend" {
            # Same data as Python test
            $closes = @(0..29 | ForEach-Object { 100 + $_ * 2 })
            
            $rsi = _CP-CalcRsiArray -Closes $closes -Period 14
            
            # Python test expects RSI > 70 for this uptrend
            $rsi[-1] | Should BeGreaterThan 70
        }
        
        It "Should match Python RSI for downtrend" {
            # Same data as Python test
            $closes = @(0..29 | ForEach-Object { 100 - $_ * 2 })
            
            $rsi = _CP-CalcRsiArray -Closes $closes -Period 14
            
            # Python test expects RSI < 30 for this downtrend
            $rsi[-1] | Should BeLessThan 30
        }
        
        It "Should match Python RSI for sideways" {
            # Same data as Python test
            $closes = @(0..29 | ForEach-Object { 100 + ($_ % 2) })
            
            $rsi = _CP-CalcRsiArray -Closes $closes -Period 14
            
            # Python test expects RSI 40-60 for sideways
            $rsi[-1] | Should BeGreaterThan 40
            $rsi[-1] | Should BeLessThan 60
        }
    }
}
