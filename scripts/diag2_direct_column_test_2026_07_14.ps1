# diag2_direct_column_test_2026_07_14.ps1 -- testa a coluna via a MESMA rota
# que o runtime usa (POST direto na tabela com Content-Profile: manuheadfund),
# nao via exec_sql. Isola se o problema e cache RPC-specific vs a tabela em si.

param(
    [Parameter(Mandatory=$false)][string]$SupabaseUrl = $env:SUPABASE_URL,
    [Parameter(Mandatory=$false)][string]$ServiceKey = $env:SUPABASE_SERVICE_KEY
)

if (-not $SupabaseUrl) { throw "SUPABASE_URL not set" }
if (-not $ServiceKey) { throw "SUPABASE_SERVICE_KEY not set" }

$baseHeaders = @{
    "apikey"        = $ServiceKey
    "Authorization" = "Bearer $ServiceKey"
    "Content-Type"  = "application/json"
}

# 1. Tenta um PATCH real na trailing_state com closeReason, exatamente como
#    Close-TrailingPosition/Save-StateRecords fariam.
Write-Host "Test 1: POST direto em manuheadfund.trailing_state com closeReason" -ForegroundColor Cyan
$h1 = $baseHeaders.Clone()
$h1["Content-Profile"] = "manuheadfund"
$h1["Prefer"] = "return=minimal"
$testRow = @{ pk_id = "DIAG_TEST_$(Get-Date -Format 'yyyyMMddHHmmss')"; market = "DIAGTEST"; side = "LONG"; entry = 1; stop = 1; target = 1; active = $false; closeReason = "diag_test" }
$body1 = @($testRow) | ConvertTo-Json
try {
    Invoke-RestMethod -Uri "$SupabaseUrl/rest/v1/trailing_state" -Headers $h1 -Method Post -Body $body1 -ErrorAction Stop | Out-Null
    Write-Host "  RESULT: SUCCESS -- closeReason accepted by direct table POST" -ForegroundColor Green
} catch {
    $respBody = $null
    try { $respBody = $_.ErrorDetails.Message } catch {}
    Write-Host "  RESULT: FAILED -- $($_.Exception.Message)" -ForegroundColor Red
    if ($respBody) { Write-Host "  Body: $respBody" -ForegroundColor Red }
}

# 2. Confirma via GET com Accept-Profile que a coluna aparece no retorno
Write-Host "`nTest 2: GET direto, confirma coluna no schema exposto via API" -ForegroundColor Cyan
$h2 = $baseHeaders.Clone()
$h2["Accept-Profile"] = "manuheadfund"
try {
    $r = Invoke-RestMethod -Uri "$SupabaseUrl/rest/v1/trailing_state?market=eq.DIAGTEST&select=*" -Headers $h2 -Method Get -ErrorAction Stop
    if ($r -and @($r).Count -gt 0) {
        $cols = $r[0].PSObject.Properties.Name -join ", "
        Write-Host "  RESULT: row found, columns: $cols" -ForegroundColor Green
        Write-Host "  has closeReason property: $($r[0].PSObject.Properties.Name -contains 'closeReason')" -ForegroundColor $(if ($r[0].PSObject.Properties.Name -contains 'closeReason') {'Green'} else {'Red'})
    } else {
        Write-Host "  RESULT: no rows returned (insert may have failed)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  RESULT: FAILED -- $($_.Exception.Message)" -ForegroundColor Red
}

# 3. Cleanup do row de teste
Write-Host "`nCleanup: removendo row de teste" -ForegroundColor Cyan
$h3 = $baseHeaders.Clone()
$h3["Content-Profile"] = "manuheadfund"
try {
    Invoke-RestMethod -Uri "$SupabaseUrl/rest/v1/trailing_state?market=eq.DIAGTEST" -Headers $h3 -Method Delete -ErrorAction Stop | Out-Null
    Write-Host "  cleanup OK" -ForegroundColor Green
} catch {
    Write-Host "  cleanup failed (nao critico): $($_.Exception.Message)" -ForegroundColor Yellow
}

# 4. OpenAPI root -- lista colunas que o PostgREST acha que a tabela tem AGORA
Write-Host "`nTest 4: OpenAPI schema description (o que o PostgREST acha que trailing_state tem)" -ForegroundColor Cyan
$h4 = $baseHeaders.Clone()
$h4["Accept-Profile"] = "manuheadfund"
try {
    $openapi = Invoke-RestMethod -Uri "$SupabaseUrl/rest/v1/" -Headers $h4 -Method Get -ErrorAction Stop
    if ($openapi.definitions -and $openapi.definitions.trailing_state) {
        $props = $openapi.definitions.trailing_state.properties.PSObject.Properties.Name -join ", "
        Write-Host "  trailing_state properties per OpenAPI: $props" -ForegroundColor White
        Write-Host "  has closeReason: $($props -match 'closeReason')" -ForegroundColor $(if ($props -match 'closeReason') {'Green'} else {'Red'})
    } else {
        Write-Host "  trailing_state not found in OpenAPI definitions (or different shape)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  OpenAPI fetch failed: $($_.Exception.Message)" -ForegroundColor Yellow
}
