# fqs_drain.Tests.ps1 -- TDD Invoke-FqsEnrichmentDrain
#
# Item 2 (2026-05-29): drena fila FQS inline ANTES do orchestrator V6 receber
# os candidatos. Antes: scanner enfileirava markets novos, mas a fila so era
# processada pelo cron separado -> markets novos chegavam ao orchestrator com
# "FQS indisponivel (sem entry no registry)" e eram vetados.
#
# Pos-fix: scan_master chama Invoke-FqsEnrichmentDrain apos enqueue, antes
# do orchestrator V6. Markets novos recebem entry no coin_registry.json em
# 3-5s, e o orchestrator ja tem dado disponivel.
#
# Pester 3.x. UTF-8 BOM. Sem acentos.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_fqs_drain.ps1")


# ── Fixture: mock registry + invoker ──────────────────────────────────────────
$mockDir = Join-Path $env:TEMP ("fqs_drain_" + [Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $mockDir -Force | Out-Null
$mockRegistry = Join-Path $mockDir "coin_registry.json"

function Reset-MockRegistry {
    @'
{
  "BTCUSDT": {"age_years": 17},
  "ETHUSDT": {"age_years": 11}
}
'@ | Out-File -FilePath $mockRegistry -Encoding UTF8
}

# Mock invoker: simula python coingecko_enrichment, registra chamadas em
# variavel global pra teste validar.
$global:_DrainCalls = @()
function _MockInvoker {
    param([string[]] $Markets, [int] $TimeoutSec)
    $global:_DrainCalls += [PSCustomObject]@{ markets=@($Markets); timeout=$TimeoutSec }
    # Simula enrichment: adiciona markets ao registry
    $reg = Get-Content $mockRegistry -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($m in $Markets) {
        if (-not $reg.PSObject.Properties[$m]) {
            Add-Member -InputObject $reg -MemberType NoteProperty -Name $m -Value @{ age_years=2 } -Force
        }
    }
    $reg | ConvertTo-Json -Depth 4 | Out-File -FilePath $mockRegistry -Encoding UTF8
    return [PSCustomObject]@{ ok=$true; exit_code=0 }
}

function _MockInvokerFail {
    param([string[]] $Markets, [int] $TimeoutSec)
    $global:_DrainCalls += [PSCustomObject]@{ markets=@($Markets); timeout=$TimeoutSec; failed=$true }
    return [PSCustomObject]@{ ok=$false; exit_code=1; error="python_not_found" }
}

function Reset-Calls { $global:_DrainCalls = @() }


# =============================================================================
Describe "Invoke-FqsEnrichmentDrain -- enriquece markets faltantes" {

    BeforeEach { Reset-MockRegistry; Reset-Calls }

    It "lista vazia: nao chama invoker, retorna stats zeradas" {
        $r = Invoke-FqsEnrichmentDrain -Markets @() -RegistryPath $mockRegistry -Invoker ${function:_MockInvoker}
        $r.enriched | Should Be 0
        $r.skipped_registered | Should Be 0
        $global:_DrainCalls.Count | Should Be 0
    }

    It "todos markets ja registrados: skip total, nao chama invoker" {
        $r = Invoke-FqsEnrichmentDrain -Markets @("BTCUSDT","ETHUSDT") -RegistryPath $mockRegistry -Invoker ${function:_MockInvoker}
        $r.enriched | Should Be 0
        $r.skipped_registered | Should Be 2
        $global:_DrainCalls.Count | Should Be 0
    }

    It "1 market faltante: chama invoker com esse market, retorna enriched=1" {
        $r = Invoke-FqsEnrichmentDrain -Markets @("BTCUSDT","NEWUSDT") -RegistryPath $mockRegistry -Invoker ${function:_MockInvoker}
        $r.enriched | Should Be 1
        $r.skipped_registered | Should Be 1
        $global:_DrainCalls.Count | Should Be 1
        $global:_DrainCalls[0].markets[0] | Should Be "NEWUSDT"
    }

    It "varios markets faltantes: chama invoker uma vez com todos juntos (batch)" {
        $r = Invoke-FqsEnrichmentDrain -Markets @("NEWAUSDT","NEWBUSDT","NEWCUSDT") -RegistryPath $mockRegistry -Invoker ${function:_MockInvoker}
        $r.enriched | Should Be 3
        $global:_DrainCalls.Count | Should Be 1
        $global:_DrainCalls[0].markets.Count | Should Be 3
    }

    It "dedup: mesmo market 2x na lista vira 1 chamada" {
        $r = Invoke-FqsEnrichmentDrain -Markets @("NEWUSDT","NEWUSDT","NEWUSDT") -RegistryPath $mockRegistry -Invoker ${function:_MockInvoker}
        $r.enriched | Should Be 1
        $global:_DrainCalls[0].markets.Count | Should Be 1
    }

    It "MaxMarkets=2 limita batch (anti-spike API)" {
        $r = Invoke-FqsEnrichmentDrain -Markets @("AUSDT","BUSDT","CUSDT","DUSDT","EUSDT") -RegistryPath $mockRegistry -Invoker ${function:_MockInvoker} -MaxMarkets 2
        $r.enriched | Should Be 2
        $r.skipped_overflow | Should Be 3
        $global:_DrainCalls[0].markets.Count | Should Be 2
    }

    It "TimeoutSec passado para invoker" {
        Invoke-FqsEnrichmentDrain -Markets @("NEWUSDT") -RegistryPath $mockRegistry -Invoker ${function:_MockInvoker} -TimeoutSec 45 | Out-Null
        $global:_DrainCalls[0].timeout | Should Be 45
    }
}


# =============================================================================
# Fail-soft: invoker falha (python ausente, timeout, etc)
Describe "Invoke-FqsEnrichmentDrain -- fail-soft" {

    BeforeEach { Reset-MockRegistry; Reset-Calls }

    It "invoker falha: retorna failed=true mas nao throw" {
        $r = Invoke-FqsEnrichmentDrain -Markets @("NEWUSDT") -RegistryPath $mockRegistry -Invoker ${function:_MockInvokerFail}
        $r.enriched | Should Be 0
        $r.failed | Should Be $true
        $r.error | Should Not BeNullOrEmpty
    }

    It "invoker null/ausente: skip total, retorna ok com stats zeradas" {
        $r = Invoke-FqsEnrichmentDrain -Markets @("NEWUSDT") -RegistryPath $mockRegistry -Invoker $null
        $r.enriched | Should Be 0
        $r.skipped_no_invoker | Should Be 1
    }

    It "registry inexistente: trata como se nada estivesse registrado, processa todos" {
        $r = Invoke-FqsEnrichmentDrain -Markets @("AUSDT","BUSDT") -RegistryPath (Join-Path $mockDir "no_existe.json") -Invoker ${function:_MockInvoker}
        $r.enriched | Should Be 2
    }
}


# =============================================================================
# Caso real INJUSDT 2026-05-29: IDUSDT/IOUSDT chegaram com FQS indisponivel
Describe "Caso 2026-05-29: scanner novos markets enriquecidos antes do orchestrator" {

    BeforeEach { Reset-MockRegistry; Reset-Calls }

    It "Cenario 10:55: 11 candidatos, 2 novos (ID/IO), 9 ja registrados" {
        # Setup: registry tem so BTC/ETH; demais ja existem em mock
        @'
{
  "BTCUSDT": {"age_years": 17},
  "ETHUSDT": {"age_years": 11},
  "PENDLEUSDT": {"age_years": 2},
  "HYPEUSDT": {"age_years": 1},
  "GRASSUSDT": {"age_years": 1},
  "FETUSDT": {"age_years": 5},
  "ALGOUSDT": {"age_years": 7},
  "INJUSDT": {"age_years": 5},
  "SEIUSDT": {"age_years": 2},
  "DYDXUSDT": {"age_years": 3}
}
'@ | Out-File -FilePath $mockRegistry -Encoding UTF8

        $cands = @("BTCUSDT","PENDLEUSDT","HYPEUSDT","GRASSUSDT","FETUSDT","ALGOUSDT",
                   "INJUSDT","IDUSDT","SEIUSDT","DYDXUSDT","IOUSDT")
        $r = Invoke-FqsEnrichmentDrain -Markets $cands -RegistryPath $mockRegistry -Invoker ${function:_MockInvoker}

        # Apenas IDUSDT e IOUSDT eram novos
        $r.enriched | Should Be 2
        $r.skipped_registered | Should Be 9
        $global:_DrainCalls[0].markets -contains "IDUSDT" | Should Be $true
        $global:_DrainCalls[0].markets -contains "IOUSDT" | Should Be $true
        $global:_DrainCalls[0].markets -contains "BTCUSDT" | Should Be $false
    }
}


# Cleanup
Remove-Item -Recurse -Force $mockDir -ErrorAction SilentlyContinue
