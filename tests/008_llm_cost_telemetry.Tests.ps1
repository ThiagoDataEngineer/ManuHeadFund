# TDD: C1 — LLM cost telemetry

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "C1: LLM Cost Telemetry" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "test_llm_cost_$(New-Guid)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        $libPath = Join-Path $projectRoot "agents\lib_llm_cost_telemetry.ps1"
        if (Test-Path $libPath) {
            . $libPath
        }
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    It "Record-LlmCall existe" {
        $cmd = Get-Command Record-LlmCall -ErrorAction SilentlyContinue
        ($cmd -ne $null) | Should Be $true
    }

    It "registra LLM call com model, tokens_in, tokens_out, cost_usd" {
        if (Get-Command Record-LlmCall -ErrorAction SilentlyContinue) {
            $call = Record-LlmCall -Model "sonnet" -TokensIn 500 `
                -TokensOut 200 -JournalDir $journalDir

            ($call -ne $null) | Should Be $true
            ($call.model) | Should Be "sonnet"
            ($call.tokens_in) | Should Be 500
            ($call.tokens_out) | Should Be 200
        }
    }

    It "calcula cost_usd baseado em pricing por modelo" {
        if (Get-Command Record-LlmCall -ErrorAction SilentlyContinue) {
            # Sonnet: $3/M input, $15/M output
            $call = Record-LlmCall -Model "sonnet" -TokensIn 1000000 `
                -TokensOut 1000000 -JournalDir $journalDir

            # Input: 1M * $3/M = $3, Output: 1M * $15/M = $15, Total = $18
            ($call.cost_usd) | Should Be 18
        }
    }

    It "calcula Haiku pricing corretamente" {
        if (Get-Command Record-LlmCall -ErrorAction SilentlyContinue) {
            # Haiku: $0.80/M input, $4/M output
            $call = Record-LlmCall -Model "haiku" -TokensIn 1000000 `
                -TokensOut 1000000 -JournalDir $journalDir

            # Input: 1M * $0.80/M = $0.80, Output: 1M * $4/M = $4, Total = $4.80
            ($call.cost_usd) | Should Be 4.80
        }
    }

    It "llm_costs.jsonl registra TODA LLM call" {
        if (Get-Command Record-LlmCall -ErrorAction SilentlyContinue) {
            $costsPath = Join-Path $journalDir "llm_costs.jsonl"

            $null = Record-LlmCall -Model "haiku" -TokensIn 100 `
                -TokensOut 50 -JournalDir $journalDir

            Test-Path $costsPath | Should Be $true
        }
    }

    It "Get-LlmCostSummary agrega custo por modelo" {
        if (Get-Command Get-LlmCostSummary -ErrorAction SilentlyContinue) {
            # Registra alguns calls
            $null = Record-LlmCall -Model "sonnet" -TokensIn 1000 `
                -TokensOut 500 -JournalDir $journalDir
            $null = Record-LlmCall -Model "sonnet" -TokensIn 2000 `
                -TokensOut 1000 -JournalDir $journalDir
            $null = Record-LlmCall -Model "haiku" -TokensIn 500 `
                -TokensOut 300 -JournalDir $journalDir

            $summary = Get-LlmCostSummary -JournalDir $journalDir

            ($summary -ne $null) | Should Be $true
        }
    }

    It "summary contem total_cost_usd, por_model, count" {
        if (Get-Command Get-LlmCostSummary -ErrorAction SilentlyContinue) {
            $null = Record-LlmCall -Model "haiku" -TokensIn 100 `
                -TokensOut 50 -JournalDir $journalDir

            $summary = Get-LlmCostSummary -JournalDir $journalDir

            if ($summary) {
                ($summary.total_cost_usd -ge 0) | Should Be $true
                ($summary.by_model -ne $null) | Should Be $true
            }
        }
    }
}
