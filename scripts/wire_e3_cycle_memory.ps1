# wire_e3_cycle_memory.ps1
# E3 refinement: Cycle memory cache to skip expensive LLM reflection calls
# Call this from lib_mentor_reflection.ps1 BEFORE LLM invocation

param(
    [string] $Market,
    [string] $Regime,
    [string] $ReflectionCachePath = ".\journal\reflection_cache.jsonl"
)

. .\agents\lib_cycle_memory_decision.ps1

# Check if we can skip LLM call using cached decision
$cachedDecision = Get-CycleMemoryDecision -Path $ReflectionCachePath -Market $Market -CurrentRegime $Regime

if ($cachedDecision -and $cachedDecision.from_cache) {
    Write-Host "[E3] Using cached veto (no LLM): $Market / $Regime / reason=$($cachedDecision.reason)" -ForegroundColor Cyan
    Write-Host "     Cached at: $($cachedDecision.cached_at)" -ForegroundColor Gray
    return @{
        decision = "VETO"
        reason = $cachedDecision.reason
        from_cache = $true
        cached_at = $cachedDecision.cached_at
    }
}

# No cache hit: proceed with normal LLM reflection
Write-Host "[E3] Cache miss for $Market / $Regime — proceeding with LLM reflection" -ForegroundColor Gray
return $null
