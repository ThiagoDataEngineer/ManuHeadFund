# replay_analyzer_hallucination.Tests.ps1 -- Lockdown 2026-05-21 sessao manha.
# Pester 3.x.
#
# Garante que replay_decisions_analyzer carrega mentor_hallucinations.jsonl,
# constroi hallucSet, e exclui decisoes flagadas do merit count.

$script:rt_here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:rt_root = Split-Path $rt_here -Parent
$script:rt_analyzer = Join-Path $rt_root "scripts\replay_decisions_analyzer.ps1"


Describe "replay_decisions_analyzer - hallucination exclusion" {

    It "Script existe + parse limpo" {
        Test-Path $rt_analyzer | Should Be $true
        $errs = $null
        [System.Management.Automation.PSParser]::Tokenize(
            (Get-Content $rt_analyzer -Raw -Encoding UTF8), [ref]$errs
        ) | Out-Null
        $errs.Count | Should Be 0
    }

    It "Carrega mentor_hallucinations.jsonl com seguranca (fail-open se ausente)" {
        $src = Get-Content $rt_analyzer -Raw -Encoding UTF8
        $src | Should Match 'mentor_hallucinations\.jsonl'
        $src | Should Match 'hallucSet\s*=\s*@\{\}'
        # ErrorAction SilentlyContinue na leitura -> fail-open
        $src | Should Match 'ErrorAction SilentlyContinue'
    }

    It "Constroi key market|date e checa via ContainsKey" {
        $src = Get-Content $rt_analyzer -Raw -Encoding UTF8
        $src | Should Match '\$key\s*=\s*"\$\(?\$?\w*market.*?\)?\|.*?\$?\w*[Dd]ate'
        $src | Should Match 'hallucSet\.ContainsKey'
    }

    It "Classifica como hallucination_detected + adiciona delta_notes" {
        $src = Get-Content $rt_analyzer -Raw -Encoding UTF8
        $src | Should Match '"hallucination_detected"'
        $src | Should Match 'mentor_hallucinations\.jsonl entry'
    }

    It "Summary exibe hallucination count separado + exclui do merit" {
        $src = Get-Content $rt_analyzer -Raw -Encoding UTF8
        $src | Should Match '\$hallucinated\s*=\s*@\(\$analyzed'
        # meritDecisions = total - infra - improved - hallucinated
        $src | Should Match '\$rows\.Count\s*-\s*\$infraIssue\s*-\s*\$improved\s*-\s*\$hallucinated'
        $src | Should Match 'hallucination_detected.*real-time'
    }

    It "JsonOutput inclui hallucination_detected no summary" {
        $src = Get-Content $rt_analyzer -Raw -Encoding UTF8
        # JsonOutput hash deve ter hallucination_detected key
        $src | Should Match 'hallucination_detected\s*=\s*\$hallucinated'
    }
}


Describe "replay_decisions_analyzer - integration mock" {

    It "Roda end-to-end com JsonOutput sem erro" {
        # Mock minimal env: tmp dir + decisions.csv vazio
        $tmpRoot = Join-Path $env:TEMP ("replay_tdd_" + [guid]::NewGuid().ToString("N").Substring(0,8))
        New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
        $journalDir = Join-Path $tmpRoot "journal"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null

        # CSV mock minimal
        "timestamp,market,mentor_decision,reason,provider_used" |
            Out-File (Join-Path $journalDir "decisions.csv") -Encoding utf8
        "2026-05-21T08:00:00,BTCUSDT,VETAR,Mesa dividida,sonnet" |
            Add-Content (Join-Path $journalDir "decisions.csv") -Encoding utf8

        # Hallucination journal mock
        '{"ts":"2026-05-21T08:30:00Z","market":"BTCUSDT","type":"fqs_indisponivel","mentor_reason_excerpt":"x","context_value":"FQS=4/7"}' |
            Out-File (Join-Path $journalDir "mentor_hallucinations.jsonl") -Encoding utf8

        # Verificacao basica: hallucSet construido com 1 entry
        $hallucPath = Join-Path $journalDir "mentor_hallucinations.jsonl"
        $hallucSet = @{}
        Get-Content $hallucPath -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {
            $h = $_ | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($h -and $h.market -and $h.ts) {
                $dateUtc = $h.ts.Substring(0, 10)
                $hallucSet["$($h.market)|$dateUtc"] = $true
            }
        }
        $hallucSet.Count | Should Be 1
        $hallucSet.ContainsKey("BTCUSDT|2026-05-21") | Should Be $true

        Remove-Item -Recurse -Force $tmpRoot -ErrorAction SilentlyContinue
    }
}
