# lib_cross_platform.ps1
# Helpers para compatibilidade Windows/Linux
# Garante que scripts funcionem tanto localmente quanto no GitHub Actions

# ============================================================================
# Detectar Sistema Operacional
# ============================================================================

$script:IsLinux = $PSVersionTable.Platform -eq "Unix" -or $PSVersionTable.OS -like "*Linux*"
$script:IsWindows = -not $script:IsLinux
$script:PathSeparator = if ($script:IsLinux) { "/" } else { "\" }

# ============================================================================
# Get-ProjectRoot - Retorna raiz do projeto de forma cross-platform
# ============================================================================

function Get-ProjectRoot {
    <#
    .SYNOPSIS
        Retorna o diretório raiz do projeto de forma cross-platform
    
    .DESCRIPTION
        Procura pela pasta .git ou agents para determinar a raiz
        Funciona tanto no Windows quanto no Linux
    
    .OUTPUTS
        String - Caminho absoluto da raiz do projeto
    #>
    
    # Se estamos em agents/, subir um nível
    $current = $PSScriptRoot
    
    # Procurar por .git ou agents
    while ($current) {
        if ((Test-Path (Join-Path $current ".git")) -or 
            (Test-Path (Join-Path $current "agents"))) {
            return $current
        }
        
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) { break }  # Chegou na raiz do sistema
        $current = $parent
    }
    
    # Fallback: assumir que estamos em agents/
    return Split-Path $PSScriptRoot -Parent
}

# ============================================================================
# Import-CrossPlatformLib - Carrega biblioteca de forma cross-platform
# ============================================================================

function Import-CrossPlatformLib {
    <#
    .SYNOPSIS
        Carrega uma biblioteca do diretório agents/ de forma cross-platform
    
    .PARAMETER LibName
        Nome da biblioteca (ex: "lib_coinex.ps1")
    
    .EXAMPLE
        Import-CrossPlatformLib "lib_coinex.ps1"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$LibName
    )
    
    $projectRoot = Get-ProjectRoot
    $agentsDir = Join-Path $projectRoot "agents"
    $libPath = Join-Path $agentsDir $LibName
    
    if (-not (Test-Path $libPath)) {
        throw "Library not found: $libPath"
    }
    
    # Usar dot-sourcing no escopo do caller
    $script:__libContent = Get-Content $libPath -Raw
    Invoke-Expression $script:__libContent
}

# ============================================================================
# Get-CrossPlatformPath - Retorna caminho de diretório do projeto
# ============================================================================

function Get-CrossPlatformPath {
    <#
    .SYNOPSIS
        Retorna caminho de um diretório do projeto de forma cross-platform
    
    .PARAMETER RelativePath
        Caminho relativo à raiz do projeto (ex: "journal", "logs")
    
    .PARAMETER CreateIfNotExists
        Se true, cria o diretório se não existir
    
    .OUTPUTS
        String - Caminho absoluto cross-platform
    
    .EXAMPLE
        Get-CrossPlatformPath "journal" -CreateIfNotExists
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RelativePath,
        
        [Parameter(Mandatory=$false)]
        [switch]$CreateIfNotExists
    )
    
    $projectRoot = Get-ProjectRoot
    $fullPath = Join-Path $projectRoot $RelativePath
    
    if ($CreateIfNotExists -and -not (Test-Path $fullPath)) {
        New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
    }
    
    return $fullPath
}

# ============================================================================
# Initialize-CrossPlatformEnvironment - Setup inicial
# ============================================================================

function Initialize-CrossPlatformEnvironment {
    <#
    .SYNOPSIS
        Inicializa ambiente cross-platform
        Cria diretórios necessários e valida configuração
    
    .OUTPUTS
        Hashtable com informações do ambiente
    #>
    
    $projectRoot = Get-ProjectRoot
    
    # Criar diretórios necessários
    $dirs = @("journal", "logs", "dashboard")
    foreach ($dir in $dirs) {
        $path = Join-Path $projectRoot $dir
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
    
    # Retornar informações do ambiente
    return @{
        IsLinux = $script:IsLinux
        IsWindows = $script:IsWindows
        ProjectRoot = $projectRoot
        JournalDir = Join-Path $projectRoot "journal"
        LogsDir = Join-Path $projectRoot "logs"
        DashboardDir = Join-Path $projectRoot "dashboard"
        AgentsDir = Join-Path $projectRoot "agents"
        ScriptsDir = Join-Path $projectRoot "scripts"
    }
}

# ============================================================================
# Write-CrossPlatformLog - Log cross-platform
# ============================================================================

function Write-CrossPlatformLog {
    <#
    .SYNOPSIS
        Escreve log de forma cross-platform
    
    .PARAMETER Message
        Mensagem a ser logada
    
    .PARAMETER LogFile
        Nome do arquivo de log (ex: "trailing_stop.log")
    
    .PARAMETER Level
        Nível do log: INFO, WARN, ERROR
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$LogFile = "system.log",
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Console
    $color = switch ($Level) {
        "INFO" { "White" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
    }
    Write-Host $logMessage -ForegroundColor $color
    
    # Arquivo (se possível)
    try {
        $logsDir = Get-CrossPlatformPath "logs" -CreateIfNotExists
        $logPath = Join-Path $logsDir $LogFile
        Add-Content -Path $logPath -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        # Silenciar erros de log (não crítico)
    }
}

# ============================================================================
# Test-CrossPlatformCredentials - Valida credenciais
# ============================================================================

function Test-CrossPlatformCredentials {
    <#
    .SYNOPSIS
        Valida se credenciais estão configuradas
    
    .OUTPUTS
        Boolean - True se credenciais válidas
    #>
    
    $hasAccessId = -not [string]::IsNullOrEmpty($env:COINEX_ACCESS_ID)
    $hasSecretKey = -not [string]::IsNullOrEmpty($env:COINEX_SECRET_KEY)
    
    if (-not $hasAccessId -or -not $hasSecretKey) {
        Write-CrossPlatformLog "Credentials not configured" -Level ERROR
        Write-CrossPlatformLog "COINEX_ACCESS_ID: $hasAccessId" -Level ERROR
        Write-CrossPlatformLog "COINEX_SECRET_KEY: $hasSecretKey" -Level ERROR
        return $false
    }
    
    return $true
}

# ============================================================================
# Exportar variáveis globais
# ============================================================================

$global:CROSS_PLATFORM_IS_LINUX = $script:IsLinux
$global:CROSS_PLATFORM_IS_WINDOWS = $script:IsWindows
$global:CROSS_PLATFORM_PROJECT_ROOT = Get-ProjectRoot

Write-Verbose "Cross-platform library loaded"
Write-Verbose "  OS: $(if ($script:IsLinux) { 'Linux' } else { 'Windows' })"
Write-Verbose "  Project Root: $global:CROSS_PLATFORM_PROJECT_ROOT"
