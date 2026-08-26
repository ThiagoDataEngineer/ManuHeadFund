# lib_no_fundamental_sizing.Tests.ps1 -- TDD de Resolve-NoFundamentalSizingPenalty
# (agents/lib_no_fundamental_sizing.ps1)
#
# 2026-08-26: fecha o gap real "HUMAUSDT entrou com fqs=UNKNOWN, tratado como
# neutro (bonus=0), nao como risco -- token sem NENHUMA curadoria fundamental
# tinha o mesmo peso que um token QUALITY/BLUE_CHIP avaliado de verdade".
#
# Pester 3.4 (motor real de producao/CI).

$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_no_fundamental_sizing.ps1")

Describe "Resolve-NoFundamentalSizingPenalty" {
    It "resultado null: nao penaliza (fail-safe, gate opcional nao deve travar entrada)" {
        $r = Resolve-NoFundamentalSizingPenalty -FqsLazyEnrichResult $null
        $r.apply_penalty | Should Be $false
    }

    It "enrich com sucesso (fundamental real avaliado, mesmo que categoria ruim): nao penaliza aqui -- categoria ruim ja e tratada por outro gate" {
        $result = [PSCustomObject]@{ success = $true; reason = "enriched_QUALITY" }
        $r = Resolve-NoFundamentalSizingPenalty -FqsLazyEnrichResult $result
        $r.apply_penalty | Should Be $false
        $r.reason | Should Be "enrich_teve_sucesso"
    }

    It "falha por not_in_MARKET_TO_CG (caso real HUMAUSDT -- nunca ouvimos falar do token): PENALIZA" {
        $result = [PSCustomObject]@{ success = $false; reason = "not_eligible: not_in_MARKET_TO_CG" }
        $r = Resolve-NoFundamentalSizingPenalty -FqsLazyEnrichResult $result
        $r.apply_penalty | Should Be $true
        $r.penalty_fraction | Should Be 0.5
    }

    It "falha por rate_limit_global (temporaria, NAO e ausencia real de curadoria): NAO penaliza" {
        $result = [PSCustomObject]@{ success = $false; reason = "rate_limit_global (last attempt < 6s ago)" }
        $r = Resolve-NoFundamentalSizingPenalty -FqsLazyEnrichResult $result
        $r.apply_penalty | Should Be $false
    }

    It "falha por market_attempted_recently (ja tentou nas ultimas 24h, temporaria): NAO penaliza" {
        $result = [PSCustomObject]@{ success = $false; reason = "market_attempted_recently (TTL 24h)" }
        $r = Resolve-NoFundamentalSizingPenalty -FqsLazyEnrichResult $result
        $r.apply_penalty | Should Be $false
    }

    It "falha por spawn_error/python_exit (erro de infra, NAO ausencia real): NAO penaliza" {
        $result = [PSCustomObject]@{ success = $false; reason = "python_exit_1" }
        $r = Resolve-NoFundamentalSizingPenalty -FqsLazyEnrichResult $result
        $r.apply_penalty | Should Be $false
    }

    It "PenaltyFraction e configuravel" {
        $result = [PSCustomObject]@{ success = $false; reason = "not_eligible: not_in_MARKET_TO_CG" }
        $r = Resolve-NoFundamentalSizingPenalty -FqsLazyEnrichResult $result -PenaltyFraction 0.3
        $r.apply_penalty | Should Be $true
        $r.penalty_fraction | Should Be 0.3
    }
}
