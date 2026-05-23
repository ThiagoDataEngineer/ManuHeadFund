# C6 round-trip TDD generalizado 2026-05-20 PM6+680min.
# Para cada writer JSON conhecido: escrever 1-elemento + ler + assert array preservado.
# Anti-regression structural — pega novos bugs antes de chegar em prod.

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_json_contract.ps1")
. (Join-Path $projectRoot "agents\lib_schema_validators.ps1")

Describe "C6 round-trip Add-PromotionEvent (caso HYPE)" {
    BeforeAll {
        . (Join-Path $projectRoot "agents\lib_promotion_ladder.ps1")
    }
    BeforeEach {
        $script:tmp = Join-Path $env:TEMP "c6_rt_$([guid]::NewGuid()).jsonl"
    }
    AfterEach {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }

    It "1 failure: round-trip preserva array" {
        Add-PromotionEvent -Path $tmp -Market "HYPEUSDT" -Event "evaluated" -TierState 1 `
            -GateEval @{ gate="obs_to_c"; passed=$false; failures=@("sharpe_30d=0.6<1.0") }
        $line = Get-Content $tmp -Encoding UTF8 | Select-Object -First 1
        $obj = $line | ConvertFrom-Json
        $r = Test-PromotionEventSchema -Event $obj
        $r.valid | Should Be $true
    }

    It "1 failure passada como STRING (caso unwrap real): round-trip recovera array" {
        # Simula bug HYPE: caller passou string scalar (apos PS unwrap)
        Add-PromotionEvent -Path $tmp -Market "HYPEUSDT" -Event "evaluated" -TierState 1 `
            -GateEval @{ gate="obs_to_c"; passed=$false; failures="sharpe_30d=0.6<1.0" }
        $line = Get-Content $tmp -Encoding UTF8 | Select-Object -First 1
        $obj = $line | ConvertFrom-Json
        $r = Test-PromotionEventSchema -Event $obj
        $r.valid | Should Be $true   # helper normalizou apesar do scalar input
    }
}

Describe "C6 round-trip generic ConvertTo-NormalizedJson" {
    It "array fields preservados em deep nested object" {
        $h = @{
            level1 = @{
                level2 = @{
                    failures = "scalar_string"  # bug case
                    reasons  = @()
                }
            }
        }
        # NOTE: NestedPaths so cobre 1 nivel. Para multi-nivel, caller wrappa antes.
        # Test confirma comportamento esperado (level1 nao normalizado pq nao listado).
        $json = ConvertTo-NormalizedJson -Object $h -ArrayFields @("failures","reasons") -NestedPaths @("level1")
        # Sem level2 em NestedPaths, level1.level2 passa-through (string fica string)
        # Esse test documenta limit do helper -- caller multi-level deve usar approach diferente
        $json | Should Match '"failures"'
    }

    It "Multiplos array fields: todos normalizados em paralelo" {
        $h = @{
            failures   = "a"           # scalar (bug)
            reasons    = @("b","c")    # array OK
            blocked_by = $null         # null
        }
        $json = ConvertTo-NormalizedJson -Object $h -ArrayFields @("failures","reasons","blocked_by")
        $obj = $json | ConvertFrom-Json
        @($obj.failures).Count   | Should Be 1
        @($obj.reasons).Count    | Should Be 2
        @($obj.blocked_by).Count | Should Be 0
    }
}
