# lib_risk_max_pct_per_trade.Tests.ps1 -- TDD
#
# Achado 2026-08-04 (owner, discutindo sizing real ~$100/trade LONG numa
# conta de ~$5057): o caminho PRIMARIO de sizing (dynamic_feedback,
# Invoke-GemExecute) usava $riskPct=0.03 HARDCODED, ignorando
# $global:RISK_MAX_PCT_PER_TRADE por completo -- a variavel de config.ps1
# dizia "1%" (nunca atualizada quando o hardcode virou 3% em 2026-07-22),
# e o proprio config.ps1 nunca era carregado no script real de producao
# (scripts/gem_scanner_executor_live.ps1 so carrega config.local.ps1,
# credenciais). Owner decidiu subir pra 7% -- corrigido pra ler
# $global:RISK_MAX_PCT_PER_TRADE com fallback embutido de 0.07 (a fonte
# real que de fato roda em producao, ja que config.ps1 nao e carregado
# nesse caminho por design -- carregar reverteria outras calibragens,
# ex: GEM_VOL_SPIKE_MIN 2.0 vs 1.5 calibrado em 2026-06-10).
#
# Este teste confirma o VALOR REAL (0.07) que o codigo usa hoje, nao so a
# logica de fallback -- se alguem reintroduzir um hardcode diferente por
# engano no futuro, este teste quebra.

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"

Describe "Risco por trade (Regra de Ouro #2) -- valor real em vigor" {

    It "gem_executor.ps1 nao tem mais 0.03 hardcoded sem fallback pra global (regressao do bug antigo)" {
        $content = Get-Content (Join-Path $agentsDir "gem_executor.ps1") -Raw
        # NAO deve existir "riskPct = 0.03" cru (sem checar a global antes)
        ($content -match '\$riskPct\s*=\s*0\.03\s*$') | Should Be $false
    }

    It "gem_executor.ps1 le \$global:RISK_MAX_PCT_PER_TRADE com fallback 0.07 (valor real da Regra de Ouro #2 hoje)" {
        $content = Get-Content (Join-Path $agentsDir "gem_executor.ps1") -Raw
        ($content -match [regex]::Escape('$riskPct = if ($global:RISK_MAX_PCT_PER_TRADE) { [double]$global:RISK_MAX_PCT_PER_TRADE } else { 0.07 }')) | Should Be $true
    }

    It "config.ps1 define RISK_MAX_PCT_PER_TRADE = 0.07 (fonte documentada, mesmo que nao carregada no path de producao real)" {
        $content = Get-Content (Join-Path $agentsDir "config.ps1") -Raw
        ($content -match '\$global:RISK_MAX_PCT_PER_TRADE\s*=\s*0\.07') | Should Be $true
    }

    It "gem_agent.ps1 fallback tambem atualizado pra 0.07 (consistencia entre os 2 pontos que definem esta variavel)" {
        $content = Get-Content (Join-Path $agentsDir "gem_agent.ps1") -Raw
        ($content -match [regex]::Escape('else { 0.07 }')) | Should Be $true
    }

    It "cenario real: com \$global:RISK_MAX_PCT_PER_TRADE nao definido (path de producao real, config.ps1 nao carregado), o fallback de 0.07 e o que vale" {
        $result = & {
            Remove-Variable -Name RISK_MAX_PCT_PER_TRADE -Scope Global -ErrorAction SilentlyContinue
            $riskPct = if ($global:RISK_MAX_PCT_PER_TRADE) { [double]$global:RISK_MAX_PCT_PER_TRADE } else { 0.07 }
            return $riskPct
        }
        $result | Should Be 0.07
    }

    It "cenario com \$global:RISK_MAX_PCT_PER_TRADE definido (ex: config.ps1 carregado em outro contexto) -- respeita o valor real, nao o fallback" {
        $result = & {
            $global:RISK_MAX_PCT_PER_TRADE = 0.05
            $riskPct = if ($global:RISK_MAX_PCT_PER_TRADE) { [double]$global:RISK_MAX_PCT_PER_TRADE } else { 0.07 }
            return $riskPct
        }
        $result | Should Be 0.05
        Remove-Variable -Name RISK_MAX_PCT_PER_TRADE -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe "Risco por trade -- 3 clamps adicionados 2026-08-07/08 tambem sincronizados (regressao real corrigida 2026-08-08)" {
    # Achado 2026-08-08 (owner, no monitoramento ao vivo: "se nao me engano
    # ja subimos para 7%"): os 2 fixes de sizing escritos em 2026-08-07
    # (Resolve-GoldenRuleSizeClamp em Execute-GemTrade, Resolve-EffectiveSizingCap
    # no guard de tier) e o "HARD CAP DE RISCO" pre-existente de 2026-07-24
    # (anterior ao commit 4060d4e que subiu a Regra de Ouro pra 7% em
    # 2026-08-04) tinham RiskPct=0.03/0.03 HARDCODED -- reintroduzindo a
    # MESMA classe de bug que 4060d4e ja tinha corrigido no caminho primario.
    # Efeito real: SOLUSDT com usd_size=$237 era clampado pra $70.38 (3%) em
    # vez do $164.21 (7%) que o owner ja tinha decidido -- sizing real ficava
    # menor que o pretendido em TODO trade que passasse por qualquer um
    # desses 3 pontos, silenciosamente, sem nenhum log indicando o motivo.

    It "gem_executor.ps1 nao tem RiskPct=0.03 hardcoded em nenhuma chamada de Resolve-GoldenRuleSizeClamp ou Resolve-EffectiveSizingCap" {
        $content = Get-Content (Join-Path $agentsDir "gem_executor.ps1") -Raw
        ($content -match '-RiskPct\s+0\.03') | Should Be $false
    }

    It "gem_executor.ps1 nao tem o HARD CAP DE RISCO usando 0.03 hardcoded (capital \* 0.03)" {
        $content = Get-Content (Join-Path $agentsDir "gem_executor.ps1") -Raw
        ($content -match '\$capital\s*\*\s*0\.03') | Should Be $false
    }

    It "chamada de Resolve-GoldenRuleSizeClamp le \$global:RISK_MAX_PCT_PER_TRADE com fallback 0.07" {
        $content = Get-Content (Join-Path $agentsDir "gem_executor.ps1") -Raw
        ($content -match [regex]::Escape('$__riskPctEarly = if ($global:RISK_MAX_PCT_PER_TRADE) { [double]$global:RISK_MAX_PCT_PER_TRADE } else { 0.07 }')) | Should Be $true
        ($content -match [regex]::Escape('Resolve-GoldenRuleSizeClamp -ProposedUsd $usd_size -Capital $capital -RiskPct $__riskPctEarly')) | Should Be $true
    }

    It "chamada de Resolve-EffectiveSizingCap le \$global:RISK_MAX_PCT_PER_TRADE com fallback 0.07" {
        $content = Get-Content (Join-Path $agentsDir "gem_executor.ps1") -Raw
        ($content -match [regex]::Escape('$__riskPctGuard = if ($global:RISK_MAX_PCT_PER_TRADE) { [double]$global:RISK_MAX_PCT_PER_TRADE } else { 0.07 }')) | Should Be $true
        ($content -match [regex]::Escape('Resolve-EffectiveSizingCap -FixedCapUsd $maxSize -Capital $capital -RiskPct $__riskPctGuard')) | Should Be $true
    }

    It "HARD CAP DE RISCO le \$global:RISK_MAX_PCT_PER_TRADE com fallback 0.07" {
        $content = Get-Content (Join-Path $agentsDir "gem_executor.ps1") -Raw
        ($content -match [regex]::Escape('$__hardCapRiskPct = if ($global:RISK_MAX_PCT_PER_TRADE) { [double]$global:RISK_MAX_PCT_PER_TRADE } else { 0.07 }')) | Should Be $true
        ($content -match [regex]::Escape('$__hardCapUsd = [math]::Round($capital * $__hardCapRiskPct, 2)')) | Should Be $true
    }

    It "cenario real SOLUSDT: com RISK_MAX_PCT_PER_TRADE=0.07 e capital=2345.92, o clamp correto e ~\$164.21 (nao \$70.38 do bug de 3%)" {
        $agentsDirLocal = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
        . (Join-Path $agentsDirLocal "lib_live_guards.ps1")

        $global:RISK_MAX_PCT_PER_TRADE = 0.07
        $riskPct = if ($global:RISK_MAX_PCT_PER_TRADE) { [double]$global:RISK_MAX_PCT_PER_TRADE } else { 0.07 }
        $r = Resolve-GoldenRuleSizeClamp -ProposedUsd 237.0 -Capital 2345.92 -RiskPct $riskPct

        $r.clamped | Should Be $true
        $r.usd_size | Should Be 164.21
        Remove-Variable -Name RISK_MAX_PCT_PER_TRADE -Scope Global -ErrorAction SilentlyContinue
    }
}
