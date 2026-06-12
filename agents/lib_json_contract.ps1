# lib_json_contract.ps1 -- C6 fix 2026-05-20 PM6+620min.
#
# Contrato de normalizacao JSON pra PowerShell 5.1.
#
# Bug raiz: PS 5.1 unwrap single-element arrays implicitamente em:
#   1. Property assignment: $x = $obj.failures (1 elem) -> $x vira String
#   2. ConvertTo-Json -Compress sem -AsArray (que nao existe em 5.1)
#
# Consequencia em prod: HYPE pipeline persistiu 12 entries com failures="sharpe..."
# (string scalar) ao inves de failures=["sharpe..."]. Replay analyzer e daily digest
# parseiam char-by-char.
#
# Solucao em 3 funcoes:
#   ConvertTo-NormalizedJson — write-side: forca @() wrap em ArrayFields conhecidos
#   Get-NormalizedJsonArray  — read-side: garante valor eh array (re-wrap scalar)
#   Test-JsonSchemaArray     — predicate: field eh array valido?
#
# PS 5.1, UTF-8 BOM.

function Get-NormalizedJsonArray {
    <#
    .SYNOPSIS
        Garante que valor eh array (re-wrap scalar/null em array).
    .DESCRIPTION
        Usar em read-side quando ler JSON que pode ter field scalar incorretamente.
    .EXAMPLE
        $failures = Get-NormalizedJsonArray $obj.failures
        # Se $obj.failures eh "string" -> retorna @("string")
        # Se $obj.failures eh @("a","b") -> retorna @("a","b")
        # Se $obj.failures eh $null -> retorna @()
    #>
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline)] $Value)
    if ($null -eq $Value) { return ,@() }
    if ($Value -is [array]) { return ,$Value }
    return ,@($Value)
}

function Test-JsonSchemaArray {
    <#
    .SYNOPSIS
        True se $Object.$FieldName eh array OU ausente OU null.
        False se eh scalar (bug pattern HYPE).
    .NOTES
        IMPORTANTE: Em PSCustomObject, acesso via $obj.Field UNWRAP single-element
        arrays (PS 5.1 quirk). Usamos PSObject.Properties[name].Value pra preservar
        tipo original SEM unwrap.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)] [string] $FieldName
    )
    if ($null -eq $Object) { return $true }
    $val = $null
    $hasField = $false
    if ($Object -is [hashtable] -or $Object -is [System.Collections.Specialized.OrderedDictionary]) {
        $hasField = $Object.Contains($FieldName)
        if ($hasField) { $val = $Object[$FieldName] }
    } else {
        $prop = $Object.PSObject.Properties[$FieldName]
        if ($null -ne $prop) {
            $hasField = $true
            $val = $prop.Value   # PSObject.Properties[].Value NAO unwrap
        }
    }
    if (-not $hasField) { return $true }
    if ($null -eq $val) { return $true }
    return ($val -is [array])
}

function _Normalize-Object {
    # Recursivamente normaliza array fields em $Obj. Mutates copy.
    param(
        $Obj,
        [string[]] $ArrayFields,
        [string[]] $NestedPaths = @()
    )
    if ($null -eq $Obj) { return $null }
    # Hashtable / OrderedDictionary
    if ($Obj -is [hashtable] -or $Obj -is [System.Collections.Specialized.OrderedDictionary]) {
        $out = [ordered]@{}
        foreach ($k in $Obj.Keys) {
            $v = $Obj[$k]
            if ($k -in $ArrayFields) {
                # Force array wrap
                if ($null -eq $v) { $out[$k] = @() }
                elseif ($v -is [array]) { $out[$k] = $v }
                else { $out[$k] = @($v) }
            } elseif ($k -in $NestedPaths) {
                # Recurse em nested
                $out[$k] = _Normalize-Object -Obj $v -ArrayFields $ArrayFields -NestedPaths $NestedPaths
            } else {
                $out[$k] = $v
            }
        }
        return $out
    }
    # PSCustomObject
    if ($Obj -is [PSCustomObject]) {
        $out = [ordered]@{}
        foreach ($p in $Obj.PSObject.Properties) {
            $k = $p.Name; $v = $p.Value
            if ($k -in $ArrayFields) {
                if ($null -eq $v) { $out[$k] = @() }
                elseif ($v -is [array]) { $out[$k] = $v }
                else { $out[$k] = @($v) }
            } elseif ($k -in $NestedPaths) {
                $out[$k] = _Normalize-Object -Obj $v -ArrayFields $ArrayFields -NestedPaths $NestedPaths
            } else {
                $out[$k] = $v
            }
        }
        return $out
    }
    # Scalar/array: passthrough
    return $Obj
}

function ConvertTo-NormalizedJson {
    <#
    .SYNOPSIS
        Wrapper de ConvertTo-Json que forca @() wrap em ArrayFields conhecidos.
        Resolve bug PS 5.1 single-element unwrap pre-serializacao.
    .PARAMETER Object
        Hashtable / PSCustomObject pra serializar.
    .PARAMETER ArrayFields
        Lista de nomes de fields que devem SEMPRE ser array no JSON output.
    .PARAMETER NestedPaths
        Lista de nomes de fields que sao nested objects (recurse normalizacao).
    .PARAMETER Compress
        Default true (compatibilidade com Add-Content append-only JSONL).
    .PARAMETER Depth
        Default 5.
    .EXAMPLE
        ConvertTo-NormalizedJson -Object $event -ArrayFields @("failures","reasons","blocked_by") -NestedPaths @("gate_eval","metrics")
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Object,
        [string[]] $ArrayFields = @(),
        [string[]] $NestedPaths = @(),
        [switch] $NoCompress,
        [int] $Depth = 5
    )
    $norm = _Normalize-Object -Obj $Object -ArrayFields $ArrayFields -NestedPaths $NestedPaths
    if ($NoCompress) {
        return ($norm | ConvertTo-Json -Depth $Depth)
    }
    return ($norm | ConvertTo-Json -Compress -Depth $Depth)
}

# Common array fields nos schemas do projeto (lookup table — atualize ao adicionar novos)
$global:JSON_CONTRACT_COMMON_ARRAY_FIELDS = @(
    "failures",     # gate_eval.failures
    "reasons",      # gate_eval.reasons / fqs.reasons / live_guards.reasons
    "blocked_by",   # gem_auto_approve.blocked_by / all_gates.blocked_by
    "markets",      # news article markets
    "errors",       # http_error_monitor.errors
    "confluencias", # mesa drones consensus
    "tags",         # knowledge_retriever
    "drones",       # mesa response
    "covered_refs", # runspace_audit
    "missing_libs", # runspace_audit
    "orphan_refs"   # runspace_audit
)
$global:JSON_CONTRACT_COMMON_NESTED_PATHS = @(
    "gate_eval",    # promotion_pipeline event
    "metrics",      # promotion_pipeline event
    "mesa"          # mentor context
)
