# evolution_params_not_tracked.Tests.ps1 -- TDD do bug real 2026-08-04.
#
# journal/evolution_params.json foi commitado em 07-25 (!journal/evolution_params.json
# no .gitignore) com a intencao de "chegar no cloud" -- mas diferente de
# coin_registry.json/per_asset_whitelist (curadoria manual, nunca escrita em
# runtime), este arquivo E' escrito pelo proprio Invoke-EvolutionCycle a cada
# ciclo. Resultado real: todo checkout limpo (cron a cada 6h) resetava o
# overlay pro valor commitado (sentinel_move_pct=3.25), apagando o progresso
# do ciclo anterior -- historico mostrava a MESMA proposta "3.25 -> 3" se
# repetindo 41x seguidas sem nunca colar. Fix: untrack + volta pra regra
# generica journal/*.json (gitignored). Pester 3.4 / ASCII-only.

$root = Split-Path $PSScriptRoot -Parent

Describe "journal/evolution_params.json NAO pode ser tracked no git" {

    It "esta ausente do indice do git (git ls-files)" {
        Push-Location $root
        try {
            $tracked = git ls-files -- "journal/evolution_params.json"
        } finally {
            Pop-Location
        }
        $tracked | Should BeNullOrEmpty
    }

    It "e coberto pela regra generica journal/*.json (git check-ignore)" {
        Push-Location $root
        try {
            & git check-ignore -q "journal/evolution_params.json"
            $ignored = ($LASTEXITCODE -eq 0)
        } finally {
            Pop-Location
        }
        $ignored | Should Be $true
    }

    It ".gitignore NAO tem excecao ativa (!journal/evolution_params.json)" {
        $content = Get-Content (Join-Path $root ".gitignore") -Raw
        # Aceita a linha em texto de comentario/historico, mas nao como regra ativa
        # (linha comecando com ! sem # antes, fora de bloco de comentario).
        $activeException = $content -split "`n" | Where-Object {
            $_.TrimStart() -eq "!journal/evolution_params.json"
        }
        @($activeException).Count | Should Be 0
    }
}
