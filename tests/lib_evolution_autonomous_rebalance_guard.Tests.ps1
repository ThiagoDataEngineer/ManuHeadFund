# lib_evolution_autonomous_rebalance_guard.Tests.ps1 -- TDD do guard
# "so executa quando chamado direto, nao quando dot-sourced" em
# agents/lib_evolution_autonomous_rebalance.ps1.
#
# 2026-07-30: achado real -- o guard original "$PSCommandPath -eq
# $MyInvocation.MyCommand.Path" NUNCA funcionou. Dentro de um arquivo
# dot-sourced, ambos os lados apontam pro proprio arquivo sendo carregado
# (confirmado identico executado direto via -File OU dot-sourced via ".") --
# a comparacao sempre avaliava $true, entao Invoke-EvolutionAutoRebalance
# disparava de VERDADE a cada dot-source deste arquivo, reescrevendo
# agents/config.local.ps1 real com backup (~190 arquivos .backup.* acumulados
# desde 2026-07-08, gerados por qualquer comando/teste que carregasse esta
# lib, sem nenhuma intencao de rodar auto-rebalance). Fix: usa
# $MyInvocation.InvocationName -ne '.' (unico discriminador confiavel).
#
# Pester 3.4 (motor real de producao/CI) / ASCII-only.

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
$libPath = Join-Path $agentsDir "lib_evolution_autonomous_rebalance.ps1"

Describe "lib_evolution_autonomous_rebalance.ps1 -- guard dot-source vs execucao direta" {

    It "dot-source NAO dispara Invoke-EvolutionAutoRebalance (fix 2026-07-30)" {
        # Marcador global: se a funcao real rodasse, ela escreveria em
        # agents/config.local.ps1 (efeito colateral real e perigoso de se
        # disparar sem querer) -- em vez de exercitar isso, confirmamos que
        # a funcao NAO e chamada monkey-patchando Invoke-EvolutionAutoRebalance
        # ANTES do dot-source (pre-load, mesmo padrao ja usado no projeto) e
        # observando que o stub nao e invocado.
        $global:__rebalance_called = $false
        function global:Invoke-EvolutionAutoRebalance { $global:__rebalance_called = $true }

        . $libPath

        $global:__rebalance_called | Should Be $false
    }

    It "usa MyInvocation.InvocationName como discriminador (nao PSCommandPath)" {
        # Guard antigo comparava $PSCommandPath -eq $MyInvocation.MyCommand.Path
        # -- confirmado via debug real que ambos sao SEMPRE iguais dentro do
        # arquivo dot-sourced (mesmo valor executado direto ou via dot-source),
        # entao essa comparacao nunca protegia nada. O fix real usa
        # $MyInvocation.InvocationName -ne '.' (unico valor que realmente
        # difere: '.' quando dot-sourced, caminho completo quando direto).
        $content = Get-Content $libPath -Raw
        ($content -match [regex]::Escape("if (`$MyInvocation.InvocationName -ne '.')")) | Should Be $true
    }
}
