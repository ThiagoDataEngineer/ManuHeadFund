# lib_learning_evolution.Tests.ps1 -- Pester 3.x
# TDD Fix #3 (2026-06-23): evoluir com os erros.
# A) Get-GateKey: normaliza a FRASE de veto da LLM -> chave canonica de gate.
#    Hoje skip_quality chaveia pela frase inteira (unica cada vez) -> 1092 chaves n~1,
#    counterfactual nao agrega. Normalizar faz dezenas de gates "costly" emergirem.
# B) Resolve-AsymmetricStop: deixa o GANHADOR correr (trail largo) e protege breakeven,
#    consertando o R:R invertido (ganho medio $1.15 vs perda $4.45; AIN cortado a +19%).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_direction_learning.ps1")
. (Join-Path $agentsDir "lib_asymmetric_trail.ps1")

Describe "Get-GateKey - normaliza frase de veto -> gate canonico (Evolucao A)" {
    It "Mesa consensus forte (varias frases) -> MESMA chave" {
        $a = Get-GateKey "TIER_B_PAPER exige Mesa consensus FORTE (T+R+L) mas Tudor esta SHORT/85 - sem consenso"
        $b = Get-GateKey "TIER_B_PAPER exige Mesa consensus FORTE (T+R+L) mas R=NEUTRO/40 quebra o requisito"
        $a | Should Be $b
        $a | Should Be "mesa_consensus_forte"
    }
    It "Self-consistency downgrade -> chave estavel" {
        Get-GateKey "Self-consistency: ambos VETAR mas magnitudes diferiram (HARD_VETO/ABORTAR)" | Should Be "self_consistency"
    }
    It "FQS eliminatorio/indisponivel -> fqs" {
        Get-GateKey "FQS=1/7 AVOID e eliminatorio imediato" | Should Be "fqs"
        Get-GateKey "FQS indisponivel (sem entry no registry)" | Should Be "fqs"
    }
    It "Beta block -> beta" {
        Get-GateKey "BETA=1.4504 viola BLOCK=1.4 em fase bear" | Should Be "beta"
    }
    It "R:R incoerente -> rr" {
        Get-GateKey "SHORT com entry=349 e target=384 ACIMA do entry - R:R=5 incoerente" | Should Be "rr"
    }
    It "Frase desconhecida -> slug das primeiras palavras (agrupa parcial, nunca a frase toda)" {
        $k = Get-GateKey "Algum motivo totalmente novo que nunca vimos antes aqui"
        $k | Should Match "^[a-z_]+$"
        ($k.Length -lt 40) | Should Be $true
    }
    It "Vazio/null -> unknown" {
        Get-GateKey "" | Should Be "unknown"
        Get-GateKey $null | Should Be "unknown"
    }
}

Describe "Get-SkipQualityStats usa Get-GateKey -> agrega de verdade (Evolucao A)" {
    It "Vetos com frases diferentes do MESMO gate somam em 1 chave" {
        $skips = @(
            [pscustomobject]@{ gate="TIER_B_PAPER exige Mesa consensus FORTE mas Tudor SHORT/85"; direction="SHORT"; regime="BEAR_WEAK"; entry_price=100; exit_price=80 }
            [pscustomobject]@{ gate="TIER_B_PAPER exige Mesa consensus FORTE mas R NEUTRO/40";     direction="SHORT"; regime="BEAR_WEAK"; entry_price=100; exit_price=85 }
            [pscustomobject]@{ gate="TIER_B_PAPER exige Mesa consensus FORTE mas L LONG/72";        direction="SHORT"; regime="BEAR_WEAK"; entry_price=100; exit_price=70 }
        )
        $stats = @(Get-SkipQualityStats -Skips $skips -MinReturnPct 3 -MinSamples 3 -CostlyThreshold 0.6)
        $mesa = @($stats | Where-Object { $_.gate -eq "mesa_consensus_forte" })
        $mesa.Count | Should Be 1
        $mesa[0].n | Should Be 3
        # SHORT com exit abaixo do entry = teria lucrado (missed_winner)
        $mesa[0].missed_winners | Should Be 3
        $mesa[0].costly | Should Be $true
    }
}

Describe "Resolve-AsymmetricStop - deixa ganhador correr (Evolucao B)" {
    It "Sem lucro relevante -> mantem SL planejado (deixa respirar, nao estrangula)" {
        $r = Resolve-AsymmetricStop -Entry 100 -Peak 102 -BaseStop 90 -Side "LONG"
        $r | Should Be 90
    }
    It "Lucro >= trigger breakeven -> trava pelo menos breakeven" {
        $r = Resolve-AsymmetricStop -Entry 100 -Peak 106 -BaseStop 90 -Side "LONG" -BreakevenTriggerPct 0.05
        ($r -ge 100) | Should Be $true
    }
    It "Ganhador grande -> trail LARGO (12%) da espaco pra correr, nao corta no topo" {
        # AIN-like: peak +26%. Trail 12% => stop ~ peak*0.88, bem acima do entry, mas longe do peak.
        $r = Resolve-AsymmetricStop -Entry 100 -Peak 126 -BaseStop 90 -Side "LONG" -TrailWidthPct 0.12
        $r | Should Be ([math]::Round(126*0.88,8))
    }
    It "Stop so SOBE (ratchet): nunca volta abaixo do BaseStop" {
        $r = Resolve-AsymmetricStop -Entry 100 -Peak 101 -BaseStop 95 -Side "LONG"
        ($r -ge 95) | Should Be $true
    }
    It "Trail largo NUNCA acima do peak (nao dispara na hora)" {
        $r = Resolve-AsymmetricStop -Entry 100 -Peak 110 -BaseStop 90 -Side "LONG" -TrailWidthPct 0.12
        ($r -lt 110) | Should Be $true
    }
    It "SHORT espelhado: ganhador (peak abaixo do entry) trail acima do peak" {
        $r = Resolve-AsymmetricStop -Entry 100 -Peak 74 -BaseStop 110 -Side "SHORT" -TrailWidthPct 0.12
        $r | Should Be ([math]::Round(74*1.12,8))
        ($r -gt 74) | Should Be $true
    }
}
