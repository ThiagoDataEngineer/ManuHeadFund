# repair_promotion_pipeline_schema.ps1 -- C6 J2 audit retroativo 2026-05-20 PM6+700min.
#
# Re-normaliza entries com schema invalido (failures/reasons/blocked_by como scalar string)
# em journal/promotion_pipeline.jsonl. Idempotent. Cria backup antes.
#
# Uso:
#   pwsh -File scripts\repair_promotion_pipeline_schema.ps1            # apply
#   pwsh -File scripts\repair_promotion_pipeline_schema.ps1 -DryRun    # so reporta

param([switch] $DryRun)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
. (Join-Path (Join-Path $projectRoot "agents") "lib_json_contract.ps1")
. (Join-Path (Join-Path $projectRoot "agents") "lib_schema_validators.ps1")

$path = Join-Path $projectRoot "journal\promotion_pipeline.jsonl"
if (-not (Test-Path $path)) { Write-Host "  arquivo nao existe"; exit 0 }

Write-Host "=== C6 J2 schema repair ==="
$rep = Invoke-PromotionPipelineAudit -Path $path
"  total=$($rep.total_lines) valid=$($rep.valid) invalid=$($rep.invalid)"

if ($rep.invalid -eq 0) { Write-Host "  nenhuma entry corrompida -- nada a fazer"; exit 0 }

if ($DryRun) {
    Write-Host "  [DRY] would repair $($rep.invalid) entries"
    $rep.sample_violations | ForEach-Object {
        "    ts=$($_.ts) market=$($_.market) -> $($_.violations -join ',')"
    }
    exit 0
}

# Backup
$bak = "$path.bak_schema_$(Get-Date -Format yyyyMMdd_HHmmss)"
Copy-Item $path $bak -Force
Write-Host "  backup: $bak"

# Re-write linha-por-linha; renormaliza invalid
$out = New-Object System.Collections.Generic.List[string]
$fixed = 0
foreach ($line in @(Get-Content $path -Encoding UTF8)) {
    $trim = $line.Trim()
    if (-not $trim) { $out.Add($line); continue }
    try {
        $obj = $trim | ConvertFrom-Json -ErrorAction Stop
        $r = Test-PromotionEventSchema -Event $obj
        if ($r.valid) {
            $out.Add($line)
        } else {
            # Re-normaliza com helper. Anota _schema_repaired pra audit.
            $normJson = ConvertTo-NormalizedJson -Object $obj `
                -ArrayFields $global:JSON_CONTRACT_COMMON_ARRAY_FIELDS `
                -NestedPaths $global:JSON_CONTRACT_COMMON_NESTED_PATHS
            # Append _schema_repaired marker pra rastreio
            $normObj = $normJson | ConvertFrom-Json
            $normObj | Add-Member -NotePropertyName "_schema_repaired" -NotePropertyValue (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ") -Force
            $repaired = ConvertTo-NormalizedJson -Object $normObj `
                -ArrayFields $global:JSON_CONTRACT_COMMON_ARRAY_FIELDS `
                -NestedPaths $global:JSON_CONTRACT_COMMON_NESTED_PATHS
            $out.Add($repaired)
            $fixed++
        }
    } catch {
        $out.Add($line)   # mantem linha unparseable como-eh
    }
}

# Write back (UTF-8 sem BOM mantendo formato original mais provavel + com BOM se original tinha)
[System.IO.File]::WriteAllLines($path, $out.ToArray(), [System.Text.UTF8Encoding]::new($true))

Write-Host "  repaired: $fixed entries"
$repAfter = Invoke-PromotionPipelineAudit -Path $path
"  pos-repair: total=$($repAfter.total_lines) valid=$($repAfter.valid) invalid=$($repAfter.invalid)"
if ($repAfter.invalid -ne 0) {
    Write-Host "  WARN: ainda existem $($repAfter.invalid) invalids (pode ser caso fora do contrato comum)"
}
