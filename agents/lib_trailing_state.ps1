# lib_trailing_state.ps1 -- Fase 2: trailing positions via state_store (local/Supabase)
# Bridge pra "tudo online": a nuvem stateless (GitHub Actions) le/escreve as mesmas
# posicoes que o local, escolhendo backend via Test-StateBackend (flag USE_SUPABASE_STATE).
# Tabela: "trailing_positions"  PK: "market".
# 2026-06-18. ASCII-only (PS 5.1 safe). Sem Export-ModuleMember (dot-source).

# Garante que o state_store esteja carregado
if (-not (Get-Command Get-StateRecords -ErrorAction SilentlyContinue)) {
    $__ss = Join-Path $PSScriptRoot "lib_state_store.ps1"
    if (Test-Path $__ss) { . $__ss }
}

$script:TRAILING_TABLE = "trailing_positions"

function Get-TrailingPositionsState {
    [CmdletBinding()]
    param(
        [switch] $ActiveOnly
    )
    if (-not (Get-Command Get-StateRecords -ErrorAction SilentlyContinue)) { return @() }

    $rows = @(Get-StateRecords -Table $script:TRAILING_TABLE)
    if ($ActiveOnly) {
        $rows = @($rows | Where-Object { $_.active -eq $true -or "$($_.active)" -eq "True" })
    }
    # Retorno simples (sem ',@()' que cria fantasma no vazio). Callers usam @().
    return $rows
}

function Save-TrailingPositionsState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object[]] $Positions
    )
    if (-not (Get-Command Save-StateRecords -ErrorAction SilentlyContinue)) { return $false }
    if ($null -eq $Positions) { $Positions = @() }

    Save-StateRecords -Table $script:TRAILING_TABLE -Records @($Positions) -PrimaryKey "market"
    return $true
}

function Remove-TrailingPositionState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string] $Market
    )
    if (-not (Get-Command Remove-StateRecord -ErrorAction SilentlyContinue)) { return $false }
    Remove-StateRecord -Table $script:TRAILING_TABLE -PrimaryKey "market" -Value $Market
    return $true
}
