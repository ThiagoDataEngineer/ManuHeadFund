# lib_live_guards.Tests.ps1 -- TDD de Resolve-EffectiveSizingCap
# (agents/lib_live_guards.ps1)
#
# 2026-08-07: achado real -- Test-SizingCap (cap fixo em dolar, historico
# desde o commit inicial do projeto quando o capital era pequeno e nao
# havia % dinamico ainda) rodava ANTES do "HARD CAP DE RISCO 3%"
# (gem_executor.ps1, a Regra de Ouro real, adicionada 2026-07-24) e
# BLOQUEAVA o trade inteiro sem o clamp de 3% ter chance de agir.
#
# 2026-08-14 FIX: achado real posterior -- mesmo com o fix acima (usa o
# MENOR entre cap fixo e risk_pct), o cap fixo de $100 (LIVE_MAX_SIZE_USD,
# nunca configurado em lugar nenhum do repo, sempre cai no default 100.0)
# continuava vencendo sempre que risk_pct do capital > $100 -- ou seja,
# SEMPRE que capital < ~$1428 (a 7%, a Regra de Ouro atual desde
# 2026-08-04). Caso real: LINKUSDT SHORT com TORI 100/100 + quality gate
# PASS, tudo aprovado, bloqueado no fim por "$171.14 > cap $100" com
# capital=$2444.81 (7% real=$171.14). Decisao explicita do owner
# (2026-08-14): removido o cap fixo em dolar do calculo -- risk_pct do
# capital atual E a trava, sem teto adicional por cima (nem pra capital
# pequeno nem pra capital grande). Testes que validavam "capital grande
# usa cap fixo" foram atualizados pra refletir a nova politica.
#
# Pester 3.4 (motor real de producao/CI) / ASCII-only.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_live_guards.ps1")

Describe "Resolve-EffectiveSizingCap" {

    It "capital pequeno (caso real XRPUSDT): usa risk_pct do capital, cap fixo nao entra na conta" {
        # capital=2560, 3%=76.80
        $r = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital 2560.0 -RiskPct 0.03
        $r.cap_usd | Should Be 76.80
        $r.source | Should Be "risk_pct"
    }

    It "caso real LINKUSDT (2026-08-14): capital=2444.81, RiskPct=7% -- risk_pct ($171.14) vence, nao mais o cap fixo $100" {
        $r = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital 2444.81 -RiskPct 0.07
        $r.cap_usd | Should Be 171.14
        $r.source | Should Be "risk_pct"
    }

    It "capital grande: risk_pct SEM teto adicional -- cap fixo nao vence mais (mudanca de politica 2026-08-14)" {
        # capital=10000, 3%=300 -- antes o cap fixo (100) venceria; agora
        # risk_pct do capital E a trava, sem teto fixo em dolar por cima.
        $r = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital 10000.0 -RiskPct 0.03
        $r.cap_usd | Should Be 300.0
        $r.source | Should Be "risk_pct"
    }

    It "capital=0 (indisponivel): fail-safe, usa o cap fixo historico, nao inventa teto de risk_pct" {
        $r = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital 0
        $r.cap_usd | Should Be 100.0
        $r.source | Should Be "fixed_only_no_capital"
    }

    It "capital negativo (dado corrompido): mesmo fail-safe do capital=0" {
        $r = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital -50.0
        $r.cap_usd | Should Be 100.0
        $r.source | Should Be "fixed_only_no_capital"
    }

    It "RiskPct customizado (nao hardcoded): respeita o parametro" {
        # capital=1000, risk=5% -> 50
        $r = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital 1000.0 -RiskPct 0.05
        $r.cap_usd | Should Be 50.0
        $r.source | Should Be "risk_pct"
    }

    It "capital muito pequeno: risk_pct pode ficar bem abaixo do cap fixo historico, usa risk_pct mesmo assim" {
        # capital=100, 3%=3.0
        $r = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital 100.0 -RiskPct 0.03
        $r.cap_usd | Should Be 3.0
        $r.source | Should Be "risk_pct"
    }
}

Describe "Resolve-EffectiveSizingCap + Test-SizingCap + Resolve-SizingClamp -- integracao (caso real XRPUSDT)" {
    # Reproduz o cenario exato do log real (run 31136408717, 2026-08-07
    # 01:00:01Z): usd_size proposto=$142.09, capital=$2560, cap fixo=$100.
    # Sem o fix, Test-SizingCap bloqueava na hora (142.09 > 100, fora da
    # tolerancia de 10% do clamp). Com o fix, o teto efetivo vira $76.80
    # (3% do capital) -- ainda bloqueia esse valor exato (142.09 e' MUITO
    # maior que 76.80, nao e so um overage pequeno de arredondamento), mas
    # agora o motivo do bloqueio e o correto (risk_pct, nao um cap fixo
    # desatualizado) -- e um trade HIPOTETICO um pouco menor (ex: $80,
    # perto do teto de risco real) que antes seria erroneamente permitido
    # (80 < 100, cap fixo deixava passar mesmo violando a Regra de Ouro)
    # agora e corretamente barrado por exceder os 3% reais.

    It "trade que respeita cap fixo mas viola Regra de Ouro (capital pequeno) -- agora e bloqueado (antes passava errado)" {
        # usd_size=$80, capital=$2560: cap fixo permitiria (80<100), mas
        # 3% real = $76.80 -- deveria bloquear (80 > 76.80, fora tolerancia)
        $eff = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital 2560.0 -RiskPct 0.03
        $result = Test-SizingCap -ProposedSizeUsd 80.0 -MaxSizeUsd $eff.cap_usd
        $result.pass | Should Be $false
    }

    It "trade real XRPUSDT ($142.09, capital=$2560) -- continua bloqueado corretamente, agora pelo motivo certo" {
        $eff = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital 2560.0 -RiskPct 0.03
        $eff.source | Should Be "risk_pct"
        $result = Test-SizingCap -ProposedSizeUsd 142.09 -MaxSizeUsd $eff.cap_usd
        $result.pass | Should Be $false
    }

    It "trade pequeno o suficiente para respeitar os 3% reais -- passa (nao e mais descartado por um cap fixo desatualizado)" {
        # usd_size=$70, capital=$2560, 3%=$76.80 -- 70 < 76.80, deveria passar
        $eff = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital 2560.0 -RiskPct 0.03
        $result = Test-SizingCap -ProposedSizeUsd 70.0 -MaxSizeUsd $eff.cap_usd
        $result.pass | Should Be $true
    }

    It "overage pequeno (<=10%) sobre o teto de risk_pct ainda e clampado, nao bloqueado (preserva fix de 07-08)" {
        # cap efetivo=76.80 (risk_pct), proposto=80 (~4.2% de overage, dentro
        # dos 10% de tolerancia) -- Resolve-SizingClamp deve reduzir pro cap,
        # nao deixar Test-SizingCap matar o trade.
        $eff = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital 2560.0 -RiskPct 0.03
        $clamp = Resolve-SizingClamp -ProposedSizeUsd 80.0 -MaxSizeUsd $eff.cap_usd
        $clamp.clamped | Should Be $true
        $clamp.size_usd | Should Be $eff.cap_usd
    }

    It "capital grande (FUTURES com muito capital): risk_pct escala com o capital, sem teto fixo por cima (2026-08-14)" {
        # capital=50000, 3%=1500 -- antes o cap fixo de 100 venceria; agora
        # a Regra de Ouro escala com o capital, decisao explicita do owner.
        $eff = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital 50000.0 -RiskPct 0.03
        $eff.source | Should Be "risk_pct"
        $eff.cap_usd | Should Be 1500.0
        $result = Test-SizingCap -ProposedSizeUsd 150.0 -MaxSizeUsd $eff.cap_usd
        $result.pass | Should Be $true
    }
}

Describe "Resolve-GoldenRuleSizeClamp" {
    # 2026-08-07: achado real -- Test-CoinExposureCap (gate "cap_por_moeda",
    # gem_executor.ps1) roda ~130 linhas ANTES do "HARD CAP DE RISCO 3%"
    # no mesmo arquivo, contra o usd_size CRU (nao clampado ainda). Caso
    # real: SOLUSDT propos usd_size~$237.19 (10.11% de capital=$2345.92,
    # mais que o triplo da Regra de Ouro de 3%=$70.38) e foi bloqueado por
    # inteiro repetidamente (mensagens Telegram identicas ciclo apos ciclo)
    # mesmo quando o Mentor aprovava o setup tecnico. Resolve-GoldenRuleSizeClamp
    # aplicado logo apos usd_size ser calculado (antes de QUALQUER gate de
    # bloqueio) fecha esse gap -- clampa pra 3% em vez de deixar o valor
    # cru estourar gates mais adiante no fluxo.

    It "caso real SOLUSDT: usd_size=$237.19 capital=$2345.92 -- clampa para 3% (~$70.38)" {
        $r = Resolve-GoldenRuleSizeClamp -ProposedUsd 237.19 -Capital 2345.92 -RiskPct 0.03
        $r.clamped | Should Be $true
        $r.usd_size | Should Be 70.38
    }

    It "usd_size ja dentro de 3% -- nao clampa, retorna o valor original inalterado" {
        $r = Resolve-GoldenRuleSizeClamp -ProposedUsd 50.0 -Capital 2345.92 -RiskPct 0.03
        $r.clamped | Should Be $false
        $r.usd_size | Should Be 50.0
    }

    It "usd_size exatamente no limite de 3% -- nao clampa (nao e 'exceder', e igual)" {
        $r = Resolve-GoldenRuleSizeClamp -ProposedUsd 70.38 -Capital 2346.0 -RiskPct 0.03
        $r.clamped | Should Be $false
    }

    It "capital=0 (indisponivel) -- fail-safe, nao mexe no valor proposto" {
        $r = Resolve-GoldenRuleSizeClamp -ProposedUsd 100.0 -Capital 0
        $r.clamped | Should Be $false
        $r.usd_size | Should Be 100.0
    }

    It "capital negativo (dado corrompido) -- mesmo fail-safe" {
        $r = Resolve-GoldenRuleSizeClamp -ProposedUsd 100.0 -Capital -500.0
        $r.clamped | Should Be $false
        $r.usd_size | Should Be 100.0
    }

    It "ProposedUsd=0 -- fail-safe, nao inventa clamp sobre valor zero" {
        $r = Resolve-GoldenRuleSizeClamp -ProposedUsd 0 -Capital 2000.0
        $r.clamped | Should Be $false
        $r.usd_size | Should Be 0
    }

    It "RiskPct customizado (nao hardcoded 3%) -- respeita o parametro" {
        # capital=1000, risk=5% -> cap=50; proposto=80 -> clampa pra 50
        $r = Resolve-GoldenRuleSizeClamp -ProposedUsd 80.0 -Capital 1000.0 -RiskPct 0.05
        $r.clamped | Should Be $true
        $r.usd_size | Should Be 50.0
    }

    It "nunca AUMENTA o valor -- clamp so reduz, mesmo com capital grande" {
        $r = Resolve-GoldenRuleSizeClamp -ProposedUsd 10.0 -Capital 100000.0 -RiskPct 0.03
        $r.clamped | Should Be $false
        $r.usd_size | Should Be 10.0
    }
}

Describe "Resolve-GoldenRuleSizeClamp -- integracao com Test-CoinExposureCap (caso real SOLUSDT)" {
    # Reproduz o cenario exato do log real (run 31190290313, 2026-08-07
    # 14:59:48Z): sem o clamp, Test-CoinExposureCap bloqueava
    # (proj=10.11% >= MaxPerCoinPct=10.0%). Com o clamp aplicado antes,
    # o usd_size cai bem abaixo do teto de exposicao, o trade passa.

    BeforeEach {
        $agentsDir = Split-Path $PSScriptRoot -Parent | Join-Path -ChildPath "agents"
        . (Join-Path $agentsDir "lib_gem_safety.ps1")
    }

    It "sem clamp: usd_size cru de $237.19 estoura o cap de exposicao (10%) -- bloqueia (comportamento antigo, bug)" {
        $cap = Test-CoinExposureCap -HeldUsd 0 -TradeUsd 237.19 -PortfolioUsd 2345.92 -MaxPerCoinPct 10.0
        $cap.allowed | Should Be $false
        $cap.reason | Should Be "cap_por_moeda"
    }

    It "com clamp: usd_size reduzido para 3% (~$70.38) passa tranquilo no cap de exposicao de 10% -- fix funciona" {
        $clamp = Resolve-GoldenRuleSizeClamp -ProposedUsd 237.19 -Capital 2345.92 -RiskPct 0.03
        $cap = Test-CoinExposureCap -HeldUsd 0 -TradeUsd $clamp.usd_size -PortfolioUsd 2345.92 -MaxPerCoinPct 10.0
        $cap.allowed | Should Be $true
    }
}
