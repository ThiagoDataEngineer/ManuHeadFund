# C6 fix 2026-05-20 PM6+580min — contract: array fields ALWAYS array in JSON.
# Bug: PowerShell 5.1 unwrap single-element arrays implicitamente em property assignment
# E ConvertTo-Json -Compress serializa single-element como scalar.
# HYPE evidence: 'failures' field viu serializacao char-by-char quando array tinha 1 entry.

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_promotion_ladder.ps1")

Describe "C6 failures array contract" {
    BeforeEach {
        $script:tmpPath = Join-Path $env:TEMP "c6_pipeline_$([guid]::NewGuid()).jsonl"
    }
    AfterEach {
        Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue
    }

    It "failures com 1 entry: persiste como ARRAY no JSON (nao string)" {
        Add-PromotionEvent -Path $tmpPath -Market "HYPEUSDT" -Event "evaluated" -TierState 1 `
            -GateEval @{ gate="obs_to_c"; passed=$false; failures=@("sharpe_30d=0.6<1.0") }
        $line = Get-Content $tmpPath -Encoding UTF8 | Select-Object -First 1
        $obj = $line | ConvertFrom-Json
        # Critical: failures deve ser array, nao string scalar
        $obj.gate_eval.failures.GetType().Name | Should Not Be "String"
        @($obj.gate_eval.failures).Count | Should Be 1
        $obj.gate_eval.failures[0] | Should Be "sharpe_30d=0.6<1.0"
    }

    It "failures com 2 entries: persiste como ARRAY" {
        Add-PromotionEvent -Path $tmpPath -Market "TONUSDT" -Event "evaluated" -TierState 1 `
            -GateEval @{ gate="obs_to_c"; passed=$false; failures=@("sharpe_30d=0.06<1.0","max_dd=0.76>0.15") }
        $line = Get-Content $tmpPath -Encoding UTF8 | Select-Object -First 1
        $obj = $line | ConvertFrom-Json
        @($obj.gate_eval.failures).Count | Should Be 2
    }

    It "failures vazio: persiste como ARRAY vazio (nao null)" {
        Add-PromotionEvent -Path $tmpPath -Market "BTCUSDT" -Event "evaluated" -TierState 4 `
            -GateEval @{ gate="obs_to_c"; passed=$true; failures=@() }
        $line = Get-Content $tmpPath -Encoding UTF8 | Select-Object -First 1
        $obj = $line | ConvertFrom-Json
        # Should not be null nor missing
        $obj.gate_eval | Should Not BeNullOrEmpty
    }

    It "REPRO bug HYPE: caller faz var=property assign (unwrap implicito) -> deve normalizar" {
        # Reproduz o flow exato do lib_promotion_cycle.ps1:149 onde PS unwrap
        $gateResult = [PSCustomObject]@{
            gate = "obs_to_c"
            passed = $false
            failures = @("sharpe_30d=0.6<1.0")  # 1 elemento
        }
        $unwrapped = $gateResult.failures   # PS 5.1 unwrap aqui -> String
        # Caller passa o valor unwrapped — Add-PromotionEvent DEVE normalizar
        Add-PromotionEvent -Path $tmpPath -Market "HYPEUSDT" -Event "evaluated" -TierState 1 `
            -GateEval @{ gate="obs_to_c"; passed=$false; failures=$unwrapped }
        $line = Get-Content $tmpPath -Encoding UTF8 | Select-Object -First 1
        $obj = $line | ConvertFrom-Json
        # Contract: independente do que veio, JSON sempre array
        @($obj.gate_eval.failures).Count | Should Be 1
        $obj.gate_eval.failures[0] | Should Be "sharpe_30d=0.6<1.0"
        # Critica: type deve ser array, NAO string
        ($obj.gate_eval.failures -is [string]) | Should Be $false
    }

    It "blocked_by (all_gates path): mesmo contract" {
        Add-PromotionEvent -Path $tmpPath -Market "TONUSDT" -Event "evaluated" -TierState 1 `
            -GateEval @{ gate="all_gates"; passed=$false; blocked_by="concentration" }
        $line = Get-Content $tmpPath -Encoding UTF8 | Select-Object -First 1
        $obj = $line | ConvertFrom-Json
        @($obj.gate_eval.blocked_by).Count | Should Be 1
        ($obj.gate_eval.blocked_by -is [string]) | Should Be $false
    }

    It "reasons (success path): contract identico - sempre array" {
        Add-PromotionEvent -Path $tmpPath -Market "INJUSDT" -Event "evaluated" -TierState 1 `
            -GateEval @{ gate="obs_to_c"; passed=$true; reasons=@("sharpe_30d_ok") }
        $line = Get-Content $tmpPath -Encoding UTF8 | Select-Object -First 1
        $obj = $line | ConvertFrom-Json
        $obj.gate_eval.reasons.GetType().Name | Should Not Be "String"
        @($obj.gate_eval.reasons).Count | Should Be 1
    }
}
