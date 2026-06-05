# lib_trailing_orphan_detection.ps1
# Auto-detecÃ§Ã£o e registro de posiÃ§Ãµes Ã³rfÃ£s (abertas na exchange mas nÃ£o registradas localmente)
# Criado: 2026-05-24 via TDD
#
# PROPÃ“SITO:
# Resolver o problema de posiÃ§Ãµes abertas manualmente ou por sistemas externos
# que nÃ£o sÃ£o gerenciadas pelo trailing stop monitor.
#
# FUNCIONALIDADES:
# - Detect-OrphanPositions: detecta posiÃ§Ãµes na exchange nÃ£o registradas localmente
# - Register-OrphanPosition: registra uma posiÃ§Ã£o Ã³rfÃ£ com stops conservadores
# - Sync-OrphanPositions: sincroniza todas as Ã³rfÃ£s em batch
#
# INTEGRAÃ‡ÃƒO:
# Dot-source: . (Join-Path $PSScriptRoot "lib_trailing_orphan_detection.ps1")
# Chamar Sync-OrphanPositions no inÃ­cio do ciclo do trailing_stop_monitor.ps1

# DependÃªncias
if (-not (Get-Command Get-TrailingPositions -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "lib_trailing.ps1")
}
if (-not (Get-Command CoinEx-GetPendingPositions -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "lib_coinex.ps1")
}

# ============================================================================
# Detect-OrphanPositions - Detecta posiÃ§Ãµes Ã³rfÃ£s
# ============================================================================

function Detect-OrphanPositions {
    <#
    .SYNOPSIS
        Detecta posiÃ§Ãµes abertas na exchange que nÃ£o estÃ£o registradas localmente
    
    .DESCRIPTION
        Compara posiÃ§Ãµes da exchange com trailing_positions.json e retorna
        as que estÃ£o na exchange mas nÃ£o registradas (Ã³rfÃ£s).
    
    .OUTPUTS
        Array de posiÃ§Ãµes Ã³rfÃ£s com flag is_orphan=$true
    
    .EXAMPLE
        $orphans = Detect-OrphanPositions
        if ($orphans.Count -gt 0) {
            Write-Host "Detectadas $($orphans.Count) posiÃ§Ãµes Ã³rfÃ£s"
        }
    #>
    [CmdletBinding()]
    param()
    
    try {
        # 1. Buscar posiÃ§Ãµes da exchange
        $exchangePositions = @(CoinEx-GetPendingPositions)
        
        if ($exchangePositions.Count -eq 0) {
            return @()
        }
        
        # 2. Buscar posiÃ§Ãµes registradas localmente (ativas)
        $localPositions = @(Get-TrailingPositions | Where-Object { $_.active })
        $localMarkets = @($localPositions | ForEach-Object { $_.market })
        
        # 3. Identificar Ã³rfÃ£s (na exchange mas nÃ£o no local)
        $orphans = @()
        foreach ($exPos in $exchangePositions) {
            $market = $exPos.market
            
            if ($localMarkets -notcontains $market) {
                # Ã“rfÃ£ detectada: adicionar flag
                $exPos | Add-Member -NotePropertyName is_orphan -NotePropertyValue $true -Force
                $orphans += $exPos
            }
        }
        
        return $orphans
    }
    catch {
        Write-Warning "Detect-OrphanPositions: erro ao detectar Ã³rfÃ£s: $_"
        return @()
    }
}

# ============================================================================
# Register-OrphanPosition - Registra uma posiÃ§Ã£o Ã³rfÃ£
# ============================================================================

function Register-OrphanPosition {
    <#
    .SYNOPSIS
        Registra uma posiÃ§Ã£o Ã³rfÃ£ no sistema local com stops conservadores
    
    .DESCRIPTION
        Extrai dados da posiÃ§Ã£o da exchange e registra via Add-TrailingPosition.
        Se a posiÃ§Ã£o nÃ£o tem stop loss configurado, calcula um conservador (5%).
    
    .PARAMETER Position
        Objeto de posiÃ§Ã£o retornado por CoinEx-GetPendingPositions
    
    .OUTPUTS
        PSCustomObject com:
        - success: $true/$false
        - registered: $true se registrou, $false se skip (duplicata)
        - stop_calculated: $true se calculou stop conservador
        - reason: motivo do skip (se aplicÃ¡vel)
        - error: mensagem de erro (se falhou)
    
    .EXAMPLE
        $orphan = Detect-OrphanPositions | Select-Object -First 1
        $result = Register-OrphanPosition -Position $orphan
        if ($result.registered) {
            Write-Host "Ã“rfÃ£ registrada: $($orphan.market)"
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Position
    )
    
    try {
        # 1. Extrair dados da posiÃ§Ã£o
        $market = $Position.market
        $side = if ($Position.side -eq "long") { "LONG" } else { "SHORT" }
        $entry = [double]$Position.avg_entry_price
        
        # ValidaÃ§Ã£o bÃ¡sica
        if (-not $market -or $entry -le 0) {
            return [PSCustomObject]@{
                success = $false
                registered = $false
                error = "Invalid position data: market='$market' entry=$entry"
            }
        }
        
        # 2. Verificar se jÃ¡ estÃ¡ registrada (prevenir duplicata)
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
            # Calcular TP razoÃ¡vel: 15% acima (LONG) ou abaixo (SHORT)
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
# Sync-OrphanPositions - SincronizaÃ§Ã£o completa em batch
# ============================================================================

function Sync-OrphanPositions {
    <#
    .SYNOPSIS
        Detecta e registra todas as posiÃ§Ãµes Ã³rfÃ£s em batch
    
    .DESCRIPTION
        FunÃ§Ã£o principal para sincronizaÃ§Ã£o automÃ¡tica. Detecta Ã³rfÃ£s e
        registra todas em batch, continuando mesmo se houver erros individuais.
    
    .OUTPUTS
        PSCustomObject com estatÃ­sticas:
        - success: $true/$false
        - total_exchange: total de posiÃ§Ãµes na exchange
        - orphans_detected: Ã³rfÃ£s detectadas
        - registered: Ã³rfÃ£s registradas com sucesso
        - skipped: Ã³rfÃ£s jÃ¡ registradas (duplicatas)
        - errors: Ã³rfÃ£s com erro ao registrar
        - details: array com resultado de cada Ã³rfÃ£
    
    .EXAMPLE
        $result = Sync-OrphanPositions
        Write-Host "Ã“rfÃ£s registradas: $($result.registered)"
        Write-Host "Erros: $($result.errors)"
    #>
    [CmdletBinding()]
    param()
    
    try {
        # 1. Detectar Ã³rfÃ£s
        $orphans = @(Detect-OrphanPositions)
        
        # 2. Buscar total de posiÃ§Ãµes na exchange
        $totalExchange = @(CoinEx-GetPendingPositions).Count
        
        # 3. Inicializar contadores
        $registered = 0
        $skipped = 0
        $errors = 0
        $details = @()
        
        # 4. Registrar cada Ã³rfÃ£
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
        
        # 5. Posicoes da exchange ja rastreadas localmente (nao-orfas) = skipped.
        #    Disjunto dos orphans, entao nao ha double-count com o loop acima.
        $skipped += ($totalExchange - $orphans.Count)

        # 6. Retornar estatÃ­sticas
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
# Detect-PhantomPositions - Detecta phantom: local active mas nao na exchange
# (oposto de orphan: posicao fechada externamente sem o sistema saber)
# Adicionado 2026-05-26 — fix dessincronizacao trailing_positions <-> CoinEx
# ============================================================================

function Detect-PhantomPositions {
    [CmdletBinding()]
    param()
    try {
        $exchangePositions = @(CoinEx-GetPendingPositions)
        $exchangeMarkets = @($exchangePositions | ForEach-Object { $_.market })

        $localActive = @(Get-TrailingPositions | Where-Object { $_.active })

        $phantoms = @()
        foreach ($pos in $localActive) {
            if ($exchangeMarkets -notcontains $pos.market) {
                $phantoms += $pos
            }
        }
        return $phantoms
    } catch {
        Write-Warning "Detect-PhantomPositions: erro: $_"
        return @()
    }
}

# ============================================================================
# Reconcile-PhantomPositions - Fecha phantoms via Close-TrailingPosition
# ============================================================================

function Reconcile-PhantomPositions {
    [CmdletBinding()]
    param(
        [string] $GemSafetyStatePath = "journal/gem_safety_state.json"
    )
    $closed = 0
    $errors = 0
    $details = @()
    try {
        $phantoms = @(Detect-PhantomPositions)
        foreach ($p in $phantoms) {
            try {
                $exitPrice = 0
                try {
                    $tick = CoinEx-GetTicker $p.market
                    if ($tick -and $tick.last) { $exitPrice = [double]$tick.last }
                } catch {}

                Close-TrailingPosition -Market $p.market -Reason "phantom_reconciliation" -ExitPrice $exitPrice

                # Sincroniza gem_safety_state: remove exposure para que gem_loop
                # nao recompre o mesmo ativo (causa raiz do loop ENA×5, 2026-06-04)
                if (Get-Command Remove-OpenGemPosition -ErrorAction SilentlyContinue) {
                    try { Remove-OpenGemPosition -Market $p.market -StateFilePath $GemSafetyStatePath } catch {}
                }

                $closed++
                $details += [PSCustomObject]@{ market = $p.market; closed = $true; exitPrice = $exitPrice }
            } catch {
                $errors++
                $details += [PSCustomObject]@{ market = $p.market; closed = $false; error = $_.Exception.Message }
            }
        }
        return [PSCustomObject]@{
            phantoms_detected = $phantoms.Count
            closed = $closed
            errors = $errors
            details = $details
        }
    } catch {
        return [PSCustomObject]@{
            phantoms_detected = 0
            closed = 0
            errors = 1
            details = @()
            error = $_.Exception.Message
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
