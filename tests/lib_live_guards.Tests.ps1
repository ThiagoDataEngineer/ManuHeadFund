# lib_live_guards.Tests.ps1 -- TDD de Resolve-EffectiveSizingCap
# (agents/lib_live_guards.ps1)
#
# 2026-08-07: achado real -- Test-SizingCap (cap fixo em dolar, historico
# desde o commit inicial do projeto quando o capital era pequeno e nao
# havia % dinamico ainda) rodava ANTES do "HARD CAP DE RISCO 3%"
# (gem_executor.ps1, a Regra de Ouro real, adicionada 2026-07-24) e
# BLOQUEAVA o trade inteiro sem o clamp de 3% ter chance de agir. Caso
# real: XRPUSDT propos $142.09 com capital=$2560 (=5.5% do capital, quase
# 2x a Regra de Ouro de 3%=$76.80) e foi descartado por inteiro pelo cap
# fixo de $100 -- que e mais restritivo que 3% pra qualquer capital abaixo
# de ~$3333. Resolve-EffectiveSizingCap calcula o teto real como o MENOR
# entre os dois, garantindo que a Regra de Ouro nunca perde pra um cap
# fixo esquecido, e que o cap fixo continua protegendo capitais grandes
# (onde 3% seria maior que o teto historico).
#
# Pester 3.4 (motor real de producao/CI) / ASCII-only.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_live_guards.ps1")

Describe "Resolve-EffectiveSizingCap" {

    It "capital pequeno (caso real XRPUSDT): 3% do capital < cap fixo -- usa 3% (Regra de Ouro vence)" {
        # capital=2560, 3%=76.80, cap fixo=100 -- 76.80 < 100, usa risk_pct
        $r = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital 2560.0 -RiskPct 0.03
        $r.cap_usd | Should Be 76.80
        $r.source | Should Be "risk_pct"
    }

    It "capital grande: 3% do capital > cap fixo -- usa cap fixo (protege trade desproporcional)" {
        # capital=10000, 3%=300, cap fixo=100 -- 300 > 100, usa fixed
        $r = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital 10000.0 -RiskPct 0.03
        $r.cap_usd | Should Be 100.0
        $r.source | Should Be "fixed"
    }

    It "capital no ponto de equilibrio exato (3% = cap fixo): usa cap fixo (empate nao vira risk_pct)" {
        # capital=3333.33, 3%=99.9999 ~ 100.00 apos round -- exatamente igual ao fixo
        $r = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital (100.0 / 0.03) -RiskPct 0.03
        $r.cap_usd | Should Be 100.0
        $r.source | Should Be "fixed"
    }

    It "capital=0 (indisponivel): fail-safe, usa so o cap fixo, nao inventa teto de risk_pct" {
        $r = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital 0
        $r.cap_usd | Should Be 100.0
        $r.source | Should Be "fixed_only_no_capital"
    }

    It "capital negativo (dado corrompido): mesmo fail-safe do capital=0" {
        $r = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital -50.0
        $r.cap_usd | Should Be 100.0
        $r.source | Should Be "fixed_only_no_capital"
    }

    It "RiskPct customizado (nao hardcoded 3%): respeita o parametro" {
        # capital=1000, risk=5% -> 50; cap fixo=100 -- 50 < 100, usa risk_pct
        $r = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital 1000.0 -RiskPct 0.05
        $r.cap_usd | Should Be 50.0
        $r.source | Should Be "risk_pct"
    }

    It "capital muito pequeno: risk_pct pode ficar bem abaixo do cap fixo, ainda assim vence" {
        # capital=100, 3%=3.0 -- protege capital pequeno de trade desproporcional
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

    It "capital grande (FUTURES com muito capital): cap fixo protege, comportamento antigo preservado" {
        # capital=50000, 3%=1500 -- cap fixo de 100 continua sendo o teto
        # real (protege contra trade desproporcional mesmo com capital alto)
        $eff = Resolve-EffectiveSizingCap -FixedCapUsd 100.0 -Capital 50000.0 -RiskPct 0.03
        $eff.source | Should Be "fixed"
        $result = Test-SizingCap -ProposedSizeUsd 150.0 -MaxSizeUsd $eff.cap_usd
        $result.pass | Should Be $false
    }
}
