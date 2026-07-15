# gem_executor_live.ps1 -- Executa descobertas com capital REAL
# 2026-07-15 FIX: candidato do gems_candidates (scanner) usa shape reduzido
# {market, direction, tori_score, change_24h, volume_24h, discovered_at, status}.
# Invoke-GemExecute (agents/gem_executor.ps1) le $Gem.score/.mode/.sizing_pct/etc,
# nao .tori_score -- sem mapeamento, $Gem.score e $null e TODO candidato e
# bloqueado em "score_below_min" (PS: $null -lt 40 == $true), antes mesmo das
# gates breadth/pump/timing rodarem. Auditoria completa 2026-07-15 (agent a8499866).
param([bool]$AutoExecute = $true)

$agentsDir = Join-Path $PSScriptRoot "..\agents"
. (Join-Path $agentsDir "gem_executor.ps1")

Write-Host ""
Write-Host "GEM EXECUTOR LIVE" -ForegroundColor Green
Write-Host "AutoExecute: $AutoExecute" -ForegroundColor Cyan
Write-Host ""

# SERVICE_KEY bypassa RLS (mesmo padrao de gem_scanner_live.ps1 / lib_state_store.ps1)
$supabaseKey = if ($env:SUPABASE_SERVICE_KEY) { $env:SUPABASE_SERVICE_KEY } else { $env:SUPABASE_ANON_KEY }

# Buscar gems do Supabase (so pendentes, mais recentes primeiro)
$candidates = @()
$headers = @{
    "Authorization" = "Bearer $supabaseKey"
    "apikey" = $supabaseKey
}
try {
    $url = "$env:SUPABASE_URL/rest/v1/gems_candidates?select=*&status=eq.pending&order=discovered_at.desc&limit=10"
    $candidates = @(Invoke-RestMethod -Uri $url -Headers $headers -ErrorAction Stop)
    Write-Host "Candidates found: $($candidates.Count)" -ForegroundColor Green
} catch {
    $errMsg = $_.Exception.Message
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $errMsg = $_.ErrorDetails.Message }
    Write-Host "WARN: No candidates: $errMsg" -ForegroundColor Yellow
}

$executed = 0
$blocked = 0

foreach ($gem in $candidates) {
    try {
        # Mapeia shape reduzido do scanner -> shape esperado por Invoke-GemExecute
        $mapped = [PSCustomObject]@{
            market          = $gem.market
            direction       = $gem.direction
            score           = if ($null -ne $gem.tori_score) { [int]$gem.tori_score } else { 0 }
            mode            = "DISCOVERY"
            sizing_pct      = 0.03
            change_24h      = if ($null -ne $gem.change_24h) { [double]$gem.change_24h } else { 0 }
            vol_data        = $null
            mcap            = $null
            days_listed     = $null
            trendline_score = $null
            rsi_14          = $null
            current_price   = $null
        }

        $status = "blocked"
        if ($AutoExecute) {
            $result = Invoke-GemExecute -Gem $mapped
            if ($result.blocked) {
                $blocked++
                Write-Host "  [BLOCKED] $($gem.market) -- $($result.blocked_by -join ', ')" -ForegroundColor Yellow
            } else {
                $executed++
                $status = "executed"
                Write-Host "  [EXECUTED] $($gem.market)" -ForegroundColor Green
            }
        }

        # Marca candidato como processado (evita reprocessar no proximo ciclo)
        if ($gem.id) {
            try {
                $patchUrl = "$env:SUPABASE_URL/rest/v1/gems_candidates?id=eq.$($gem.id)"
                $patchBody = @{ status = $status } | ConvertTo-Json
                Invoke-RestMethod -Uri $patchUrl -Method PATCH -Headers ($headers + @{ "Content-Type" = "application/json" }) -Body $patchBody -ErrorAction Stop | Out-Null
            } catch {
                Write-Host "  WARN: nao marcou status de $($gem.market): $_" -ForegroundColor DarkYellow
            }
        }
    } catch {
        Write-Host "ERROR: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Summary: Executed=$executed, Blocked=$blocked" -ForegroundColor Green
