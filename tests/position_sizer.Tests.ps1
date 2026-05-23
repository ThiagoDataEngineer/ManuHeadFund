# position_sizer.Tests.ps1 — Pester 3.x tests para position_sizer.ps1
# Rodar: Invoke-Pester .\tests\position_sizer.Tests.ps1 -Verbose

# Stubs de config para nao depender de credenciais
$COINEX_FEE_ROUNDTRIP_FALLBACK = 0.004
$COINEX_FEE_MAKER_FALLBACK     = 0.002
$COINEX_FEE_TAKER_FALLBACK     = 0.002
$RISCO_MAXIMO_PCT  = 0.01
$RR_MINIMO         = 2.0
$SCORE_MINIMO      = 55.0
$ALAVANCAGEM_MAX   = 5.0
$CAPITAL_TOTAL     = 1000.0

# Silencia Write-Host dos agentes durante testes
function Write-Host { param() }

. "$PSScriptRoot\..\agents\position_sizer.ps1"

Describe "Get-EffectiveRR" {
    Context "sem FeeContext (usa fallback 0.4%)" {
        It "R:R bruto 1:2 com stop 1% fica abaixo de 2 apos fees" {
            # Entry=100, Stop=99 (1%), Target=102 (2%) => bruto 1:2
            # effectiveLoss=1+(100*0.004)=1.4 | effectiveProfit=2-0.4=1.6 => RR=1.14
            $rr = Get-EffectiveRR -Entry 100 -Stop 99 -Target 102
            $rr | Should BeLessThan 2.0
            $rr | Should BeGreaterThan 1.0
        }

        It "R:R bruto 1:3 sobrevive a fees" {
            # Entry=100, Stop=99 (1%), Target=103 (3%)
            # effectiveLoss=1.4 | effectiveProfit=3-0.4=2.6 => RR=1.86
            $rr = Get-EffectiveRR -Entry 100 -Stop 99 -Target 103
            $rr | Should BeGreaterThan 1.5
        }

        It "stop micro faz RR efetivo negativo" {
            # Entry=100, Stop=99.9 (0.1%), Target=100.2 (0.2%)
            # Com fees 0.4% round-trip: feeCost=0.4 | effectiveProfit=0.2-0.4=-0.2 => RR negativo
            $fc = [PSCustomObject]@{ roundTrip = 0.4 }
            $rr = Get-EffectiveRR -Entry 100 -Stop 99.9 -Target 100.2 -FeeContext $fc
            $rr | Should BeLessThan 0
        }

        It "stop=entry: effectiveLoss e apenas o custo de taxa, funcao nao divide por zero" {
            # Stop=Entry => nao ha perda de preco, mas fee torna effectiveLoss > 0
            # Este input e rejeitado por Get-PositionSize, mas Get-EffectiveRR nao deve travar
            $rr = Get-EffectiveRR -Entry 100 -Stop 100 -Target 102
            $rr | Should BeGreaterThan 0  # profit / fee_only = valido, nao NaN
        }
    }

    Context "com FeeContext VIP (taxa menor)" {
        It "fee menor gera RR efetivo maior que com fee padrao" {
            # Mesmo trade, fee diferente — fee menor => RR maior. Autocontido, independe do fallback.
            $fcHigh = [PSCustomObject]@{ roundTrip = 0.4 }
            $fcLow  = [PSCustomObject]@{ roundTrip = 0.08 }
            $rrHigh = Get-EffectiveRR -Entry 100 -Stop 99 -Target 102 -FeeContext $fcHigh
            $rrLow  = Get-EffectiveRR -Entry 100 -Stop 99 -Target 102 -FeeContext $fcLow
            $rrLow | Should BeGreaterThan $rrHigh
        }
    }
}

Describe "Get-PositionSize" {
    It "calcula quantidade pela regra dos 1%" {
        $r = Get-PositionSize -CapitalTotal 1000 -EntryPrice 100 -StopLoss 99
        # risco=10 USD | stopDist=1 | qtd=10
        $r.quantidadeUnits | Should Be 10
        $r.riscoMaxUSD     | Should Be 10
        $r.stopPct         | Should Be 1.0
    }

    It "limita alavancagem ao maximo" {
        $r = Get-PositionSize -CapitalTotal 1000 -EntryPrice 100 -StopLoss 99.99 -AlavancagemMax 5
        $r.alavancagem | Should BeLessThan 5.1
    }

    It "falha com EntryPrice zero" {
        { Get-PositionSize -CapitalTotal 1000 -EntryPrice 0 -StopLoss 99 } | Should Throw
    }

    It "falha com stop igual ao entry" {
        { Get-PositionSize -CapitalTotal 1000 -EntryPrice 100 -StopLoss 100 } | Should Throw
    }
}

Describe "Test-TradeSetup" {
    It "bloqueia quando RR efetivo abaixo do minimo (fees corroem 1:2 bruto)" {
        $fc = [PSCustomObject]@{ roundTrip = 0.4 }
        $r = Test-TradeSetup `
            -CapitalTotal 1000 -EntryPrice 100 -StopLoss 99 -Alvo1 102 `
            -ScorePonderado 70 -Sinal "LONG" -RRMinimo 2.0 -ScoreMinimo 55 -FeeContext $fc
        $r.aprovado  | Should Be $false
        $r.rrEfetivo | Should BeLessThan 2.0
    }

    It "aprova setup com RR efetivo acima do minimo" {
        $fc = [PSCustomObject]@{ roundTrip = 0.4 }
        # Entry=100 Stop=95 (5%) Target=120 (20%) => bruto 4.0 | efetivo: loss=5.4 profit=19.6 => 3.63
        $r = Test-TradeSetup `
            -CapitalTotal 1000 -EntryPrice 100 -StopLoss 95 -Alvo1 120 `
            -ScorePonderado 70 -Sinal "LONG" -RRMinimo 2.0 -ScoreMinimo 55 -FeeContext $fc
        $r.aprovado  | Should Be $true
        $r.rrEfetivo | Should BeGreaterThan 2.0
    }

    It "bloqueia por score insuficiente" {
        $r = Test-TradeSetup `
            -CapitalTotal 1000 -EntryPrice 100 -StopLoss 95 -Alvo1 120 `
            -ScorePonderado 40 -Sinal "LONG" -RRMinimo 2.0 -ScoreMinimo 55
        $r.aprovado | Should Be $false
        ($r.bloqueios | Where-Object { $_ -match "Score" }) | Should Not BeNullOrEmpty
    }

    It "bloqueia stop acima do entry para LONG" {
        $r = Test-TradeSetup `
            -CapitalTotal 1000 -EntryPrice 100 -StopLoss 101 -Alvo1 110 `
            -ScorePonderado 70 -Sinal "LONG"
        $r.aprovado | Should Be $false
    }

    It "expoe rrEfetivo e feeContext no resultado" {
        $fc = [PSCustomObject]@{ roundTrip = 0.2 }
        $r = Test-TradeSetup `
            -CapitalTotal 1000 -EntryPrice 100 -StopLoss 95 -Alvo1 115 `
            -ScorePonderado 70 -Sinal "LONG" -FeeContext $fc
        $r.rrEfetivo            | Should BeGreaterThan 0
        $r.feeContext           | Should Not BeNullOrEmpty
        $r.rr                   | Should BeGreaterThan $r.rrEfetivo
    }
}
