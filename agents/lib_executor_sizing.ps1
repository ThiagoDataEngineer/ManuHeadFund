# lib_executor_sizing.ps1 -- Helper unified pra sizing executor (gem + orchestrator).
#
# Substitui o pattern direto:
#   $usd_size = $capital * $sz.sizing_pct
# Por:
#   $sz = Get-ExecutorSize -Market $mkt -Mode $mode -Capital $cap -BasePct $sz.sizing_pct
#   $usd_size = $sz.size_usd
#
# Behavior:
#   $global:USE_KELLY_SIZING = $false (default) -> legacy fixed (Capital * BasePct)
#   $global:USE_KELLY_SIZING = $true             -> Resolve-AdaptiveSizing (Kelly + cap por mode)
#
# Rollout gradual: flag stays OFF ate confirmar Kelly nao explode em paper.

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}


function Get-ExecutorSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Mode,    # GEM | TIER_A | STANDARD | BLUE_CHIP
        [Parameter(Mandatory)] [double] $Capital,
        [Parameter(Mandatory)] [double] $BasePct, # legacy sizing pct (0.01 = 1%)
        [string] $OutcomePath = (Join-Path $global:JOURNAL_DIR "trade_outcomes.jsonl")
    )
    $useKelly = ($global:USE_KELLY_SIZING -eq $true)

    if (-not $useKelly) {
        $sizeUsd = [Math]::Round($Capital * $BasePct, 2)
        return [PSCustomObject]@{
            size_usd = $sizeUsd
            method   = "legacy_fixed"
            base_pct = $BasePct
            capital  = $Capital
            mode     = $Mode
            fallback = $false
        }
    }

    # Kelly path (com fallback automatico se historico insuficiente)
    if (-not (Get-Command Resolve-AdaptiveSizing -ErrorAction SilentlyContinue)) {
        # Sem lib_kelly_wire carregada, cai pro legacy
        $sizeUsd = [Math]::Round($Capital * $BasePct, 2)
        return [PSCustomObject]@{
            size_usd = $sizeUsd
            method   = "legacy_fixed_no_kelly_lib"
            base_pct = $BasePct
            capital  = $Capital
            mode     = $Mode
            fallback = $true
        }
    }
    $kelly = Resolve-AdaptiveSizing -Market $Market -Mode $Mode -Capital $Capital -OutcomePath $OutcomePath
    Add-Member -InputObject $kelly -MemberType NoteProperty -Name method -Value "kelly_adaptive" -Force
    return $kelly
}
