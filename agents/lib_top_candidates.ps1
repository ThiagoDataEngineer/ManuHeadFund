# lib_top_candidates.ps1 -- Selecao de candidatos para o orchestrator V6.
#
# DESIGN 2026-05-29 (Item 1: top organico real):
#   Pre-fix: scan_master fazia Sort-Object | Select -First N puro. Quando a
#   whitelist forcada tinha N markets, todos os slots eram monopolizados,
#   bloqueando candidatos organicos do scanner. Caso INJUSDT (e todo Tier A)
#   aparecia em todos os ciclos com tier_level=1 + score=100.
#
#   Pos-fix: separa forcados de organicos. Forcados (apenas BTC como anchor)
#   ficam SEMPRE vivos, fora da contagem. Top-N e preenchido com candidatos
#   organicos reais por compScore desc. Resultado: BTC + top-N organicos.
#
# PS 5.1. UTF-8. Sem acentos.

function Select-TopCandidates {
    <#
    .SYNOPSIS
    Seleciona candidatos para o orchestrator: forcados (sempre vivos) + top-N organicos.

    .DESCRIPTION
    Funcao pura. Recebe lista de candidatos (cada um com market, compScore, vol,
    isWhitelistForced, tierLevel) e devolve:
      - Todos os candidatos com isWhitelistForced=true (deduplicados por market),
        ordenados por tierLevel ASC, compScore DESC.
      - Os top-N candidatos organicos (isWhitelistForced=false) por compScore DESC,
        vol DESC.

    Forcados ficam ANTES de organicos no resultado final (anchor de mercado).

    .PARAMETER Candidates
    Array de PSCustomObject. Cada um deve ter ao menos:
      - market (string)
      - compScore (numeric)
      - isWhitelistForced (bool)
    Opcionais: vol, tierLevel.

    .PARAMETER OrganicTopN
    Quantos candidatos organicos selecionar. Forcados sao adicionais.
    Use 0 para "so forcados".

    .OUTPUTS
    Array de candidatos selecionados, ja ordenado (forcados primeiro).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [PSObject[]] $Candidates,

        [int] $OrganicTopN = 20
    )

    if (-not $Candidates -or $Candidates.Count -eq 0) { return @() }

    # Separar forcados de organicos
    $forced  = @($Candidates | Where-Object { $_.isWhitelistForced -eq $true })
    $organic = @($Candidates | Where-Object { -not $_.isWhitelistForced })

    # Dedup forcados por market (caso uma entrada apareca dupla por augment)
    $forcedDedup = @{}
    $forcedFinal = @()
    foreach ($f in $forced) {
        if (-not $forcedDedup.ContainsKey($f.market)) {
            $forcedDedup[$f.market] = $true
            $forcedFinal += $f
        }
    }

    # Ordenar forcados: tierLevel ASC, compScore DESC
    $forcedSorted = @($forcedFinal | Sort-Object -Property `
        @{Expression = { if ($_.PSObject.Properties['tierLevel']) { [int]$_.tierLevel } else { 99 } }; Descending = $false }, `
        @{Expression = 'compScore'; Descending = $true })

    # Selecionar top-N organicos por compScore DESC, vol DESC (tie-break)
    $organicTop = @()
    if ($OrganicTopN -gt 0 -and $organic.Count -gt 0) {
        $organicTop = @($organic | Sort-Object -Property `
            @{Expression = 'compScore'; Descending = $true }, `
            @{Expression = 'vol'; Descending = $true } | Select-Object -First $OrganicTopN)
    }

    # Forcados primeiro, organicos depois
    return @($forcedSorted) + @($organicTop)
}
