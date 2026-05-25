# lib_trailing_orphan_detection.ps1
# Auto-detecção e registro de posições órfãs (abertas na exchange mas não registradas localmente)
# Criado: 2026-05-24 via TDD
#
# PROPÓSITO:
# Resolver o problema de posições abertas manualmente ou por sistemas externos
# que não são gerenciadas pelo trailing stop monitor.
#
# FUNCIONALIDADES:
# - Detect-OrphanPositions: detecta posições na exchange não registradas localmente
# - Register-OrphanPosition: registra uma posição órfã com stops conservadores
# - Sync-OrphanPositions: sincroniza todas as órfãs em batch
#
# INTEGRAÇÃO:
# Dot-source: . "$PSScriptRoot\lib_trailing_orphan_detection.ps1"
# Chamar Sync-OrphanPositions no início do ciclo do trailing_stop_monitor.ps1

# Dependências
if (-not (Get-Command Get-TrailingPositions -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "lib_trailing.ps1")
}
if (-not (Get-Command CoinEx-GetPendingPositions -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "lib_coinex.ps1")
}

# ============================================================================
# Detect-OrphanPositions - Detecta posições órfãs
# ============================================================================

function Detect-OrphanPositions {
    <#
    .SYNOPSIS
        Detecta posições abertas na exchange que não estão registradas localmente
    
    .DESCRIPTION
        Compara posições da exchange com trailing_positions.json e retorna
        as que estão na exchange mas não registradas (órfãs).
    
    .OUTPUTS
        Array de posições órfãs com flag is_orphan=$true
    
    .EXAMPLE
        $orphans = Detect-OrphanPositions
        if ($orphans.Count -gt 0) {
            Write-Host "Detectadas $($orphans.Count) posições órfãs"
        }
    #>
    [CmdletBinding()]
    param()
    
    try {
        # 1. Buscar posições da exchange
        $exchangePositions = @(CoinEx-GetPendingPositions)
        
        if ($exchangePositions.Count -eq 0) {
            return @()
        }
        
        # 2. Buscar posições registradas localmente (ativas)
        $localPositions = @(Get-TrailingPositions | Where-Object { $_.active })
        $localMarkets = @($localPositions | ForEach-Object { $_.market })
        
        # 3. Identificar órfãs (na exchange mas não no local)
        $orphans = @()
        foreach ($exPos in $exchangePositions) {
            $market = $exPos.market
            
            if ($localMarkets -notcontains $market) {
                # Órfã detectada: adicionar flag
                $exPos | Add-Member -NotePropertyName is_orphan -NotePropertyValue $true -Force
                $orphans += $exPos
            }
        }
        
        return $orphans
    }
    catch {
        Write-Warning "Detect-OrphanPositions: erro ao detectar órfãs: $_"
        return @()
    }
}

# ============================================================================
# Register-OrphanPosition - Registra uma posição órfã
# ============================================================================

function Register-OrphanPosition {
    <#
    .SYNOPSIS
        Registra uma posição órfã no sistema local com stops conservadores
    
    .DESCRIPTION
        Extrai dados da posição da exchange e registra via Add-TrailingPosition.
        Se a posição não tem stop loss configurado, calcula um conservador (5%).
    
    .PARAMETER Position
        Objeto de posição retornado por CoinEx-GetPendingPositions
    
    .OUTPUTS
        PSCustomObject com:
        - success: $true/$false
        - registered: $true se registrou, $false se skip (duplicata)
        - stop_calculated: $true se calculou stop conservador
        - reason: motivo do skip (se aplicável)
        - error: mensagem de erro (se falhou)
    
    .EXAMPLE
        $orphan = Detect-OrphanPositions | Select-Object -First 1
        $result = Register-OrphanPosition -Position $orphan
        if ($result.registered) {
            Write-Host "Órfã registrada: $($orphan.market)"
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Position
    )
    
    try {
        # 1. Extrair dados da posição
        $market = $Position.market
        $side = if ($Position.side -eq "long") { "LONG" } else { "SHORT" }
        $entry = [double]$Position.avg_entry_price
        
        # Validação básica
        if (-not $market -or $entry -le 0) {
            return [PSCustomObject]@{
                success = $false
                registered = $false
                error = "Invalid position data: market='$market' entry=$entry"
            }
        }
        
        # 2. Verificar se já está registrada (prevenir duplicata)
        $existing = Get-TrailingPositions | Where-Object { 
            $_.market -eq $market -and $_.active 
        }
        
        if ($existing) {
            return [PSCustomObject]@{
                success = $true
                registered = $false
                reason = "Position already registered locally"
            }
        }
        
        # 3. Extrair ou calcular stop loss
        $stopLoss = $null
        $stopCalculated = $false
        
        if ($Position.PSObject.Properties['stop_loss_price'] -and $Position.stop_loss_price) {
            # Stop configurado na exchange
            $stopLoss = [double]$Position.stop_loss_price
        }
        else {
            # Calcular stop conservador: 5% abaixo (LONG) ou acima (SHORT)
            if ($side -eq "LONG") {
                $stopLoss = [math]::Round($entry * 0.95, 4)
            }
            else {
                $stopLoss = [math]::Round($entry * 1.05, 4)
            }
            $stopCalculated = $true
        }
        
        # 4. Extrair ou calcular take profit
        $takeProfit = $null
        
        if ($Position.PSObject.Properties['take_profit_price'] -and $Position.take_profit_price) {
            $takeProfit = [double]$Position.take_profit_price
        }
        else {
            # Calcular TP razoável: 15% acima (LONG) ou abaixo (SHORT)
            if ($side -eq "LONG") {
                $takeProfit = [math]::Round($entry * 1.15, 4)
            }
            else {
                $takeProfit = [math]::Round($entry * 0.85, 4)
            }
        }
        
        # 5. Registrar via Add-TrailingPosition
        Add-TrailingPosition `
            -Market $market `
            -Side $side `
            -Entry $entry `
            -Stop $stopLoss `
            -Target $takeProfit `
            -Source "orphan_auto_register" `
            -Mode "ORPHAN_AUTO"
        
        return [PSCustomObject]@{
            success = $true
            registered = $true
            stop_calculated = $stopCalculated
            market = $market
            entry = $entry
            stop = $stopLoss
            target = $takeProfit
        }
    }
    catch {
        return [PSCustomObject]@{
            success = $false
            registered = $false
            error = $_.Exception.Message
        }
    }
}

# ============================================================================
# Sync-OrphanPositions - Sincronização completa em batch
# ============================================================================

function Sync-OrphanPositions {
    <#
    .SYNOPSIS
        Detecta e registra todas as posições órfãs em batch
    
    .DESCRIPTION
        Função principal para sincronização automática. Detecta órfãs e
        registra todas em batch, continuando mesmo se houver erros individuais.
    
    .OUTPUTS
        PSCustomObject com estatísticas:
        - success: $true/$false
        - total_exchange: total de posições na exchange
        - orphans_detected: órfãs detectadas
        - registered: órfãs registradas com sucesso
        - skipped: órfãs já registradas (duplicatas)
        - errors: órfãs com erro ao registrar
        - details: array com resultado de cada órfã
    
    .EXAMPLE
        $result = Sync-OrphanPositions
        Write-Host "Órfãs registradas: $($result.registered)"
        Write-Host "Erros: $($result.errors)"
    #>
    [CmdletBinding()]
    param()
    
    try {
        # 1. Detectar órfãs
        $orphans = @(Detect-OrphanPositions)
        
        # 2. Buscar total de posições na exchange
        $totalExchange = @(CoinEx-GetPendingPositions).Count
        
        # 3. Inicializar contadores
        $registered = 0
        $skipped = 0
        $errors = 0
        $details = @()
        
        # 4. Registrar cada órfã
        foreach ($orphan in $orphans) {
            $result = Register-OrphanPosition -Position $orphan
            $details += $result
            
            if ($result.success) {
                if ($result.registered) {
                    $registered++
                }
                else {
                    $skipped++
                }
            }
            else {
                $errors++
            }
        }
        
        # 5. Retornar estatísticas
        return [PSCustomObject]@{
            success = $true
            total_exchange = $totalExchange
            orphans_detected = $orphans.Count
            registered = $registered
            skipped = $skipped
            errors = $errors
            details = $details
        }
    }
    catch {
        return [PSCustomObject]@{
            success = $false
            error = $_.Exception.Message
            total_exchange = 0
            orphans_detected = 0
            registered = 0
            skipped = 0
            errors = 0
            details = @()
        }
    }
}

# ============================================================================
# Export functions (commented out - not needed for dot-sourced scripts)
# ============================================================================

# Export-ModuleMember -Function @(
#     'Detect-OrphanPositions',
#     'Register-OrphanPosition',
#     'Sync-OrphanPositions'
# )
