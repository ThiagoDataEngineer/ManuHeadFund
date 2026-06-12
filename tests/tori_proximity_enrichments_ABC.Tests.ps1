# tori_proximity_enrichments_ABC.Tests.ps1 -- 2026-05-22 enriquecimentos opt-in.
# Pester 3.x. Anti-regression de:
#   A. Tori MISSED log enriquecido (gem_executor)
#   B. scan_master priority boost (compScore += 1000 quando ripening)
#   C. GemScan vol_spike confluence (+5 ripening LONG; chase_risk_high tag se invalid + prox>15%)

$script:abc_here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:abc_root = Split-Path -Parent $abc_here


Describe "A. gem_executor.ps1 - MISSED log enriquecido" {

    It "Contem bloco que cruza tori_reason MISSED com snapshot" {
        $src = Get-Content (Join-Path $abc_root "agents\gem_executor.ps1") -Raw -Encoding UTF8
        $src | Should Match 'missed_setups\.jsonl'
        $src | Should Match 'isTimingMissed'
        $src | Should Match 'Get-ToriProximityForMarket'
    }

    It "Pattern matcher cobre variantes 'missed/distanciou/overbought'" {
        $src = Get-Content (Join-Path $abc_root "agents\gem_executor.ps1") -Raw -Encoding UTF8
        $missedBlock = [regex]::Match($src, '\$isTimingMissed\s*=\s*\(.+?\)').Value
        $missedBlock | Should Match 'missed'
        $missedBlock | Should Match 'distanciou'
        $missedBlock | Should Match 'overbought'
    }

    It "Append-only JSONL (nao apaga historico)" {
        $src = Get-Content (Join-Path $abc_root "agents\gem_executor.ps1") -Raw -Encoding UTF8
        $missedBlock = [regex]::Match($src, 'missed_setups\.jsonl[\s\S]+?(?=}\s*catch|return)').Value
        $missedBlock | Should Match 'Add-Content'
        # NAO contem Set-Content nem Out-File (substituiriam)
        $missedBlock | Should Not Match 'Set-Content\b'
    }

    It "Zero risco LIVE: try/catch ao redor + Get-Command guard" {
        $src = Get-Content (Join-Path $abc_root "agents\gem_executor.ps1") -Raw -Encoding UTF8
        $src | Should Match 'Get-Command Get-ToriProximityForMarket'
    }
}


Describe "B. scan_master.ps1 - PRIORITY BOOST flag-gated" {

    It "Flag-gated via TORI_PROXIMITY_BOOST.flag" {
        $src = Get-Content (Join-Path $abc_root "scripts\scan_master.ps1") -Raw -Encoding UTF8
        $src | Should Match 'TORI_PROXIMITY_BOOST\.flag'
    }

    It "Boost = 1000 quando ripening" {
        $src = Get-Content (Join-Path $abc_root "scripts\scan_master.ps1") -Raw -Encoding UTF8
        $src | Should Match '\$ripeningBoost\s*=\s*1000'
    }

    It "compScore eh aditivo (nao substitui base)" {
        $src = Get-Content (Join-Path $abc_root "scripts\scan_master.ps1") -Raw -Encoding UTF8
        $src | Should Match '\$compScoreBoosted\s*=\s*\$compScore\s*\+\s*\$ripeningBoost'
        # compScoreBase preservado pra audit
        $src | Should Match 'compScoreBase\s*=\s*\$compScore'
    }

    It "Tag visual [TORI-RIPE-SIDE] no log de pre-screen" {
        $src = Get-Content (Join-Path $abc_root "scripts\scan_master.ps1") -Raw -Encoding UTF8
        $src | Should Match 'TORI-RIPE'
    }

    It "Zero risco LIVE: flag ausente = comportamento idêntico" {
        $src = Get-Content (Join-Path $abc_root "scripts\scan_master.ps1") -Raw -Encoding UTF8
        # Existe Test-Path guard antes do boost
        $src | Should Match 'Test-Path \$boostFlag'
    }
}


Describe "C. gem_agent.ps1 - VOL_SPIKE confluence flag-gated" {

    It "Flag-gated via TORI_PROXIMITY_CONFLUENCE.flag" {
        $src = Get-Content (Join-Path $abc_root "agents\gem_agent.ps1") -Raw -Encoding UTF8
        $src | Should Match 'TORI_PROXIMITY_CONFLUENCE\.flag'
    }

    It "Ripening LONG + pump dia >=5 = score +5 + tag G9-TORI-LONG-RIPE" {
        $src = Get-Content (Join-Path $abc_root "agents\gem_agent.ps1") -Raw -Encoding UTF8
        $src | Should Match 'G9-TORI-LONG-RIPE'
        # +5 bump quando confluente
        $src | Should Match '\$score\s*\+=\s*5'
    }

    It "Chase risk: proximity invalida + |prox| > 15% = chase_risk_high" {
        $src = Get-Content (Join-Path $abc_root "agents\gem_agent.ps1") -Raw -Encoding UTF8
        $src | Should Match '\$chaseRiskHigh\s*=\s*\$true'
        $src | Should Match 'G9-CHASE-RISK'
        $src | Should Match '15\.0'
    }

    It "chase_risk_high propagado no return object" {
        $src = Get-Content (Join-Path $abc_root "agents\gem_agent.ps1") -Raw -Encoding UTF8
        $src | Should Match 'chase_risk_high\s*=\s*\[bool\]\$chaseRiskHigh'
    }

    It "Zero risco LIVE: flag ausente = boost 0 + tag vazio" {
        $src = Get-Content (Join-Path $abc_root "agents\gem_agent.ps1") -Raw -Encoding UTF8
        $src | Should Match '\$chaseRiskHigh\s*=\s*\$false'
        $src | Should Match '\$confluenceTag\s*=\s*'''''
    }
}


Describe "Anti-regression - lib_tori_proximity docstrings" {

    It "Linha 13 atualizada: gate soft 5-35 nao 20-35" {
        $src = Get-Content (Join-Path $abc_root "agents\lib_tori_proximity.ps1") -Raw -Encoding UTF8
        # Old docstring removido
        ($src -match '(?im)>=3 toques, slope 20-35deg') | Should Be $false
        # New side-aware docstring
        $src | Should Match 'LONG\s+\(ascending support bounce\)'
        $src | Should Match 'SHORT \(descending resistance rejection\)'
    }

    It "Docstrings explicitam slopes corretos LONG (+5 a +35) e SHORT (-5 a -35)" {
        $src = Get-Content (Join-Path $abc_root "agents\lib_tori_proximity.ps1") -Raw -Encoding UTF8
        $src | Should Match 'slope \+5deg a \+35deg'
        $src | Should Match 'slope -5deg a -35deg'
    }
}
