# gate_invariants_static.Tests.ps1 — invariantes estaticos da classe de bugs 2026-07-03
# Classe: (a) comparacao de $scen.scenario com valor que NUNCA existe (flag nasce morta);
#         (b) gate lendo direcao antes dela ser resolvida.
# Estes testes leem o CODIGO — pegam o bug no commit, nao em producao 4 ciclos depois.

$root = Split-Path $PSScriptRoot -Parent

Describe "Invariantes: cenario enum" {
    It "toda comparacao com scen.scenario usa valor valido do enum" {
        # Enum real extraido da fonte de verdade (lib_market_scenario)
        $libText = Get-Content (Join-Path $root "agents\lib_market_scenario.ps1") -Raw
        $enumVals = [regex]::Matches($libText, 'scenario="([A-Z_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        $enumVals.Count | Should BeGreaterThan 3

        # Varre comparacoes em todo agents/ + scripts/
        $bad = @()
        foreach ($f in (Get-ChildItem (Join-Path $root "agents\*.ps1"), (Join-Path $root "scripts\*.ps1") -ErrorAction SilentlyContinue)) {
            $txt = Get-Content $f.FullName -Raw
            $comps = [regex]::Matches($txt, '\$scen\.scenario\s+-(?:eq|ne)\s+"([A-Z_]+)"')
            foreach ($c in $comps) {
                $val = $c.Groups[1].Value
                if ($val -notin $enumVals) {
                    $bad += "$($f.Name): compara scenario com '$val' (enum: $($enumVals -join ','))"
                }
            }
        }
        if ($bad.Count -gt 0) { throw ($bad -join "`n") }
        $bad.Count | Should Be 0
    }
}

Describe "Invariantes: direcao no gate de cenario (gem_executor)" {
    It "gate de cenario le a direcao do Gem, nao de variavel resolvida depois" {
        $txt = Get-Content (Join-Path $root "agents\gem_executor.ps1") -Raw
        # A secao do gate (1c CENARIO) deve conter leitura de $Gem.direction
        $gateSection = [regex]::Match($txt, '(?s)1c\. CENARIO.*?\[CENARIO OK\]').Value
        $gateSection | Should Not BeNullOrEmpty
        ($gateSection -match '\$Gem\.(PSObject\.Properties\[.direction.\]|direction)') | Should Be $true
    }

    It "dirForGate nao depende exclusivamente de `$direction (resolvida tarde)" {
        $txt = Get-Content (Join-Path $root "agents\gem_executor.ps1") -Raw
        # padrao antigo quebrado: dirForGate = if ($direction) {...} else {"LONG"} sem $Gem
        $oldPattern = '\$dirForGate\s*=\s*if\s*\(\s*\$direction\s*\)'
        ($txt -match $oldPattern) | Should Be $false
    }
}

Describe "Invariantes: flags referenciadas existem no codigo com condicao alcancavel" {
    It "ALLOW_LONG_IN_BEAR_WEAK usa regime global (nao cenario)" {
        $txt = Get-Content (Join-Path $root "agents\gem_executor.ps1") -Raw
        $section = [regex]::Match($txt, '(?s)ALLOW_LONG_IN_BEAR_WEAK.{0,600}').Value
        # a condicao deve referenciar CURRENT_REGIME, nunca scen.scenario -eq BEAR_WEAK
        ($section -match 'CURRENT_REGIME') | Should Be $true
        ($section -match '\$scen\.scenario\s+-eq\s+"BEAR_WEAK"') | Should Be $false
    }
}
