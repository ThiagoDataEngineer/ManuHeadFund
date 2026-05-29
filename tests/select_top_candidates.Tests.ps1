# select_top_candidates.Tests.ps1 -- TDD Select-TopCandidates
#
# Funcao pura para selecionar candidatos do orchestrator V6.
#
# DESIGN 2026-05-29 (Item 1 fix):
# - Apenas BTCUSDT e mantido como forcado (anchor de mercado, sempre vivo).
# - Todos os demais markets (INJ/RENDER/CFG/ZEC/PENDLE/SUI/SKY/XRP/BCH/XMR) sao
#   tratados como organicos: so entram no top-20 se o scanner os ranquear.
# - O top fica: BTC (sempre, fora da contagem) + top-20 organicos.
#
# Pre-fix: top-10 monopolizado por 11 forcados (INJUSDT em todos os ciclos).
# Pos-fix: top tem BTC + 20 organicos competindo por compScore real.
#
# Pester 3.x. UTF-8 BOM. Sem acentos.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_top_candidates.ps1")


# ── Helpers de fixture ────────────────────────────────────────────────────────
function _Cand {
    param(
        [string]$Market,
        [int]$CompScore,
        [double]$Vol = 1.0,
        [bool]$Forced = $false,
        [int]$TierLevel = 99
    )
    [PSCustomObject]@{
        market            = $Market
        compScore         = $CompScore
        vol               = $Vol
        isWhitelistForced = $Forced
        tierLevel         = $TierLevel
    }
}


# =============================================================================
Describe "Select-TopCandidates -- so BTC forcado + top-N organicos" {

    It "lista vazia retorna lista vazia" {
        $r = @(Select-TopCandidates -Candidates @() -OrganicTopN 20)
        $r.Count | Should Be 0
    }

    It "so organicos: retorna top-N por compScore desc" {
        $cands = @(
            (_Cand -Market "AAA" -CompScore 30 -Forced:$false),
            (_Cand -Market "BBB" -CompScore 90 -Forced:$false),
            (_Cand -Market "CCC" -CompScore 50 -Forced:$false)
        )
        $r = @(Select-TopCandidates -Candidates $cands -OrganicTopN 2)
        $r.Count | Should Be 2
        $r[0].market | Should Be "BBB"
        $r[1].market | Should Be "CCC"
    }

    It "BTC presente como forcado: sempre vivo + top-N organicos (BTC fora da contagem)" {
        $cands = @(
            (_Cand -Market "BTCUSDT" -CompScore 25 -Forced:$true -TierLevel 1),
            (_Cand -Market "ALT1"    -CompScore 90 -Forced:$false),
            (_Cand -Market "ALT2"    -CompScore 80 -Forced:$false),
            (_Cand -Market "ALT3"    -CompScore 70 -Forced:$false)
        )
        $r = @(Select-TopCandidates -Candidates $cands -OrganicTopN 2)
        # BTC + 2 organicos
        $r.Count | Should Be 3
        ($r | ForEach-Object { $_.market }) -contains "BTCUSDT" | Should Be $true
        ($r | ForEach-Object { $_.market }) -contains "ALT1"    | Should Be $true
        ($r | ForEach-Object { $_.market }) -contains "ALT2"    | Should Be $true
        ($r | ForEach-Object { $_.market }) -contains "ALT3"    | Should Be $false
    }

    It "BTC ausente da lista: retorna apenas top-N organicos (sem inventar BTC)" {
        $cands = @(
            (_Cand -Market "ALT1" -CompScore 90 -Forced:$false),
            (_Cand -Market "ALT2" -CompScore 80 -Forced:$false)
        )
        $r = @(Select-TopCandidates -Candidates $cands -OrganicTopN 5)
        $r.Count | Should Be 2
        ($r | ForEach-Object { $_.market }) -contains "BTCUSDT" | Should Be $false
    }

    It "ordenacao final: BTC primeiro (anchor), depois organicos por compScore DESC" {
        $cands = @(
            (_Cand -Market "ORG_HIGH" -CompScore 95 -Forced:$false),
            (_Cand -Market "BTCUSDT"  -CompScore 25 -Forced:$true -TierLevel 1),
            (_Cand -Market "ORG_MID"  -CompScore 60 -Forced:$false),
            (_Cand -Market "ORG_LOW"  -CompScore 20 -Forced:$false)
        )
        $r = @(Select-TopCandidates -Candidates $cands -OrganicTopN 3)
        $r.Count | Should Be 4
        $r[0].market | Should Be "BTCUSDT"
        $r[1].market | Should Be "ORG_HIGH"
        $r[2].market | Should Be "ORG_MID"
        $r[3].market | Should Be "ORG_LOW"
    }

    It "menos organicos disponiveis que N: pega todos os disponiveis + BTC" {
        $cands = @(
            (_Cand -Market "BTCUSDT" -CompScore 25 -Forced:$true -TierLevel 1),
            (_Cand -Market "A" -CompScore 80 -Forced:$false),
            (_Cand -Market "B" -CompScore 60 -Forced:$false)
        )
        $r = @(Select-TopCandidates -Candidates $cands -OrganicTopN 20)
        $r.Count | Should Be 3
    }

    It "OrganicTopN=0: somente BTC (anchor only, sem expansao organica)" {
        $cands = @(
            (_Cand -Market "BTCUSDT" -CompScore 25 -Forced:$true -TierLevel 1),
            (_Cand -Market "ORG"     -CompScore 90 -Forced:$false)
        )
        $r = @(Select-TopCandidates -Candidates $cands -OrganicTopN 0)
        $r.Count | Should Be 1
        $r[0].market | Should Be "BTCUSDT"
    }

    It "BTC duplicado (forced + scanner organic) entra so uma vez (sem duplicar)" {
        # Cenario real: BTC pode aparecer organicamente E ser forcado simultaneamente.
        # Merge-QuantWhitelist faz augment in-place, mas queremos garantir que se
        # houver entrada duplicada, dedup por market.
        $cands = @(
            (_Cand -Market "BTCUSDT" -CompScore 25 -Forced:$true -TierLevel 1),
            (_Cand -Market "ALT1"    -CompScore 90 -Forced:$false)
        )
        $r = @(Select-TopCandidates -Candidates $cands -OrganicTopN 5)
        @($r | Where-Object { $_.market -eq "BTCUSDT" }).Count | Should Be 1
    }
}


# =============================================================================
# CASO REAL INJUSDT (2026-05-29)
# Pre-fix: 11 forcados + N=10 -> top-10 monopolizado, 0 organicos
# Pos-fix com Item 1 (regime BEAR -> tier 3): no-op em producao (ainda 10 forcados)
# Pos-fix com Item 2 (so BTC forcado + 20 organicos): BTC + 20 organicos reais
Describe "Caso INJUSDT 2026-05-29: so BTC forcado, 20 organicos competindo" {

    It "Cenario producao: BTC + INJ ex-forcado + 25 alts organicas com N=20" {
        $cands = @()
        # Apenas BTC permanece forcado (anchor)
        $cands += _Cand -Market "BTCUSDT" -CompScore 25 -Forced:$true -TierLevel 1
        # INJ e demais ex-forcados agora sao organicos -- competem por compScore
        $exForced = @("INJUSDT","RENDERUSDT","CFGUSDT","ZECUSDT","PENDLEUSDT",
                      "SKYUSDT","XRPUSDT","BCHUSDT","SUIUSDT","XMRUSDT")
        for ($i = 0; $i -lt $exForced.Count; $i++) {
            # compScore baixo (~20) simula realidade: ativos da whitelist em mercado bear
            # nao tem momentum forte
            $cands += _Cand -Market $exForced[$i] -CompScore (20 + $i) -Forced:$false
        }
        # 25 candidatos organicos do scanner com compScore alto (real momentum)
        for ($i = 0; $i -lt 25; $i++) {
            $cands += _Cand -Market ("ORG{0:D2}USDT" -f $i) -CompScore (95 - $i) -Forced:$false
        }

        $r = @(Select-TopCandidates -Candidates $cands -OrganicTopN 20)

        # BTC sempre vivo
        ($r | ForEach-Object { $_.market }) -contains "BTCUSDT" | Should Be $true
        # Total: BTC + 20 organicos
        $r.Count | Should Be 21

        # Organicos selecionados: os 20 maiores compScore de TODOS os nao-forcados
        # (INJ et al competem em pe de igualdade com ORG*)
        $organicResults = @($r | Where-Object { -not $_.isWhitelistForced })
        $organicResults.Count | Should Be 20
        # ORG00..ORG19 (compScore 95..76) ganham; INJ/RENDER (compScore 20..29) ficam fora
        ($organicResults | ForEach-Object { $_.market }) -contains "ORG00USDT" | Should Be $true
        ($organicResults | ForEach-Object { $_.market }) -contains "ORG19USDT" | Should Be $true
        # INJ tem compScore=20, abaixo do ultimo ORG selecionado (compScore=76) -> NAO entra
        ($organicResults | ForEach-Object { $_.market }) -contains "INJUSDT" | Should Be $false
    }

    It "Mercado fraco: poucos organicos com momentum -> top fica menor naturalmente" {
        # Edge: dia sem volatilidade. Cenario de protecao de overtrade.
        $cands = @()
        $cands += _Cand -Market "BTCUSDT" -CompScore 25 -Forced:$true -TierLevel 1
        # Apenas 3 alts com momentum genuino
        $cands += _Cand -Market "MOVER1" -CompScore 70 -Forced:$false
        $cands += _Cand -Market "MOVER2" -CompScore 65 -Forced:$false
        $cands += _Cand -Market "MOVER3" -CompScore 55 -Forced:$false

        $r = @(Select-TopCandidates -Candidates $cands -OrganicTopN 20)
        # 1 BTC + 3 organicos = 4 (nao 21 fake)
        $r.Count | Should Be 4
    }
}
