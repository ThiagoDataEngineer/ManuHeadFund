$script:fase4Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:fase4Root = Split-Path -Parent $fase4Here
. (Join-Path $fase4Root "agents\lib_quant_whitelist.ps1")

# fase4_tier_a_forced_priority.Tests.ps1 -- Lockdown anti-regression FASE 4 parte 2.
# Pester 3.x.
#
# Bug 2026-05-21 manha PARTE 2: marketType fix da merge resolveu drop em filter,
# mas Tier A LIVE seguia ausente do orchestrator porque sort por compScore enterra
# markets estaveis low-momentum (BTC). Pre-screen reconstroi candidates sem score=100.
#
# Fix: forcedSet captura markets quant_whitelist_*, propaga isWhitelistForced=true
# no candidate, e sort prioriza por isWhitelistForced DESC, depois compScore DESC.
#
# Esta suite valida o comportamento de sort puro (sem rodar pre-screen real).

Describe "FASE 4 part 2 - Sort priority Tier A LIVE" {

    It "Sort prioriza isWhitelistForced=true mesmo com compScore baixo" {
        $candidates = @(
            [PSCustomObject]@{ market='HYPEUSDT'; compScore=90; vol=4.5; isWhitelistForced=$false },
            [PSCustomObject]@{ market='USELESSUSDT'; compScore=85; vol=3.2; isWhitelistForced=$false },
            [PSCustomObject]@{ market='BTCUSDT'; compScore=25; vol=0.9; isWhitelistForced=$true },
            [PSCustomObject]@{ market='RENDERUSDT'; compScore=30; vol=1.1; isWhitelistForced=$true }
        )
        $top = @($candidates | Sort-Object -Property `
            @{Expression='isWhitelistForced';Descending=$true}, `
            @{Expression='compScore';Descending=$true}, `
            @{Expression='vol';Descending=$true} | Select-Object -First 3)

        # Esperado: BTC + RENDER (forced) primeiro, depois HYPE (highest compScore unforced)
        $top[0].market | Should Be 'RENDERUSDT'  # forced, compScore 30
        $top[1].market | Should Be 'BTCUSDT'      # forced, compScore 25
        $top[2].market | Should Be 'HYPEUSDT'     # unforced, compScore 90
    }

    It "Tie-break por compScore quando ambos forced" {
        $candidates = @(
            [PSCustomObject]@{ market='BTCUSDT'; compScore=25; vol=0.9; isWhitelistForced=$true },
            [PSCustomObject]@{ market='RENDERUSDT'; compScore=30; vol=1.1; isWhitelistForced=$true },
            [PSCustomObject]@{ market='INJUSDT'; compScore=45; vol=2.1; isWhitelistForced=$true }
        )
        $top = @($candidates | Sort-Object -Property `
            @{Expression='isWhitelistForced';Descending=$true}, `
            @{Expression='compScore';Descending=$true}, `
            @{Expression='vol';Descending=$true} | Select-Object -First 3)

        $top[0].market | Should Be 'INJUSDT'      # highest compScore among forced
        $top[1].market | Should Be 'RENDERUSDT'
        $top[2].market | Should Be 'BTCUSDT'
    }

    It "Sem forced, sort cai pra compScore desc (comportamento legacy preservado)" {
        $candidates = @(
            [PSCustomObject]@{ market='AAA'; compScore=10; vol=0.5; isWhitelistForced=$false },
            [PSCustomObject]@{ market='BBB'; compScore=90; vol=1.0; isWhitelistForced=$false },
            [PSCustomObject]@{ market='CCC'; compScore=50; vol=2.0; isWhitelistForced=$false }
        )
        $top = @($candidates | Sort-Object -Property `
            @{Expression='isWhitelistForced';Descending=$true}, `
            @{Expression='compScore';Descending=$true}, `
            @{Expression='vol';Descending=$true} | Select-Object -First 2)

        $top[0].market | Should Be 'BBB'
        $top[1].market | Should Be 'CCC'
    }
}


Describe "FASE 4 part 2 - forcedSet construction (integration shape)" {

    It "Identifica source='quant_whitelist_LIVE' como forced" {
        $scannerResults = @(
            [PSCustomObject]@{ market='HYPEUSDT'; source=$null },
            [PSCustomObject]@{ market='BTCUSDT'; source='quant_whitelist_LIVE' },
            [PSCustomObject]@{ market='RENDERUSDT'; source='quant_whitelist_LIVE' }
        )
        $forcedSet = @{}
        foreach ($sr in $scannerResults) {
            if ($sr.PSObject.Properties['source'] -and $sr.source -like 'quant_whitelist_*') {
                $forcedSet[$sr.market] = $true
            }
        }
        $forcedSet.Count | Should Be 2
        $forcedSet['BTCUSDT'] | Should Be $true
        $forcedSet['RENDERUSDT'] | Should Be $true
        $forcedSet.ContainsKey('HYPEUSDT') | Should Be $false
    }

    It "Lockdown wire-up em scan_master.ps1 (forcedSet + isWhitelistForced)" {
        $src = Get-Content (Join-Path $script:fase4Root "scripts\scan_master.ps1") -Raw -Encoding UTF8
        $src | Should Match 'forcedSet\s*=\s*@\{\}'
        $src | Should Match 'isWhitelistForced'
        $src | Should Match "quant_whitelist_\*"
    }

    It "FASE 4 p3: bypass pre-screen passes>=3 para forced markets" {
        # Lockdown: Tier A LIVE deve ENTRAR em $candidates mesmo se passes<3.
        # Pre-fix: BTC/RENDER/XMR podiam ser dropados em consolidacao tecnica.
        $src = Get-Content (Join-Path $script:fase4Root "scripts\scan_master.ps1") -Raw -Encoding UTF8
        # Deve ter o or-isForced no condicional
        $src | Should Match '\$passes\s+-ge\s+3\s+-or\s+\$isForced'
    }

    It "FASE 4 p4: tier_level propagado da merge ate selecao top-N" {
        # Lockdown: Mode=PAPER tem 11 forced; sem tier_level RENDER/XMR (A) sao bumped por BCH/SKY (B).
        # Merge deve setar tier_level=1 para A_LIVE e 2 para B_PAPER. Pre-screen propaga.
        # Item 1 fix 2026-05-29: scan_master agora delega selecao a Select-TopCandidates
        # (lib_top_candidates.ps1) que ordena forcados por tierLevel ASC internamente.
        # O lockdown garante que: (1) tierLevelSet existe, (2) tierLevel e propagado
        # ao candidate, (3) selecao final usa Select-TopCandidates.
        $src = Get-Content (Join-Path $script:fase4Root "scripts\scan_master.ps1") -Raw -Encoding UTF8
        # forcedSet ahora tem irmao tierLevelSet
        $src | Should Match 'tierLevelSet\s*=\s*@\{\}'
        # tier_level propagada no candidate
        $src | Should Match 'tierLevel\s*=\s*\$tierLevel'
        # selecao via Select-TopCandidates (substituiu Sort-Object 4-key)
        $src | Should Match 'Select-TopCandidates'
    }

    It "FASE 4 p5: Tier A organico recebe tier_level=1 (augment, nao skip)" {
        # Bug 2026-05-21 cycle 11:29: INJ apareceu organicamente em scanner top,
        # merge fazia -notcontains e SKIPAVA forced metadata. Result: scanner natural
        # tierLevel=99 -> bumped do top-7. Fix: augment existing entry.
        $here = $script:fase4Here
        $agentsDir = Join-Path (Split-Path -Parent $here) "agents"
        $tmpDir = Join-Path $env:TEMP ("p5_" + [guid]::NewGuid().ToString("N").Substring(0,6))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $mockPath = Join-Path $tmpDir "wl.json"
        @'
{
  "TIER_A_LIVE": [{"market":"INJUSDT","sharpe":3.88}],
  "TIER_B_PAPER": [{"market":"XRPUSDT","sharpe":3.72}],
  "TIER_C_SKIP": []
}
'@ | Out-File $mockPath -Encoding UTF8

        # INJ ja em scanner organico (com marketType=FUTURES + change/volume reais)
        $cands = @(
            [PSCustomObject]@{ market='INJUSDT'; marketType='FUTURES'; score=85; change=12.5; volume=1.2e6 },
            [PSCustomObject]@{ market='HYPEUSDT'; marketType='FUTURES'; score=90; change=18; volume=2.5e6 }
        )
        $merged = Merge-QuantWhitelistIntoCandidates -Candidates $cands -Mode 'PAPER' -Path $mockPath

        # INJ deve estar 1x (nao duplicado) + agora tem source + tier_level=1
        $injs = @($merged | Where-Object { $_.market -eq 'INJUSDT' })
        $injs.Count | Should Be 1
        $injs[0].source | Should Match 'quant_whitelist_'
        $injs[0].tier_level | Should Be 1
        # Volume original preservado (scanner real)
        $injs[0].volume | Should Be 1200000

        # XRP nao apareceu organicamente -> deve ser extra
        $xrps = @($merged | Where-Object { $_.market -eq 'XRPUSDT' })
        $xrps.Count | Should Be 1
        $xrps[0].tier_level | Should Be 2

        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    }

    It "FASE 4 p4: Sort 4-key prioriza Tier A LIVE sobre B PAPER" {
        # Cenario: 11 forced markets (4 Tier A + 7 Tier B), top-7. Sort deve garantir
        # que TODOS os 4 Tier A entram primeiro, depois top-3 Tier B por compScore.
        $candidates = @(
            [PSCustomObject]@{ market='SUIUSDT';   compScore=90; vol=4.5; isWhitelistForced=$true; tierLevel=2 },
            [PSCustomObject]@{ market='SKYUSDT';   compScore=80; vol=3.0; isWhitelistForced=$true; tierLevel=2 },
            [PSCustomObject]@{ market='BCHUSDT';   compScore=70; vol=2.5; isWhitelistForced=$true; tierLevel=2 },
            [PSCustomObject]@{ market='CFGUSDT';   compScore=60; vol=2.0; isWhitelistForced=$true; tierLevel=2 },
            [PSCustomObject]@{ market='BTCUSDT';   compScore=25; vol=0.9; isWhitelistForced=$true; tierLevel=1 },
            [PSCustomObject]@{ market='RENDERUSDT';compScore=15; vol=0.4; isWhitelistForced=$true; tierLevel=1 },
            [PSCustomObject]@{ market='INJUSDT';   compScore=50; vol=0.2; isWhitelistForced=$true; tierLevel=1 },
            [PSCustomObject]@{ market='XMRUSDT';   compScore=10; vol=0.2; isWhitelistForced=$true; tierLevel=1 },
            [PSCustomObject]@{ market='HYPEUSDT';  compScore=95; vol=5.0; isWhitelistForced=$false; tierLevel=99 }
        )
        $top = @($candidates | Sort-Object -Property `
            @{Expression='tierLevel';Descending=$false}, `
            @{Expression='isWhitelistForced';Descending=$true}, `
            @{Expression='compScore';Descending=$true}, `
            @{Expression='vol';Descending=$true} | Select-Object -First 7)

        # Top 4 devem ser Tier A LIVE (por compScore: INJ 50, BTC 25, RENDER 15, XMR 10)
        $top[0].market | Should Be 'INJUSDT'
        $top[1].market | Should Be 'BTCUSDT'
        $top[2].market | Should Be 'RENDERUSDT'
        $top[3].market | Should Be 'XMRUSDT'
        # Slots 5-7 = top 3 Tier B
        $top[4].market | Should Be 'SUIUSDT'
        $top[5].market | Should Be 'SKYUSDT'
        $top[6].market | Should Be 'BCHUSDT'
    }
}
