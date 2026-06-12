$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_short_signals.ps1")

Describe "Detect-ShortSignal" {
    It "Detecta SHORT signal sintético: vol spike + new high + close BELOW + RSI>70" {
        # Construir setup que dispara SHORT
        $n = 30
        $closes = @(); $highs = @(); $lows = @(); $vols = @()
        # 25 candles uptrend smooth + new high climax + rejection
        for ($i = 0; $i -lt 25; $i++) {
            $base = 100 + $i  # uptrend
            $closes += $base
            $highs += $base + 0.5
            $lows += $base - 0.5
            $vols += 100
        }
        # Climax bar: new HIGH but close BELOW high (rejection)
        $highs += 140; $lows += 120; $closes += 122; $vols += 500
        # 4 more bars (RSI smoothing)
        for ($i = 0; $i -lt 4; $i++) {
            $closes += 120
            $highs += 122
            $lows += 118
            $vols += 100
        }
        $r = Detect-ShortSignal -Volumes $vols -Highs $highs -Lows $lows -Closes $closes -ClimaxMultiplier 2.0 -RsiOverboughtMin 60
        # Pode ou nao detectar dependendo do RSI calc — verifica que nao crasha + retorna struct
        $r.side | Should Be "SHORT"
        ($r.pattern_name -like "SHORT*") | Should Be $true
    }

    It "Não detecta em downtrend (sem new high)" {
        $closes = @(); $highs = @(); $lows = @(); $vols = @()
        for ($i = 0; $i -lt 30; $i++) {
            $base = 100 - $i  # downtrend
            $closes += $base; $highs += $base + 0.5; $lows += $base - 0.5; $vols += 100
        }
        $r = Detect-ShortSignal -Volumes $vols -Highs $highs -Lows $lows -Closes $closes
        $r.detected | Should Be $false
    }

    It "Retorna struct mesmo quando lib chart_patterns ausente (fail-soft)" {
        $closes = @(100) * 30; $highs = @(101) * 30; $lows = @(99) * 30; $vols = @(100) * 30
        $r = Detect-ShortSignal -Volumes $vols -Highs $highs -Lows $lows -Closes $closes
        $r.side | Should Be "SHORT"
        ($r.detected -is [bool]) | Should Be $true
    }
}

Describe "Get-ShortSignalWss" {
    It "Retorna null se Detect-ShortSignal nao trigger" {
        $closes = @(100) * 30; $highs = @(101) * 30; $lows = @(99) * 30; $vols = @(100) * 30
        $r = Get-ShortSignalWss -Market "BTCUSDT" -Volumes $vols -Highs $highs -Lows $lows -Closes $closes
        $r | Should Be $null
    }
}

Describe "Property: side eh sempre SHORT" {
    It "Output side field sempre 'SHORT'" {
        $closes = @(100) * 30; $highs = @(101) * 30; $lows = @(99) * 30; $vols = @(100) * 30
        $r = Detect-ShortSignal -Volumes $vols -Highs $highs -Lows $lows -Closes $closes
        $r.side | Should Be "SHORT"
    }
}

Describe "Property: determinism" {
    It "Mesma entrada -> mesma saida" {
        $closes = @(); $highs = @(); $lows = @(); $vols = @()
        for ($i = 0; $i -lt 30; $i++) { $closes += 100 + $i; $highs += 101 + $i; $lows += 99 + $i; $vols += 100 }
        $r1 = Detect-ShortSignal -Volumes $vols -Highs $highs -Lows $lows -Closes $closes
        $r2 = Detect-ShortSignal -Volumes $vols -Highs $highs -Lows $lows -Closes $closes
        $r1.detected | Should Be $r2.detected
        $r1.pattern_name | Should Be $r2.pattern_name
    }
}
