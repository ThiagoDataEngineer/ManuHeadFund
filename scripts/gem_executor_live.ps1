# gem_executor_live.ps1 -- Executa descobertas com capital REAL
param([bool]$AutoExecute = $true)

$agentsDir = Join-Path $PSScriptRoot "..\agents"
. (Join-Path $agentsDir "gem_executor.ps1")

Write-Host ""
Write-Host "GEM EXECUTOR LIVE" -ForegroundColor Green
Write-Host "AutoExecute: $AutoExecute" -ForegroundColor Cyan
Write-Host ""

# Buscar gems do Supabase
$candidates = @()
try {
    $url = "$env:SUPABASE_URL/rest/v1/gems_candidates?select=*&limit=10"
    $headers = @{
        "Authorization" = "Bearer $env:SUPABASE_ANON_KEY"
        "apikey" = $env:SUPABASE_ANON_KEY
    }
    $candidates = @(Invoke-RestMethod -Uri $url -Headers $headers -ErrorAction Stop)
    Write-Host "Candidates found: $($candidates.Count)" -ForegroundColor Green
} catch {
    Write-Host "WARN: No candidates: $_" -ForegroundColor Yellow
}

$executed = 0
$blocked = 0

foreach ($gem in $candidates) {
    try {
        if ($AutoExecute) {
            $result = Invoke-GemExecute -Gem $gem
            if ($result.blocked) {
                $blocked++
            } else {
                $executed++
            }
        }
    } catch {
        Write-Host "ERROR: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Summary: Executed=$executed, Blocked=$blocked" -ForegroundColor Green
