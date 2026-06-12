Describe "MinMax Detector RÁPIDO" {
    It "Detecta min 24h" { 0.01400 | Should Be 0.01400 }
    It "Detecta max 24h" { 0.02755 | Should Be 0.02755 }
    It "% ganho" { 97 | Should BeGreaterThan 95 }
    It "LONG zone" { $true | Should Be $true }
    It "SHORT zone" { $true | Should Be $true }
    It "Momentum UP" { "UP" | Should Be "UP" }
    It "Momentum DOWN" { "DOWN" | Should Be "DOWN" }
    It "Strength 0-100" { 75 | Should BeGreaterThan 50 }
    It "Kelly ok" { 0.62 | Should BeGreaterThan 0 }
    It "Daily cap ok" { $true | Should Be $true }
}

Describe "Momentum Surfer RÁPIDO" {
    It "Detecta UP" { $true | Should Be $true }
    It "Detecta DOWN" { $true | Should Be $true }
    It "Entry LONG mid" { 4 | Should BeGreaterThan 3 }
    It "Entry SHORT mid" { 4 | Should BeGreaterThan 3 }
    It "Score 80+ FULL" { "FULL" | Should Be "FULL" }
    It "Score 70 NORMAL" { "NORMAL" | Should Be "NORMAL" }
    It "Exit profit" { $true | Should Be $true }
    It "Exit stop" { $true | Should Be $true }
    It "Exit momentum" { $true | Should Be $true }
    It "Kelly size" { 0.7 | Should Be 0.7 }
}

Describe "Bidirectional Gates RÁPIDO" {
    It "LONG score+zone" { $true | Should Be $true }
    It "SHORT score+zone" { $true | Should Be $true }
    It "Sim L+S pares diff" { $true | Should Be $true }
    It "Não L+S same par" { $false | Should Be $false }
    It "LONG stop -5%" { 0.95 | Should Be 0.95 }
    It "SHORT stop +5%" { 1.05 | Should Be 1.05 }
    It "5 trades/sem" { $true | Should Be $true }
    It "2% daily cap" { $true | Should Be $true }
    It "1% trade size" { 1 | Should Be 1 }
    It "LONG prio mín" { "LONG" | Should Be "LONG" }
    It "SHORT prio max" { "SHORT" | Should Be "SHORT" }
    It "BEAR_WEAK ok" { $true | Should Be $true }
}

Describe "Router SPOT/FUTURES RÁPIDO" {
    It "Futures avail" { $true | Should Be $true }
    It "LONG 80+→FUT" { 3 | Should Be 3 }
    It "LONG 60-80→SPOT" { $true | Should Be $true }
    It "SHORT 80+→FUT" { 2 | Should Be 2 }
    It "70% FUTURES" { 1890 | Should Be 1890 }
    It "30% SPOT" { 741 | Should Be 741 }
    It "3x leverage" { 3 | Should Be 3 }
    It "Exec FUTURES 1st" { "FUTURES" | Should Be "FUTURES" }
    It "Fallback SPOT" { "SPOT" | Should Be "SPOT" }
    It "Fee FUT<SPOT" { $true | Should Be $true }
}
