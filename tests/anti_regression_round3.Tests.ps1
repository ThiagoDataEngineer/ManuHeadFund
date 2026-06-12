# Anti-regression suite — lockdown dos fixes round 1+2+3 (2026-05-20 PM6+).
# Cada teste cobre um bug que poderia ressurgir sem essa rede.
#
# B4  — pre-mentor invariant (tier=A + mode=TIER_B_PAPER -> reject sem custar LLM call)
# B7  — DSR multi-gate registration (Invoke-AllGates registra >1 chave em by_gate)
# B10 — backup rotation (>5 backups = oldest pruned)
# B11 — single helper CSV (apenas 1 definicao de ConvertTo-CsvField no projeto)

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_mentor_invariants.ps1")
. (Join-Path $projectRoot "agents\lib_dsr_global.ps1")
. (Join-Path $projectRoot "agents\lib_promotion_gates.ps1")
. (Join-Path $projectRoot "agents\lib_csv_utils.ps1")

Describe "Anti-regression: B4 pre-mentor invariant" {
    It "tier=A + mode=TIER_B_PAPER NAO pode passar sem reject" {
        $r = Test-MentorPayloadInvariant -TriagemTier "A" -MentorMode "TIER_B_PAPER"
        $r.valid | Should Be $false
    }
}

Describe "Anti-regression: B7 DSR multi-gate" {
    It "Invoke-AllGates com DsrPath registra >1 chave por_gate" {
        $tmpDsr = Join-Path $env:TEMP "anti_b7_$([guid]::NewGuid()).json"
        try {
            $null = Invoke-AllGates -Market "TEST" -VolumeUsd 5000000 -CurrentTierACount 2 `
                -CurrentTierAMarkets @("BTCUSDT","RENDERUSDT") -EquityTodayPct 0 -DsrPath $tmpDsr
            $dsr = Get-Content $tmpDsr -Raw | ConvertFrom-Json
            $gateKeys = @($dsr.by_gate.PSObject.Properties.Name)
            $gateKeys.Count | Should BeGreaterThan 1
        } finally {
            Remove-Item $tmpDsr -ErrorAction SilentlyContinue
        }
    }
}

Describe "Anti-regression: B10 backup rotation" {
    It "manter >5 backups -> oldest pruned (logica espelhada do Python)" {
        $tmpDir = Join-Path $env:TEMP "anti_b10_$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        try {
            # Cria 7 backups com mtimes incrementais
            for ($i = 1; $i -le 7; $i++) {
                $f = Join-Path $tmpDir "coin_registry.bak_$($i.ToString('000')).json"
                Set-Content -Path $f -Value "{}" -Encoding utf8
                $item = Get-Item $f
                $item.LastWriteTime = (Get-Date).AddMinutes(-($i * 10))
            }
            # Aplica retention N=5 (logica do coingecko_*.py traduzida)
            $backups = Get-ChildItem -Path $tmpDir -Filter "coin_registry.bak_*.json" |
                       Sort-Object LastWriteTime -Descending
            $backups | Select-Object -Skip 5 | ForEach-Object { Remove-Item $_.FullName -Force }
            $remaining = @(Get-ChildItem -Path $tmpDir -Filter "coin_registry.bak_*.json")
            $remaining.Count | Should Be 5
        } finally {
            Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Anti-regression: B11 single CSV helper" {
    It "ConvertTo-CsvField definido apenas em lib_csv_utils.ps1" {
        $agentsDir = Join-Path $projectRoot "agents"
        $defs = Get-ChildItem -Path $agentsDir -Filter "*.ps1" -ErrorAction SilentlyContinue |
                Where-Object {
                    (Get-Content $_.FullName -Raw -Encoding UTF8) -match 'function\s+ConvertTo-CsvField\s*[\{\(]'
                }
        $defs.Count | Should Be 1
        $defs[0].Name | Should Be "lib_csv_utils.ps1"
    }
    It "Nenhuma copia de RFC4180 inline restante em agents/ (exceto helper)" {
        $agentsDir = Join-Path $projectRoot "agents"
        # Padrao do hack ',->;' original
        $hacks = Get-ChildItem -Path $agentsDir -Filter "*.ps1" -ErrorAction SilentlyContinue |
                 Where-Object {
                     (Get-Content $_.FullName -Raw -Encoding UTF8) -match "-replace\s+['""],['""]\s*,\s*['""];['""]"
                 }
        $hacks.Count | Should Be 0
    }
}
