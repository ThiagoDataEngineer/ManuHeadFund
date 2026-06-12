# refresh_regime_state.Tests.ps1 -- Pester 3.x -- TDD
#
# Testa scripts/refresh_regime_state.ps1
# Responsabilidade: ler regime_state.json (Python output) e normalizar para
# o schema PS esperado por:
#   - mesa_agent.ps1 (campo .regime string direto)
#   - lib_mentor_gate_block.ps1 (campo .regime = {phase, bias})
#   - lib_beta_cap_per_phase.ps1 (regime semantic -> phase halving)
#   - lib_quant_whitelist.ps1 Get-MarketRegimeFromCache (campo .current_regime)
#
# Schema Python (entrada):
#   { timestamp, current_regime, prev_regime, changed, trigger_actions }
#
# Schema PS normalizado (saida em regime_state.json):
#   {
#     regime        : "BEAR_WEAK"          <- campo direto para mesa_agent
#     phase         : "h24_p3_bear"        <- para lib_beta_cap_per_phase
#     bias          : "BEAR_WEAK"          <- para lib_mentor_gate_block
#     current_regime: "BEAR_WEAK"          <- backward compat Get-MarketRegimeFromCache
#     prev_regime   : "BEAR_WEAK"
#     changed       : false
#     updated_at    : "2026-05-28T13:00:00Z"
#     source        : "refresh_regime_state.ps1"
#   }

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath  = Join-Path $projectRoot "scripts\refresh_regime_state.ps1"

# Stubs
function Write-Host    { param($Object, $ForegroundColor) }
function Write-Warning { param($Message) }

# ============================================================================
# Helpers
# ============================================================================

function New-PythonRegimeJson {
    param(
        [string]$CurrentRegime = "BEAR_WEAK",
        [string]$PrevRegime    = "BEAR_WEAK",
        [bool]$Changed         = $false
    )
    return @{
        timestamp       = "2026-05-28T05:00:23.077747+00:00"
        current_regime  = $CurrentRegime
        prev_regime     = $PrevRegime
        changed         = $Changed
        trigger_actions = @()
    } | ConvertTo-Json -Compress
}

# ============================================================================
# GRUPO A -- Script existe e e executavel
# ============================================================================

Describe "A -- Script existe" {
    It "A1 scripts/refresh_regime_state.ps1 existe" {
        Test-Path $scriptPath | Should Be $true
    }
    It "A2 script tem funcao Invoke-RefreshRegimeState" {
        $src = Get-Content $scriptPath -Raw -Encoding UTF8
        ($src -match 'function Invoke-RefreshRegimeState') | Should Be $true
    }
}

# ============================================================================
# GRUPO B -- Invoke-RefreshRegimeState: logica de normalizacao
# ============================================================================

Describe "B -- Normalizacao do schema" {
    BeforeAll {
        . $scriptPath
    }

    It "B1 entrada Python valida: saida tem campo .regime string" {
        $tmpDir = [System.IO.Path]::GetTempPath()
        $inFile = Join-Path $tmpDir "regime_state_in.json"
        $outFile = Join-Path $tmpDir "regime_state_out.json"
        (New-PythonRegimeJson -CurrentRegime "BEAR_STRONG") | Set-Content $inFile -Encoding UTF8

        Invoke-RefreshRegimeState -InputPath $inFile -OutputPath $outFile

        $result = Get-Content $outFile -Raw | ConvertFrom-Json
        $result.regime | Should Be "BEAR_STRONG"
        Remove-Item $inFile, $outFile -Force -ErrorAction SilentlyContinue
    }

    It "B2 saida tem campo .current_regime (backward compat Get-MarketRegimeFromCache)" {
        $tmpDir = [System.IO.Path]::GetTempPath()
        $inFile = Join-Path $tmpDir "regime_state_in.json"
        $outFile = Join-Path $tmpDir "regime_state_out.json"
        (New-PythonRegimeJson -CurrentRegime "BULL_WEAK") | Set-Content $inFile -Encoding UTF8

        Invoke-RefreshRegimeState -InputPath $inFile -OutputPath $outFile

        $result = Get-Content $outFile -Raw | ConvertFrom-Json
        $result.current_regime | Should Be "BULL_WEAK"
        Remove-Item $inFile, $outFile -Force -ErrorAction SilentlyContinue
    }

    It "B3 saida tem campo .phase (para lib_beta_cap_per_phase)" {
        $tmpDir = [System.IO.Path]::GetTempPath()
        $inFile = Join-Path $tmpDir "regime_state_in.json"
        $outFile = Join-Path $tmpDir "regime_state_out.json"
        (New-PythonRegimeJson -CurrentRegime "BEAR_WEAK") | Set-Content $inFile -Encoding UTF8

        Invoke-RefreshRegimeState -InputPath $inFile -OutputPath $outFile

        $result = Get-Content $outFile -Raw | ConvertFrom-Json
        # phase deve ser formato halving (h24_p3_bear, h24_p1_bull, etc)
        ($result.phase -match '^h\d+_p\d+_') | Should Be $true
        Remove-Item $inFile, $outFile -Force -ErrorAction SilentlyContinue
    }

    It "B4 saida tem campo .bias igual ao regime" {
        $tmpDir = [System.IO.Path]::GetTempPath()
        $inFile = Join-Path $tmpDir "regime_state_in.json"
        $outFile = Join-Path $tmpDir "regime_state_out.json"
        (New-PythonRegimeJson -CurrentRegime "BULL_STRONG") | Set-Content $inFile -Encoding UTF8

        Invoke-RefreshRegimeState -InputPath $inFile -OutputPath $outFile

        $result = Get-Content $outFile -Raw | ConvertFrom-Json
        $result.bias | Should Be "BULL_STRONG"
        Remove-Item $inFile, $outFile -Force -ErrorAction SilentlyContinue
    }

    It "B5 saida tem campo .updated_at no formato ISO8601" {
        $tmpDir = [System.IO.Path]::GetTempPath()
        $inFile = Join-Path $tmpDir "regime_state_in.json"
        $outFile = Join-Path $tmpDir "regime_state_out.json"
        (New-PythonRegimeJson) | Set-Content $inFile -Encoding UTF8

        Invoke-RefreshRegimeState -InputPath $inFile -OutputPath $outFile

        $result = Get-Content $outFile -Raw | ConvertFrom-Json
        ($result.updated_at -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}') | Should Be $true
        Remove-Item $inFile, $outFile -Force -ErrorAction SilentlyContinue
    }

    It "B6 saida tem campo .source = refresh_regime_state.ps1" {
        $tmpDir = [System.IO.Path]::GetTempPath()
        $inFile = Join-Path $tmpDir "regime_state_in.json"
        $outFile = Join-Path $tmpDir "regime_state_out.json"
        (New-PythonRegimeJson) | Set-Content $inFile -Encoding UTF8

        Invoke-RefreshRegimeState -InputPath $inFile -OutputPath $outFile

        $result = Get-Content $outFile -Raw | ConvertFrom-Json
        $result.source | Should Be "refresh_regime_state.ps1"
        Remove-Item $inFile, $outFile -Force -ErrorAction SilentlyContinue
    }

    It "B7 saida tem campo .prev_regime preservado" {
        $tmpDir = [System.IO.Path]::GetTempPath()
        $inFile = Join-Path $tmpDir "regime_state_in.json"
        $outFile = Join-Path $tmpDir "regime_state_out.json"
        (New-PythonRegimeJson -CurrentRegime "BEAR_STRONG" -PrevRegime "BULL_WEAK" -Changed $true) | Set-Content $inFile -Encoding UTF8

        Invoke-RefreshRegimeState -InputPath $inFile -OutputPath $outFile

        $result = Get-Content $outFile -Raw | ConvertFrom-Json
        $result.prev_regime | Should Be "BULL_WEAK"
        $result.changed     | Should Be $true
        Remove-Item $inFile, $outFile -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# GRUPO C -- Robustez
# ============================================================================

Describe "C -- Robustez" {
    BeforeAll {
        . $scriptPath
    }

    It "C1 arquivo de entrada nao existe: retorna false sem crash" {
        $result = Invoke-RefreshRegimeState -InputPath "C:\nao_existe_xyz.json" -OutputPath "C:\nao_existe_out.json"
        $result | Should Be $false
    }

    It "C2 arquivo de entrada JSON invalido: retorna false sem crash" {
        $tmpDir = [System.IO.Path]::GetTempPath()
        $inFile = Join-Path $tmpDir "regime_bad.json"
        $outFile = Join-Path $tmpDir "regime_bad_out.json"
        "{ invalid json {{{{" | Set-Content $inFile -Encoding UTF8

        $result = Invoke-RefreshRegimeState -InputPath $inFile -OutputPath $outFile
        $result | Should Be $false
        Remove-Item $inFile -Force -ErrorAction SilentlyContinue
    }

    It "C3 current_regime vazio/null: usa UNKNOWN como fallback" {
        $tmpDir = [System.IO.Path]::GetTempPath()
        $inFile = Join-Path $tmpDir "regime_empty.json"
        $outFile = Join-Path $tmpDir "regime_empty_out.json"
        '{"timestamp":"2026-05-28T05:00:00Z","current_regime":"","prev_regime":"","changed":false}' | Set-Content $inFile -Encoding UTF8

        Invoke-RefreshRegimeState -InputPath $inFile -OutputPath $outFile

        $result = Get-Content $outFile -Raw | ConvertFrom-Json
        ($result.regime -ne $null) | Should Be $true
        ($result.regime.Length -gt 0) | Should Be $true
        Remove-Item $inFile, $outFile -Force -ErrorAction SilentlyContinue
    }

    It "C4 InputPath = OutputPath (in-place update): funciona sem corromper" {
        $tmpDir = [System.IO.Path]::GetTempPath()
        $file = Join-Path $tmpDir "regime_inplace.json"
        (New-PythonRegimeJson -CurrentRegime "BEAR_WEAK") | Set-Content $file -Encoding UTF8

        Invoke-RefreshRegimeState -InputPath $file -OutputPath $file

        $result = Get-Content $file -Raw | ConvertFrom-Json
        $result.regime | Should Be "BEAR_WEAK"
        Remove-Item $file -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# GRUPO D -- Integracao com regime_state.json real
# ============================================================================

Describe "D -- Integracao com arquivo real" {
    BeforeAll {
        . $scriptPath
    }

    It "D1 regime_state.json real existe e tem current_regime preenchido" {
        $realPath = Join-Path $projectRoot "journal\regime_state.json"
        Test-Path $realPath | Should Be $true
        $data = Get-Content $realPath -Raw | ConvertFrom-Json
        ($data.current_regime -ne $null -and $data.current_regime -ne "") | Should Be $true
    }

    It "D2 apos refresh in-place: regime_state.json tem campo .regime preenchido" {
        $realPath = Join-Path $projectRoot "journal\regime_state.json"
        if (-not (Test-Path $realPath)) {
            Set-TestInconclusive "regime_state.json nao existe"
            return
        }

        Invoke-RefreshRegimeState -InputPath $realPath -OutputPath $realPath

        $result = Get-Content $realPath -Raw | ConvertFrom-Json
        ($result.regime -ne $null -and $result.regime -ne "") | Should Be $true
        ($result.phase  -ne $null -and $result.phase  -ne "") | Should Be $true
        $result.source | Should Be "refresh_regime_state.ps1"
    }
}
