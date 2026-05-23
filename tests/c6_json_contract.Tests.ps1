# C6 helper TDD 2026-05-20 PM6+620min.
# Contrato de normalizacao JSON pra eliminar bug HYPE (single-element array unwrap em PS 5.1).
#
# Helper centralizado expoe:
#   ConvertTo-NormalizedJson  - escreve JSON normalizando array fields conhecidos
#   Get-NormalizedJsonArray   - read-side: garante field eh array (re-wrap scalar)
#   Test-JsonSchemaArray      - predicate: field eh array valido?

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_json_contract.ps1")

Describe "C6 ConvertTo-NormalizedJson - write contract" {
    It "Single-element array preserved como array no JSON output" {
        $h = @{ gate="obs_to_c"; failures=@("sharpe_30d=0.6<1.0") }
        $json = ConvertTo-NormalizedJson -Object $h -ArrayFields @("failures")
        $obj = $json | ConvertFrom-Json
        ($obj.failures -is [string]) | Should Be $false
        @($obj.failures).Count | Should Be 1
        $obj.failures[0] | Should Be "sharpe_30d=0.6<1.0"
    }
    It "Caso HYPE real (string scalar passa): NORMALIZADO pra array" {
        # Simula o caso real onde caller passa string (pos-unwrap) e helper recovera array
        $json = ConvertTo-NormalizedJson -Object @{ failures="sharpe_30d=0.6<1.0" } -ArrayFields @("failures")
        $obj = $json | ConvertFrom-Json
        ($obj.failures -is [string]) | Should Be $false
        @($obj.failures).Count | Should Be 1
        $obj.failures[0] | Should Be "sharpe_30d=0.6<1.0"
    }
    It "Multi-element array: array preservado" {
        $h = @{ failures=@("a","b","c") }
        $json = ConvertTo-NormalizedJson -Object $h -ArrayFields @("failures")
        $obj = $json | ConvertFrom-Json
        @($obj.failures).Count | Should Be 3
    }
    It "Empty array: persiste como [] (nao null)" {
        $h = @{ failures=@() }
        $json = ConvertTo-NormalizedJson -Object $h -ArrayFields @("failures")
        # JSON deve conter "failures":[]
        $json | Should Match '"failures":\s*\[\s*\]'
    }
    It "Field nao listado em ArrayFields: passa through inalterado" {
        $h = @{ name="BTC"; price=50000 }
        $json = ConvertTo-NormalizedJson -Object $h -ArrayFields @("failures")
        $obj = $json | ConvertFrom-Json
        $obj.name | Should Be "BTC"
        $obj.price | Should Be 50000
    }
    It "Nested array field (gate_eval.failures): normaliza recursivamente" {
        $h = @{ gate_eval = @{ gate="obs_to_c"; failures="single_string_unwrap" } }
        $json = ConvertTo-NormalizedJson -Object $h -ArrayFields @("failures") -NestedPaths @("gate_eval")
        $obj = $json | ConvertFrom-Json
        @($obj.gate_eval.failures).Count | Should Be 1
        ($obj.gate_eval.failures -is [string]) | Should Be $false
    }
}

Describe "C6 Get-NormalizedJsonArray - read contract" {
    It "Input scalar string: returns array com 1 elemento" {
        $r = Get-NormalizedJsonArray "single_string"
        @($r).Count | Should Be 1
        $r[0] | Should Be "single_string"
    }
    It "Input array: returns array (passthrough)" {
        $r = Get-NormalizedJsonArray @("a","b","c")
        @($r).Count | Should Be 3
    }
    It "Input null: returns empty array" {
        $r = Get-NormalizedJsonArray $null
        @($r).Count | Should Be 0
    }
    It "Input empty array: returns empty array" {
        $r = Get-NormalizedJsonArray @()
        @($r).Count | Should Be 0
    }
}

Describe "C6 Test-JsonSchemaArray - validator predicate" {
    It "Field array valido: true" {
        # Hashtable preserva array sem unwrap
        $h = @{ failures = [string[]]@("a","b") }
        $r = Test-JsonSchemaArray -Object $h -FieldName "failures"
        $r | Should Be $true
    }
    It "Field string (bug HYPE): false" {
        $h = @{ failures = "single_string" }
        $r = Test-JsonSchemaArray -Object $h -FieldName "failures"
        $r | Should Be $false
    }
    It "Field ausente: true (campo opcional)" {
        $h = @{ outro = "x" }
        $r = Test-JsonSchemaArray -Object $h -FieldName "failures"
        $r | Should Be $true
    }
}
