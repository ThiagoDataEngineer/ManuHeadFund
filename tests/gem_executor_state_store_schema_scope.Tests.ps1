# gem_executor_state_store_schema_scope.Tests.ps1 -- TDD
#
# Achado real 2026-08-15: $env:STATE_STORE_SCHEMA = "manuheadfund" so era
# forcado dentro do bloco de Add-TrailingPosition (~linha 2555, registro de
# trade ABERTO). Mas Write-SignalSkip (candidatos REJEITADOS -- a materia-
# prima real de trade_rejections/mce_counterfactual_agg/Evolution Engine) e
# chamada 6x ANTES desse ponto no arquivo (linhas ~469-2230). Resultado:
# trade_rejections ficou vazia por ~1 mes em producao (confirmado via query
# real Supabase: 0 linhas), mce_counterfactual_agg parou de atualizar em
# 2026-07-17 (11 linhas, todas com gate=null, updated_at congelado), e a
# regra C de Get-EvolutionProposals (calibragem automatica do
# tori_confluence_threshold, escrita e testada desde 07-17) nunca teve
# evidencia real pra agir (sempre n=0).
#
# Fix: STATE_STORE_SCHEMA agora e forcado no TOPO do arquivo, antes de
# QUALQUER dot-source ou chamada de persistencia -- cobre Write-SignalSkip
# e qualquer outra chamada de Save-StateRecords no arquivo inteiro.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"

Describe "gem_executor.ps1 -- STATE_STORE_SCHEMA forcado no topo do arquivo" {

    It "define \$env:STATE_STORE_SCHEMA=manuheadfund ANTES de qualquer dot-source REAL (primeiras linhas do arquivo)" {
        $lines = Get-Content (Join-Path $agentsDir "gem_executor.ps1")
        $schemaLineNum = -1
        $firstRealDotSourceLineNum = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i].TrimStart()
            if ($schemaLineNum -eq -1 -and $line -eq '$env:STATE_STORE_SCHEMA = "manuheadfund"') {
                $schemaLineNum = $i
            }
            if ($firstRealDotSourceLineNum -eq -1 -and $line.StartsWith('. (Join-Path $PSScriptRoot')) {
                $firstRealDotSourceLineNum = $i
            }
        }
        $schemaLineNum | Should BeGreaterThan -1
        $firstRealDotSourceLineNum | Should BeGreaterThan -1
        $schemaLineNum | Should BeLessThan $firstRealDotSourceLineNum
    }

    It "todas as chamadas de Write-SignalSkip ficam DEPOIS do force de schema no arquivo" {
        $content = Get-Content (Join-Path $agentsDir "gem_executor.ps1") -Raw
        $schemaLineIdx = $content.IndexOf('$env:STATE_STORE_SCHEMA = "manuheadfund"')
        $schemaLineIdx | Should BeGreaterThan -1

        $skipCalls = [regex]::Matches($content, 'Write-SignalSkip\s+-Market')
        $skipCalls.Count | Should BeGreaterThan 0
        foreach ($m in $skipCalls) {
            $m.Index | Should BeGreaterThan $schemaLineIdx
        }
    }

    It "\$env:STATE_STORE_SCHEMA fica populado apos dot-source real do arquivo (efeito observavel)" {
        # Dot-source real (mesmo padrao de gem_executor.Tests.ps1) -- confirma
        # que o efeito e observavel em runtime, nao so no texto fonte.
        Remove-Item Env:\STATE_STORE_SCHEMA -ErrorAction SilentlyContinue
        function CoinEx-Post { param($path, $body) }
        . (Join-Path $agentsDir "gem_agent.ps1")
        . (Join-Path $agentsDir "gem_executor.ps1")
        $env:STATE_STORE_SCHEMA | Should Be "manuheadfund"
    }
}
