# lib_schema_validators.ps1 -- C6 fix 2026-05-20 PM6+650min.
#
# Validators read-back pra detectar JSON corrupto (HYPE-style schema violation).
# Camada complementar do lib_json_contract (write-side).
#
# Patterns detectados:
#   - Array field como scalar string (bug HYPE)
#   - Field obrigatorio ausente
#   - Type mismatch (numero como string, etc)
#
# PS 5.1, UTF-8 BOM.

if (-not (Get-Command Test-JsonSchemaArray -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "lib_json_contract.ps1")
}

function Test-PromotionEventSchema {
    <#
    .SYNOPSIS
        Valida que evento de promotion_pipeline.jsonl segue contrato schema.
    .OUTPUTS
        PSCustomObject { valid, violations }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Event)

    $violations = New-Object System.Collections.Generic.List[string]

    # Required top-level fields
    foreach ($req in @("ts","event","market")) {
        if (-not $Event.PSObject.Properties[$req]) {
            [void]$violations.Add("missing_required_field:$req")
        }
    }

    # gate_eval.failures/reasons/blocked_by devem ser array
    if ($Event.PSObject.Properties['gate_eval'] -and $null -ne $Event.gate_eval) {
        foreach ($field in @('failures','reasons','blocked_by')) {
            if (-not (Test-JsonSchemaArray -Object $Event.gate_eval -FieldName $field)) {
                [void]$violations.Add("gate_eval.${field}_is_scalar_should_be_array")
            }
        }
    }

    return [PSCustomObject]@{
        valid      = ($violations.Count -eq 0)
        violations = [string[]]@($violations)
    }
}

function Invoke-PromotionPipelineAudit {
    <#
    .SYNOPSIS
        Audita arquivo promotion_pipeline.jsonl detectando entries com schema invalido.
    .OUTPUTS
        PSCustomObject { total_lines, valid, invalid, violations_by_market }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path
    )
    $result = [PSCustomObject]@{
        total_lines = 0
        valid       = 0
        invalid     = 0
        violations_by_market = @{}
        sample_violations = New-Object System.Collections.Generic.List[object]
    }
    if (-not (Test-Path $Path)) { return $result }

    $lines = @(Get-Content $Path -Encoding UTF8 -ErrorAction SilentlyContinue)
    foreach ($line in $lines) {
        $trim = $line.Trim()
        if (-not $trim) { continue }
        $result.total_lines++
        try {
            $obj = $trim | ConvertFrom-Json -ErrorAction Stop
            $r = Test-PromotionEventSchema -Event $obj
            if ($r.valid) {
                $result.valid++
            } else {
                $result.invalid++
                $m = if ($obj.market) { [string]$obj.market } else { "?" }
                if (-not $result.violations_by_market.ContainsKey($m)) {
                    $result.violations_by_market[$m] = 0
                }
                $result.violations_by_market[$m]++
                if ($result.sample_violations.Count -lt 5) {
                    [void]$result.sample_violations.Add([PSCustomObject]@{
                        ts = $obj.ts
                        market = $m
                        violations = $r.violations
                    })
                }
            }
        } catch {
            $result.invalid++
        }
    }
    return $result
}
