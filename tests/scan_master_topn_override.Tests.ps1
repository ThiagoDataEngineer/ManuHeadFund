# scan_master_topn_override.Tests.ps1 -- Pester 3.x
# Calibracao TopN cascade V6 (2026-05-15)
#
# Contexto: 30+ trades observados em 100% Tier D (cascade morre no DRONE BATEDOR).
# PORTEIRO / MESA / GENERAL nunca rodaram em producao. User aprovou aumentar
# TopN de 3 para 7 via override OPT-IN em config.local.ps1.
#
# Contrato:
#   - Sem $global:ORCHESTRATOR_TOPN_OVERRIDE setado -> TopN = 3 (default)
#   - Override valido (1..20)                      -> TopN = override
#   - Override invalido (<=0, >20, nao numerico)   -> TopN = 3 (fallback seguro)
#   - Ordenacao por compScore preservada (sem regressao Bug B)

$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptsDir = Join-Path (Split-Path $here -Parent) 'scripts'
$scanMaster = Join-Path $scriptsDir 'scan_master.ps1'

# Extrai funcoes puras sem rodar o loop (mesmo padrao de scan_master_rsi_filter.Tests.ps1)
$scanMasterContent = Get-Content -Raw -Path $scanMaster

if ($scanMasterContent -match '(?ms)(^function Get-OrchestratorTopN\s*\{.*?^\})') {
    Invoke-Expression $Matches[1]
}
if ($scanMasterContent -match '(?ms)(^function Get-ScannerCompositeScore\s*\{.*?^\})') {
    Invoke-Expression $Matches[1]
}

# Helper: limpa override entre testes
function Reset-TopNOverride {
    if (Test-Path variable:global:ORCHESTRATOR_TOPN_OVERRIDE) {
        Remove-Variable -Name ORCHESTRATOR_TOPN_OVERRIDE -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe "Get-OrchestratorTopN - override OPT-IN para cascade V6" {

    BeforeEach { Reset-TopNOverride }
    AfterEach  { Reset-TopNOverride }

    It "Sem override (variavel nao setada): TopN permanece 3 (regression)" {
        Reset-TopNOverride
        (Get-OrchestratorTopN) | Should Be 3
    }

    It "Com override = 5: TopN = 5" {
        $global:ORCHESTRATOR_TOPN_OVERRIDE = 5
        (Get-OrchestratorTopN) | Should Be 5
    }

    It "Com override = 7 (calibracao 2026-05-15): TopN = 7" {
        $global:ORCHESTRATOR_TOPN_OVERRIDE = 7
        (Get-OrchestratorTopN) | Should Be 7
    }

    It "Com override = 10: TopN = 10" {
        $global:ORCHESTRATOR_TOPN_OVERRIDE = 10
        (Get-OrchestratorTopN) | Should Be 10
    }

    It "Com override = 0 (invalido): TopN cai pro default 3" {
        $global:ORCHESTRATOR_TOPN_OVERRIDE = 0
        (Get-OrchestratorTopN) | Should Be 3
    }

    It "Com override = -1 (invalido, negativo): TopN cai pro default 3" {
        $global:ORCHESTRATOR_TOPN_OVERRIDE = -1
        (Get-OrchestratorTopN) | Should Be 3
    }

    It "Com override = 99 (acima do max 20): TopN cai pro default 3" {
        $global:ORCHESTRATOR_TOPN_OVERRIDE = 99
        (Get-OrchestratorTopN) | Should Be 3
    }

    It "Com override nao numerico ('abc'): TopN cai pro default 3" {
        $global:ORCHESTRATOR_TOPN_OVERRIDE = "abc"
        (Get-OrchestratorTopN) | Should Be 3
    }
}

Describe "Get-OrchestratorTopN + Get-ScannerCompositeScore - ordenacao preservada" {

    BeforeEach { Reset-TopNOverride }
    AfterEach  { Reset-TopNOverride }

    It "Top-N candidatos sao os de maior compScore (sem regressao Bug B)" {
        # Mock array: 5 candidatos com perfis variados
        # A: vol medio + momentum medio + ADX saudavel  -> compScore medio-alto
        # B: vol baixo + momentum saudavel + ADX OK     -> compScore medio
        # C: vol baixo, momentum baixo, ADX saudavel    -> compScore baixo (deve sair)
        # D: vol moderado MAS ADX 99 (zombie quase max) -> compScore baixo (deve sair)
        # E: vol 5x, momentum 25, ADX 30                -> compScore TOP
        # Top-3 esperado: E, A, B (D fica fora pela penalidade ADX>80)
        $cands = @(
            [PSCustomObject]@{ market='AAAUSDT'; vol=3.0; momentum=10.0; adx=40.0 }
            [PSCustomObject]@{ market='BBBUSDT'; vol=1.0; momentum=8.0;  adx=45.0 }
            [PSCustomObject]@{ market='CCCUSDT'; vol=0.8; momentum=1.0;  adx=35.0 }
            [PSCustomObject]@{ market='DDDUSDT'; vol=2.0; momentum=3.0;  adx=99.0 }
            [PSCustomObject]@{ market='EEEUSDT'; vol=5.0; momentum=25.0; adx=30.0 }
        )
        foreach ($c in $cands) {
            $c | Add-Member -NotePropertyName compScore -NotePropertyValue (
                Get-ScannerCompositeScore -VolSpike $c.vol -MomentumPct $c.momentum -Adx $c.adx
            ) -Force
        }

        $global:ORCHESTRATOR_TOPN_OVERRIDE = 3
        $topN = Get-OrchestratorTopN
        $top  = @($cands | Sort-Object -Property @{Expression='compScore';Descending=$true}, @{Expression='vol';Descending=$true} | Select-Object -First $topN)

        $top.Count    | Should Be 3
        $top[0].market | Should Be 'EEEUSDT'   # maior compScore (vol 5 + mom 25 + ADX saudavel)
        # DDDUSDT NAO deve estar no top (ADX zombie penaliza)
        $zombieHits = @($top | Where-Object { $_.market -eq 'DDDUSDT' })
        $zombieHits.Count | Should Be 0
    }

    It "Override = 7 amplia o universo passado ao cascade" {
        # Gera 10 candidatos sinteticos com compScore decrescente
        $cands = @()
        for ($i = 0; $i -lt 10; $i++) {
            $vol = 5.0 - ($i * 0.4)
            $mom = 20.0 - ($i * 1.5)
            $cands += [PSCustomObject]@{
                market    = "C${i}USDT"
                vol       = $vol
                momentum  = $mom
                adx       = 35.0
                compScore = (Get-ScannerCompositeScore -VolSpike $vol -MomentumPct $mom -Adx 35.0)
            }
        }

        # Sem override: 3 candidatos
        Reset-TopNOverride
        $defaultN = Get-OrchestratorTopN
        $topDef   = @($cands | Sort-Object -Property @{Expression='compScore';Descending=$true} | Select-Object -First $defaultN)
        $topDef.Count | Should Be 3

        # Com override 7: 7 candidatos (mais chance de escapar Tier D)
        $global:ORCHESTRATOR_TOPN_OVERRIDE = 7
        $loose = Get-OrchestratorTopN
        $topLoose = @($cands | Sort-Object -Property @{Expression='compScore';Descending=$true} | Select-Object -First $loose)
        $topLoose.Count | Should Be 7
    }
}
