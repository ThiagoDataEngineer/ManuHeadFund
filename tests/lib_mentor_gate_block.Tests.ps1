$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_mentor_gate_block.ps1")

function _MakeContext {
    param([hashtable] $Overrides = @{})
    $base = [PSCustomObject]@{
        mode = "STANDARD"
        fqs = [PSCustomObject]@{ score = 4; category = "QUALITY" }
        beta = [PSCustomObject]@{ asset = 1.115; portfolio_after = 1.118 }
        historical = [PSCustomObject]@{ n_trades = 23; dsr = 0.42; sharpe_30d = 2.1 }
        regime = [PSCustomObject]@{ phase = "phase_3_bear"; bias = "neutral" }
        drawdown = [PSCustomObject]@{ vs_peak_pct = -3.2; flag_streak = 0; level = "GREEN" }
        tori_proximity = [PSCustomObject]@{ valid = $true; side = "LONG"; proximity_pct = 2.3; action_line = 100.5; touches = 4; slope_deg = 22; rsi = 35; vol_drying = $true; setup_ripening = $true }
        gates = $null
    }
    foreach ($k in $Overrides.Keys) {
        $base | Add-Member -MemberType NoteProperty -Name $k -Value $Overrides[$k] -Force
    }
    return $base
}

Describe "Build-GateStatusBlock" {
    It "All gates present: produz bloco completo com todas tags" {
        $ctx = _MakeContext
        $block = Build-GateStatusBlock -FullContext $ctx
        $block | Should Match "=== GATE STATUS"
        $block | Should Match "=== END GATE STATUS"
        $block | Should Match "\[FQS\]"
        $block | Should Match "\[BETA\]"
        $block | Should Match "\[DSR_HISTORY\]"
        $block | Should Match "\[REGIME\]"
        $block | Should Match "\[DRAWDOWN\]"
        $block | Should Match "\[TORI_PROX\]"
        $block | Should Match "\[MODE\]"
    }

    It "FQS score=4 QUALITY presente literalmente" {
        $ctx = _MakeContext
        $block = Build-GateStatusBlock -FullContext $ctx
        $block | Should Match "score=4/7 QUALITY"
    }

    It "FQS missing: vira [FQS] ABSENT" {
        $ctx = _MakeContext -Overrides @{ fqs = $null }
        $block = Build-GateStatusBlock -FullContext $ctx
        $block | Should Match "\[FQS\]\s+ABSENT"
    }

    It "FQS no_registry: vira [FQS] ABSENT (enrich agendado)" {
        $ctx = _MakeContext -Overrides @{
            fqs = [PSCustomObject]@{ score = $null; category = "N/A_no_registry" }
        }
        $block = Build-GateStatusBlock -FullContext $ctx
        $block | Should Match "\[FQS\]\s+ABSENT.*enrich"
    }

    It "BETA missing: vira [BETA] ABSENT" {
        $ctx = _MakeContext -Overrides @{ beta = $null }
        $block = Build-GateStatusBlock -FullContext $ctx
        $block | Should Match "\[BETA\]\s+ABSENT"
    }

    It "Multiple gates absent: todos viram ABSENT (nunca silent)" {
        $ctx = _MakeContext -Overrides @{ fqs = $null; beta = $null; historical = $null }
        $block = Build-GateStatusBlock -FullContext $ctx
        ($block -split "`n" | Where-Object { $_ -match "ABSENT" }).Count | Should BeGreaterThan 2
    }

    It "TORI_PROX valid=false: vira ABSENT" {
        $ctx = _MakeContext -Overrides @{
            tori_proximity = [PSCustomObject]@{ valid = $false }
        }
        $block = Build-GateStatusBlock -FullContext $ctx
        $block | Should Match "\[TORI_PROX\]\s+ABSENT"
    }

    It "TORI_PROX ripening=true: tag RIPENING presente" {
        $ctx = _MakeContext  # default ripening=true
        $block = Build-GateStatusBlock -FullContext $ctx
        $block | Should Match "RIPENING"
    }

    It "TORI_PROX ripening=false: tag 'watch' presente" {
        $ctx = _MakeContext
        $ctx.tori_proximity.setup_ripening = $false
        $block = Build-GateStatusBlock -FullContext $ctx
        $block | Should Match "watch"
    }

    It "MODE field sempre presente" {
        $ctx = _MakeContext -Overrides @{ mode = "GEM_DISCOVERY" }
        $block = Build-GateStatusBlock -FullContext $ctx
        $block | Should Match "GEM_DISCOVERY"
    }
}

Describe "Test-PromptForbiddenPhrases" {
    It "Texto limpo: has_forbidden=false" {
        $r = Test-PromptForbiddenPhrases -Text "Setup decente com FQS=4/7 QUALITY"
        $r.has_forbidden | Should Be $false
        $r.found.Count | Should Be 0
    }

    It "Texto com 'Mesa pulou': has_forbidden=true" {
        $r = Test-PromptForbiddenPhrases -Text "Mesa pulou o debate por Tier A skip"
        $r.has_forbidden | Should Be $true
        $r.found -contains "Mesa pulou" | Should Be $true
    }

    It "Texto com 'FQS indisponivel' + gate block sem ABSENT: hallucination detected" {
        $block = "=== GATE STATUS ===`n[FQS] score=4/7 QUALITY`n=== END ==="
        $r = Test-PromptForbiddenPhrases -Text "FQS indisponivel para este market" -GateStatusBlock $block
        $r.has_forbidden | Should Be $true
    }

    It "Texto com 'FQS indisponivel' + gate block COM [FQS] ABSENT: NAO eh forbidden (justificado)" {
        $block = "=== GATE STATUS ===`n[FQS] ABSENT (no data)`n=== END ==="
        $r = Test-PromptForbiddenPhrases -Text "FQS indisponivel para este market" -GateStatusBlock $block
        # Smart detection: phrase justificada pq gate eh realmente ABSENT
        $r.has_forbidden | Should Be $false
    }

    It "Multiple forbidden phrases: todas reportadas" {
        $r = Test-PromptForbiddenPhrases -Text "Mesa pulou e FQS missing causaram veto"
        $r.found.Count | Should BeGreaterThan 1
    }
}

Describe "Get-MentorForbiddenPhrasesList" {
    It "Retorna lista nao vazia" {
        $list = Get-MentorForbiddenPhrasesList
        $list.Count | Should BeGreaterThan 0
    }

    It "Lista contem 'Mesa pulou' (skill registered phrase)" {
        $list = Get-MentorForbiddenPhrasesList
        $list -contains "Mesa pulou" | Should Be $true
    }
}

Describe "Property: Build-GateStatusBlock determinismo" {
    It "Mesma entrada produz mesma saida" {
        $ctx = _MakeContext
        $b1 = Build-GateStatusBlock -FullContext $ctx
        $b2 = Build-GateStatusBlock -FullContext $ctx
        $b1 | Should Be $b2
    }
}

Describe "Property: cada gate aparece exatamente 1x" {
    It "Tags unicas no bloco" {
        $ctx = _MakeContext
        $block = Build-GateStatusBlock -FullContext $ctx
        foreach ($tag in @("[FQS]","[BETA]","[DSR_HISTORY]","[REGIME]","[DRAWDOWN]","[TORI_PROX]","[MODE]")) {
            $count = ([regex]::Matches($block, [regex]::Escape($tag))).Count
            $count | Should Be 1
        }
    }
}

Describe "Property: ABSENT count consistency" {
    It "Numero de gates ABSENT igual a gates omitted no FullContext" {
        $ctx = _MakeContext -Overrides @{ fqs = $null; beta = $null }
        $block = Build-GateStatusBlock -FullContext $ctx
        $absentCount = ([regex]::Matches($block, "ABSENT")).Count
        # FQS + BETA absent = 2; TORI ainda valid; outros present
        $absentCount | Should Be 2
    }
}
