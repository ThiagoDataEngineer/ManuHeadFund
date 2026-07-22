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

        # FIX B (2026-07-07): Confirmar que posição ainda está ABERTA na corretora
        # antes de registrar. Evita registrar "sombras" de phantom_reconciliation.
        try {
            $allPending = @(CoinEx-GetPendingPositions)
            $stillOpen = $allPending | Where-Object { $_.market -eq $market }
            if (-not $stillOpen) {
                # Posição foi fechada na corretora entretanto (SL/TP/manual)
                # Não registrar como órfã
                return [PSCustomObject]@{
                    success = $true
                    registered = $false
                    reason = "Position closed on exchange since detection"
                }
            }
        } catch {
            # API falha: proceed com caution (não bloqueia registro)
        }
        
        # 2026-07-22 FIX: Round(,4) fixo zerava stop/target calculados pra
        # tokens sub-centavo (PEPE-like), mesma causa raiz corrigida em
        # lib_position_protection.ps1 e lib_order_validation.ps1.
        $orphanRoundPrec = 4
        if (Get-Command Get-MarketPrecision -ErrorAction SilentlyContinue) {
            try {
                $orphanPrec = Get-MarketPrecision -Market $market -MarketType "futures"
                if ($orphanPrec -and $orphanPrec.quote_ccy_precision -gt 0) { $orphanRoundPrec = [int]$orphanPrec.quote_ccy_precision }
            } catch { }
        }

        # 3. Extrair ou calcular stop loss
        $stopLoss = $null
        $stopCalculated = $false

        # 2026-07-07: a API devolve stop_loss_price="0" (STRING) quando NAO ha stop —
        # e string nao-vazia e TRUTHY no PS, entao o guard antigo registrava stop=0
        # (caso WLDUSDT short sl=0). Coage p/ double e exige > 0.
        $exchSl = 0.0
        if ($Position.PSObject.Properties['stop_loss_price'] -and $Position.stop_loss_price) {
            try { $exchSl = [double]$Position.stop_loss_price } catch { $exchSl = 0.0 }
        }
        if ($exchSl -gt 0) {
            # Stop configurado na exchange
            $stopLoss = $exchSl
        }
        else {
            # Calcular stop conservador: 5% abaixo (LONG) ou acima (SHORT)
            if ($side -eq "LONG") {
                $stopLoss = [math]::Round($entry * 0.95, $orphanRoundPrec)
            }
            else {
                $stopLoss = [math]::Round($entry * 1.05, $orphanRoundPrec)
            }
            $stopCalculated = $true
        }

        # 4. Extrair ou calcular take profit
        $takeProfit = $null

        $exchTp = 0.0
        if ($Position.PSObject.Properties['take_profit_price'] -and $Position.take_profit_price) {
            try { $exchTp = [double]$Position.take_profit_price } catch { $exchTp = 0.0 }
        }
        if ($exchTp -gt 0) {
            $takeProfit = $exchTp
        }
        else {
            # Calcular TP razoÃ¡vel: 15% acima (LONG) ou abaixo (SHORT)
            if ($side -eq "LONG") {
                $takeProfit = [math]::Round($entry * 1.15, $orphanRoundPrec)
            }
            else {
                $takeProfit = [math]::Round($entry * 0.85, $orphanRoundPrec)
            }
        }

        # 5. Registrar via Add-TrailingPosition
        # 2026-07-22 FIX: origin nunca era gravado aqui -- lib_trailing_unified.ps1
        # (motor shadow) exige origin.{asset_class,trade_style} e recusa
        # "adivinhar" (fail-closed), entao toda posicao orfa registrada por
        # este caminho ficava fora da avaliacao shadow. Este caminho e
        # exclusivamente FUTURES (usa CoinEx-GetPendingPositions, endpoint
        # /v2/futures/pending-position).
        Add-TrailingPosition `
            -Market $market `
            -Side $side `
            -Entry $entry `
            -Stop $stopLoss `
            -Target $takeProfit `
            -Source "orphan_auto_register" `
            -Mode "ORPHAN_AUTO" `
            -Origin @{ asset_class = "FUTURES"; trade_style = "SWING" }
        
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

        2026-07-07 FIX A: Verifica se phantom_reconciliation rodou nos últimos 2min.
        Se sim, retorna early (evita re-entrada involuntária).

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
        Write-Host “Ã”rfÃ£s registradas: $($result.registered)”
        Write-Host “Erros: $($result.errors)”
    #>
    [CmdletBinding()]
    param()

    try {
        # FIX A (2026-07-07): Skip se phantom_reconciliation rodou nos últimos 2min
        # Evita re-entrada involuntária (phantom fecha, sync reabre)
        $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { (Join-Path (Split-Path $PSScriptRoot) “journal”) }
        $phantomFlagFile = Join-Path $journalDir “phantom_reconciliation_just_ran.flag”

        if (Test-Path $phantomFlagFile) {
            try {
                $flagTime = [datetime](Get-Content $phantomFlagFile -Raw)
                $elapsed = (Get-Date) - $flagTime
                if ($elapsed.TotalSeconds -lt 120) {
                    # Phantom rodou há menos de 2min, skip Sync
                    return [PSCustomObject]@{
                        success = $true
                        total_exchange = 0
                        orphans_detected = 0
                        registered = 0
                        skipped = 0
                        errors = 0
                        details = @()
                        skip_reason = “phantom_reconciliation_cooldown”
                    }
                }
            } catch {}
        }

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
        # FUTURES: pending positions
        $exchangePositions = @(CoinEx-GetPendingPositions | ForEach-Object { $_ })
        $exchangeMarkets = @($exchangePositions | ForEach-Object { "$($_.market)" })

        # 2026-06-11 fix: posicoes SPOT (GEMs BASED/AIN/FIRO/COAI) nunca aparecem
        # em futures pending-position — eram marcadas phantom e fechadas em todo
        # ciclo do gem_loop. Spot position existe se o saldo do asset base > 0.
        try {
            $sb = CoinEx-Get "/v2/assets/spot/balance"
            if ($sb.code -eq 0) {
                foreach ($bal in @($sb.data)) {
                    $tot = [double]$bal.available + [double]$bal.frozen
                    if ($tot -gt 0) { $exchangeMarkets += "$($bal.ccy)".ToUpper() + "USDT" }
                }
            }
        } catch {
            # Fail-closed REVERSO: se a leitura de saldos spot falhar, NAO da pra
            # afirmar que a posicao sumiu — aborta deteccao em vez de fechar tudo.
            Write-Warning "Detect-PhantomPositions: spot balance indisponivel, abortando deteccao: $_"
            return @()
        }

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

                # Anti-silencio (2026-07-07): sem exitPrice>0 o Close-TrailingPosition NAO
                # dispara Add-TradeOutcome (guard ExitPrice>0 em lib_trailing) -> o trade
                # some do journal SEM registro. Fallback pro ultimo preco conhecido da
                # posicao (peak/entry/stopCurrent) antes de desistir; se ainda 0, WARN
                # explicito em vez de fechar em silencio.
                if ($exitPrice -le 0) {
                    foreach ($fld in @('peak','entry','stopCurrent')) {
                        if ($p.PSObject.Properties[$fld] -and [double]$p.$fld -gt 0) { $exitPrice = [double]$p.$fld; break }
                    }
                    if ($exitPrice -le 0) {
                        Write-Warning "[Reconcile-Phantom] outcome skipped: no exit price for $($p.market) (ticker falhou e sem preco na posicao)"
                    }
                }

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

        # FIX A (2026-07-07): Escrever flag de cooldown pra Sync-OrphanPositions
        # Previne que sync reabre automaticamente posições que phantom acabou de fechar
        if ($closed -gt 0) {
            try {
                $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }
                $phantomFlagFile = Join-Path $journalDir "phantom_reconciliation_just_ran.flag"
                if (-not (Test-Path $journalDir)) { New-Item -ItemType Directory -Path $journalDir -Force | Out-Null }
                (Get-Date).ToString("o") | Set-Content -Path $phantomFlagFile -Encoding UTF8 -Force
            } catch {}
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
