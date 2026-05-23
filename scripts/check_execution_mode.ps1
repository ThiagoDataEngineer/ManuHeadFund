# check_execution_mode.ps1 - Detecta se está rodando local ou GitHub Actions
# Evita conflitos de execução simultânea

function Get-ExecutionMode {
    <#
    .SYNOPSIS
        Detecta onde o script está rodando
    
    .OUTPUTS
        "local" ou "github-actions"
    #>
    
    # GitHub Actions define variáveis de ambiente específicas
    if ($env:GITHUB_ACTIONS -eq "true") {
        return "github-actions"
    }
    
    return "local"
}

function Test-ShouldExecute {
    <#
    .SYNOPSIS
        Verifica se deve executar baseado no modo
    
    .PARAMETER PreferredMode
        "local", "github-actions", ou "both"
    
    .OUTPUTS
        $true se deve executar, $false caso contrário
    #>
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet("local", "github-actions", "both")]
        [string]$PreferredMode = "both"
    )
    
    $currentMode = Get-ExecutionMode
    
    if ($PreferredMode -eq "both") {
        return $true
    }
    
    return ($currentMode -eq $PreferredMode)
}

function Get-LockFile {
    <#
    .SYNOPSIS
        Retorna caminho do arquivo de lock
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$JobName
    )
    
    $lockDir = Join-Path $PSScriptRoot "..\locks"
    if (-not (Test-Path $lockDir)) {
        New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
    }
    
    return Join-Path $lockDir "$JobName.lock"
}

function Test-JobRunning {
    <#
    .SYNOPSIS
        Verifica se job já está rodando (evita duplicação)
    
    .PARAMETER JobName
        Nome do job (ex: "risk-manager", "dashboard")
    
    .PARAMETER MaxAge
        Idade máxima do lock em segundos (default: 300 = 5min)
    
    .OUTPUTS
        $true se job está rodando, $false caso contrário
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$JobName,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxAge = 300
    )
    
    $lockFile = Get-LockFile -JobName $JobName
    
    if (-not (Test-Path $lockFile)) {
        return $false
    }
    
    # Verificar idade do lock
    $lockInfo = Get-Content $lockFile -Raw | ConvertFrom-Json
    $lockTime = [DateTime]::Parse($lockInfo.timestamp)
    $age = (Get-Date) - $lockTime
    
    if ($age.TotalSeconds -gt $MaxAge) {
        # Lock expirado, remover
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        return $false
    }
    
    return $true
}

function Set-JobLock {
    <#
    .SYNOPSIS
        Cria lock para job
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$JobName
    )
    
    $lockFile = Get-LockFile -JobName $JobName
    $mode = Get-ExecutionMode
    
    $lockInfo = @{
        job = $JobName
        mode = $mode
        timestamp = (Get-Date).ToString("o")
        pid = $PID
        machine = $env:COMPUTERNAME
    }
    
    $lockInfo | ConvertTo-Json | Out-File $lockFile -Force
}

function Remove-JobLock {
    <#
    .SYNOPSIS
        Remove lock do job
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$JobName
    )
    
    $lockFile = Get-LockFile -JobName $JobName
    
    if (Test-Path $lockFile) {
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-SafeJob {
    <#
    .SYNOPSIS
        Executa job com proteção contra duplicação
    
    .PARAMETER JobName
        Nome do job
    
    .PARAMETER ScriptBlock
        Código a executar
    
    .PARAMETER PreferredMode
        Modo preferido: "local", "github-actions", ou "both"
    
    .EXAMPLE
        Invoke-SafeJob -JobName "risk-manager" -ScriptBlock {
            Write-Host "Executando Risk Manager"
        }
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$JobName,
        
        [Parameter(Mandatory=$true)]
        [ScriptBlock]$ScriptBlock,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("local", "github-actions", "both")]
        [string]$PreferredMode = "both"
    )
    
    $mode = Get-ExecutionMode
    
    # Verificar se deve executar neste modo
    if (-not (Test-ShouldExecute -PreferredMode $PreferredMode)) {
        Write-Host "[$mode] Job '$JobName' configurado para rodar apenas em '$PreferredMode', pulando..." -ForegroundColor Yellow
        return
    }
    
    # Verificar se já está rodando
    if (Test-JobRunning -JobName $JobName) {
        Write-Host "[$mode] Job '$JobName' já está rodando, pulando..." -ForegroundColor Yellow
        return
    }
    
    try {
        # Criar lock
        Set-JobLock -JobName $JobName
        Write-Host "[$mode] Iniciando job '$JobName'..." -ForegroundColor Cyan
        
        # Executar job
        & $ScriptBlock
        
        Write-Host "[$mode] Job '$JobName' concluído com sucesso" -ForegroundColor Green
    }
    catch {
        Write-Host "[$mode] Erro no job '$JobName': $_" -ForegroundColor Red
        throw
    }
    finally {
        # Remover lock
        Remove-JobLock -JobName $JobName
    }
}

# Funções disponíveis (não precisa Export-ModuleMember quando não é módulo)
# Get-ExecutionMode
# Test-ShouldExecute
# Test-JobRunning
# Set-JobLock
# Remove-JobLock
# Invoke-SafeJob
