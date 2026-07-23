# lib_llm_cost_telemetry.ps1

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

# LLM pricing (per million tokens)
$script:LLM_PRICING = @{
    "sonnet" = @{ input = 3; output = 15 }
    "haiku" = @{ input = 0.80; output = 4 }
    "opus" = @{ input = 15; output = 75 }
    "groq" = @{ input = 0.05; output = 0.10 }
    "mistral" = @{ input = 0.14; output = 0.42 }
}

function Record-LlmCall {
    param(
        [Parameter(Mandatory)] [string] $Model,
        [Parameter(Mandatory)] [int] $TokensIn,
        [Parameter(Mandatory)] [int] $TokensOut,
        [string] $JournalDir = $global:JOURNAL_DIR,
        [datetime] $Now = (Get-Date)
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $costsPath = Join-Path $JournalDir "llm_costs.jsonl"

    # Lookup pricing
    $pricing = $script:LLM_PRICING[$Model]
    if (-not $pricing) {
        $pricing = @{ input = 0; output = 0 }
    }

    # Calculate cost: (tokens / 1M) * price_per_million
    $costIn = ($TokensIn / 1000000) * $pricing.input
    $costOut = ($TokensOut / 1000000) * $pricing.output
    $costUsd = $costIn + $costOut

    # Registra call
    $callEntry = [ordered]@{
        timestamp = $timestamp
        model = $Model
        tokens_in = $TokensIn
        tokens_out = $TokensOut
        cost_usd = [Math]::Round($costUsd, 6)
    } | ConvertTo-Json -Compress

    Add-Content -Path $costsPath -Value $callEntry -Encoding UTF8

    return [PSCustomObject]@{
        model = $Model
        tokens_in = $TokensIn
        tokens_out = $TokensOut
        cost_usd = [Math]::Round($costUsd, 6)
        timestamp = $timestamp
    }
}

function Get-LlmCostSummary {
    param(
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    $costsPath = Join-Path $JournalDir "llm_costs.jsonl"

    $totalCost = 0
    $byModel = @{}
    $count = 0

    if (Test-Path $costsPath) {
        $lines = @(Get-Content $costsPath | Where-Object { $_.Trim() -ne "" })

        foreach ($line in $lines) {
            $obj = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($obj) {
                $totalCost += $obj.cost_usd
                if (-not $byModel[$obj.model]) {
                    $byModel[$obj.model] = 0
                }
                $byModel[$obj.model] += $obj.cost_usd
                $count++
            }
        }
    }

    return [PSCustomObject]@{
        total_cost_usd = [Math]::Round($totalCost, 6)
        by_model = $byModel
        count = $count
        summary_path = $costsPath
    }
}
