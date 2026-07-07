# trailing_stop_monitor_orphan_detection.Tests.ps1
# TDD para detecção e auto-registro de posições órfãs
# Criado: 2026-05-24
#
# REQUISITO:
# O trailing stop monitor deve detectar posições abertas na exchange que não
# estão registradas localmente (órfãs) e auto-registrá-las para proteção.
#
# CENÁRIOS:
# 1. Posição na exchange + não registrada localmente = AUTO-REGISTRO
# 2. Posição na exchange + já registrada localmente = SKIP (sem duplicata)
# 3. Posição órfã SEM stop loss configurado = AUTO-REGISTRO com stop conservador
# 4. Posição órfã COM stop loss configurado = AUTO-REGISTRO com stop da exchange
# 5. Múltiplas posições órfãs = AUTO-REGISTRO de todas
# 6. Erro ao registrar órfã = LOG erro mas continua processamento

$ErrorActionPreference = "Stop"

# Setup: criar ambiente isolado
$tmpDir = Join-Path $env:TEMP "trailing_orphan_tests_$(Get-Random)"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

# Mock trailing_positions.json path
$global:TRAILING_FILE_BACKUP = $TRAILING_FILE
$global:TRAILING_FILE = "$tmpDir\trailing_positions.json"

# Carregar libs (com path mockado)
. "$PSScriptRoot\..\agents\config.ps1"
. "$PSScriptRoot\..\agents\lib_coinex.ps1"
. "$PSScriptRoot\..\agents\lib_trailing.ps1"
. "$PSScriptRoot\..\agents\lib_trailing_orphan_detection.ps1"

# Mock CoinEx-GetPendingPositions para testes
function Mock-CoinExPositions {
    param([array]$Positions)
    
    $global:__orphan_mock_positions = $Positions

    # Set-Item no script scope (1 level up de Mock-CoinExPositions) onde lib_coinex
    # foi dot-sourced. Scope 1 = caller (script scope do arquivo de teste).
    Set-Item -Path "function:CoinEx-GetPendingPositions" -Value ([scriptblock]::Create('return $global:__orphan_mock_positions')) -Force
    # Tambem replica no global para cobertura de ambos lookups
    Set-Item -Path "function:global:CoinEx-GetPendingPositions" -Value ([scriptblock]::Create('return $global:__orphan_mock_positions')) -Force
}

# Helper: criar posição mock
function New-MockPosition {
    param(
        [string]$Market,
        [string]$Side = "long",
        [double]$Entry = 100.0,
        [double]$Amount = 10.0,
        [double]$StopLoss = 0,
        [double]$TakeProfit = 0
    )
    
    $pos = [PSCustomObject]@{
        market = $Market
        side = $Side
        avg_entry_price = $Entry
        amount = $Amount
        unrealized_pnl = 0
    }
    
    if ($StopLoss -gt 0) {
        $pos | Add-Member -NotePropertyName stop_loss_price -NotePropertyValue $StopLoss
    }
    if ($TakeProfit -gt 0) {
        $pos | Add-Member -NotePropertyName take_profit_price -NotePropertyValue $TakeProfit
    }
    
    return $pos
}

# ============================================================================
# FASE RED: Testes escritos ANTES da implementação
# ============================================================================

Describe "Detect-OrphanPositions - Detecção de posições órfãs" {
    
    BeforeEach {
        # Desabilita state_store (forca legacy file path) + limpa arquivo
        $global:TRAILING_USE_STATE_STORE = $false
        $env:TRAILING_USE_STATE_STORE = "0"
        if (Test-Path $global:TRAILING_FILE) {
            Remove-Item $global:TRAILING_FILE -Force
        }
        "[]" | Set-Content $global:TRAILING_FILE -Encoding utf8
    }

    It "Detecta posição órfã (na exchange mas não registrada localmente)" {
        # Arrange: posição na exchange
        $exchangePos = New-MockPosition -Market "BTCUSDT" -Side "long" -Entry 76000
        Mock-CoinExPositions -Positions @($exchangePos)
        
        # Act: detectar órfãs (wrap @() = mesmo padrao que Sync-OrphanPositions usa em producao)
        $orphans = @(Detect-OrphanPositions)

        # Assert
        $orphans.Count | Should Be 1
        $orphans[0].market | Should Be "BTCUSDT"
        $orphans[0].is_orphan | Should Be $true
    }
    
    It "NÃO detecta posição já registrada localmente" {
        # Arrange: posição na exchange E registrada localmente
        $exchangePos = New-MockPosition -Market "ETHUSDT" -Side "long" -Entry 2100
        Mock-CoinExPositions -Positions @($exchangePos)
        
        # Registrar localmente
        Add-TrailingPosition -Market "ETHUSDT" -Side "LONG" -Entry 2100 -Stop 2000 -Target 2300
        
        # Act: detectar órfãs
        $orphans = Detect-OrphanPositions
        
        # Assert: nenhuma órfã
        $orphans.Count | Should Be 0
    }
    
    It "Detecta múltiplas posições órfãs simultaneamente" {
        # Arrange: 3 posições na exchange, 1 registrada
        $pos1 = New-MockPosition -Market "BTCUSDT" -Side "long" -Entry 76000
        $pos2 = New-MockPosition -Market "ETHUSDT" -Side "long" -Entry 2100
        $pos3 = New-MockPosition -Market "SOLUSDT" -Side "long" -Entry 85
        Mock-CoinExPositions -Positions @($pos1, $pos2, $pos3)
        
        # Registrar apenas ETHUSDT
        Add-TrailingPosition -Market "ETHUSDT" -Side "LONG" -Entry 2100 -Stop 2000 -Target 2300
        
        # Act
        $orphans = Detect-OrphanPositions
        
        # Assert: 2 órfãs (BTC e SOL)
        $orphans.Count | Should Be 2
        ($orphans | Where-Object { $_.market -eq "BTCUSDT" }) | Should Not Be $null
        ($orphans | Where-Object { $_.market -eq "SOLUSDT" }) | Should Not Be $null
    }
    
    It "Retorna array vazio quando não há posições na exchange" {
        # Arrange: nenhuma posição
        Mock-CoinExPositions -Positions @()
        
        # Act
        $orphans = Detect-OrphanPositions
        
        # Assert
        $orphans.Count | Should Be 0
    }
    
    It "Retorna array vazio quando todas as posições estão registradas" {
        # Arrange: 2 posições na exchange, ambas registradas
        $pos1 = New-MockPosition -Market "BTCUSDT" -Side "long" -Entry 76000
        $pos2 = New-MockPosition -Market "ETHUSDT" -Side "long" -Entry 2100
        Mock-CoinExPositions -Positions @($pos1, $pos2)
        
        Add-TrailingPosition -Market "BTCUSDT" -Side "LONG" -Entry 76000 -Stop 72000 -Target 80000
        Add-TrailingPosition -Market "ETHUSDT" -Side "LONG" -Entry 2100 -Stop 2000 -Target 2300
        
        # Act
        $orphans = Detect-OrphanPositions
        
        # Assert
        $orphans.Count | Should Be 0
    }
}

Describe "Register-OrphanPosition - Auto-registro de posições órfãs" {
    
    BeforeEach {
        if (Test-Path $global:TRAILING_FILE) {
            Remove-Item $global:TRAILING_FILE -Force
        }
    }
    
    It "Registra posição órfã COM stop loss configurado na exchange" {
        # Arrange: posição com SL
        $orphan = New-MockPosition -Market "BTCUSDT" -Side "long" -Entry 76000 -StopLoss 72000 -TakeProfit 80000
        
        # Act
        $result = Register-OrphanPosition -Position $orphan
        
        # Assert
        $result.success | Should Be $true
        $result.registered | Should Be $true
        
        # Verificar registro local
        $local = Get-TrailingPositions | Where-Object { $_.market -eq "BTCUSDT" -and $_.active }
        $local | Should Not Be $null
        $local.entry | Should Be 76000
        $local.stopCurrent | Should Be 72000
        $local.target | Should Be 80000
        $local.source | Should Be "orphan_auto_register"
    }
    
    It "Registra posição órfã SEM stop loss usando stop conservador (5%)" {
        # Arrange: posição SEM SL
        $orphan = New-MockPosition -Market "ETHUSDT" -Side "long" -Entry 2000
        
        # Act
        $result = Register-OrphanPosition -Position $orphan
        
        # Assert
        $result.success | Should Be $true
        $result.stop_calculated | Should Be $true
        
        # Verificar stop conservador: 2000 * 0.95 = 1900
        $local = Get-TrailingPositions | Where-Object { $_.market -eq "ETHUSDT" -and $_.active }
        $local.stopCurrent | Should Be 1900
        $local.target | Should Be 2300  # 2000 * 1.15
    }
    
    It "Registra posição SHORT órfã com stop conservador invertido" {
        # Arrange: SHORT sem SL
        $orphan = New-MockPosition -Market "BTCUSDT" -Side "short" -Entry 76000
        
        # Act
        $result = Register-OrphanPosition -Position $orphan
        
        # Assert
        $result.success | Should Be $true
        
        # SHORT: stop ACIMA da entrada (76000 * 1.05 = 79800)
        $local = Get-TrailingPositions | Where-Object { $_.market -eq "BTCUSDT" -and $_.active }
        $local.stopCurrent | Should Be 79800
        $local.target | Should Be 64600  # 76000 * 0.85
        $local.side | Should Be "SHORT"
    }
    
    It "SHORT com stop_loss_price STRING '0' (API real) calcula stop protetivo, nao registra 0" {
        # Regressao WLDUSDT (2026-07-07): a API devolve stop_loss_price="0" (string
        # truthy no PS) -> o guard antigo registrava stop=0, deixando um SHORT
        # alavancado SEM protecao. Deve cair no calculo direcional (entry*1.05).
        $orphan = [PSCustomObject]@{
            market          = "WLDUSDT"
            side            = "short"
            avg_entry_price = 0.389701
            amount          = 100
            stop_loss_price = "0"   # STRING, como a API devolve
            take_profit_price = "0"
        }

        $result = Register-OrphanPosition -Position $orphan

        $result.success | Should Be $true
        $result.stop_calculated | Should Be $true
        $local = Get-TrailingPositions | Where-Object { $_.market -eq "WLDUSDT" -and $_.active }
        # SHORT sem stop -> stop ACIMA da entrada (0.389701 * 1.05).
        ($local.stopCurrent -gt $local.entry) | Should Be $true
        ($local.stopCurrent -gt 0) | Should Be $true
    }

    It "NÃO registra duplicata se posição já existe localmente" {
        # Arrange: registrar primeiro
        Add-TrailingPosition -Market "BTCUSDT" -Side "LONG" -Entry 76000 -Stop 72000 -Target 80000
        
        $orphan = New-MockPosition -Market "BTCUSDT" -Side "long" -Entry 76000
        
        # Act
        $result = Register-OrphanPosition -Position $orphan
        
        # Assert: skip duplicata
        $result.success | Should Be $true
        $result.registered | Should Be $false
        $result.reason | Should Match "already registered"
        
        # Verificar que há apenas 1 registro
        $all = Get-TrailingPositions | Where-Object { $_.market -eq "BTCUSDT" -and $_.active }
        @($all).Count | Should Be 1
    }
    
    It "Registra com mode=ORPHAN_AUTO para rastreabilidade" {
        # Arrange
        $orphan = New-MockPosition -Market "SOLUSDT" -Side "long" -Entry 85
        
        # Act
        Register-OrphanPosition -Position $orphan
        
        # Assert: mode específico para órfãs
        $local = Get-TrailingPositions | Where-Object { $_.market -eq "SOLUSDT" -and $_.active }
        $local.mode | Should Be "ORPHAN_AUTO"
        $local.source | Should Be "orphan_auto_register"
    }
    
    It "Retorna erro mas não falha quando registro falha" {
        # Arrange: forçar erro (market inválido)
        $orphan = [PSCustomObject]@{
            market = ""  # inválido
            side = "long"
            avg_entry_price = 100
            amount = 10
        }
        
        # Act
        $result = Register-OrphanPosition -Position $orphan -ErrorAction SilentlyContinue
        
        # Assert: erro capturado mas não throw
        $result.success | Should Be $false
        $result.error | Should Not Be $null
    }
}

Describe "Sync-OrphanPositions - Sincronização completa" {
    
    BeforeEach {
        if (Test-Path $global:TRAILING_FILE) {
            Remove-Item $global:TRAILING_FILE -Force
        }
    }
    
    It "Sincroniza todas as posições órfãs em batch" {
        # Arrange: 3 órfãs
        $pos1 = New-MockPosition -Market "BTCUSDT" -Side "long" -Entry 76000 -StopLoss 72000
        $pos2 = New-MockPosition -Market "ETHUSDT" -Side "long" -Entry 2100
        $pos3 = New-MockPosition -Market "SOLUSDT" -Side "short" -Entry 85
        Mock-CoinExPositions -Positions @($pos1, $pos2, $pos3)
        
        # Act
        $result = Sync-OrphanPositions
        
        # Assert
        $result.success | Should Be $true
        $result.total_exchange | Should Be 3
        $result.orphans_detected | Should Be 3
        $result.registered | Should Be 3
        $result.skipped | Should Be 0
        $result.errors | Should Be 0
        
        # Verificar registros locais
        $local = Get-TrailingPositions | Where-Object { $_.active }
        $local.Count | Should Be 3
    }
    
    It "Sincroniza apenas órfãs, skip posições já registradas" {
        # Arrange: 3 na exchange, 1 já registrada
        $pos1 = New-MockPosition -Market "BTCUSDT" -Side "long" -Entry 76000
        $pos2 = New-MockPosition -Market "ETHUSDT" -Side "long" -Entry 2100
        $pos3 = New-MockPosition -Market "SOLUSDT" -Side "long" -Entry 85
        Mock-CoinExPositions -Positions @($pos1, $pos2, $pos3)
        
        # Registrar ETHUSDT previamente
        Add-TrailingPosition -Market "ETHUSDT" -Side "LONG" -Entry 2100 -Stop 2000 -Target 2300
        
        # Act
        $result = Sync-OrphanPositions
        
        # Assert
        $result.orphans_detected | Should Be 2  # BTC e SOL
        $result.registered | Should Be 2
        $result.skipped | Should Be 1  # ETH
    }
    
    It "Retorna sucesso mesmo quando não há órfãs" {
        # Arrange: todas registradas
        $pos1 = New-MockPosition -Market "BTCUSDT" -Side "long" -Entry 76000
        Mock-CoinExPositions -Positions @($pos1)
        
        Add-TrailingPosition -Market "BTCUSDT" -Side "LONG" -Entry 76000 -Stop 72000 -Target 80000
        
        # Act
        $result = Sync-OrphanPositions
        
        # Assert
        $result.success | Should Be $true
        $result.orphans_detected | Should Be 0
        $result.registered | Should Be 0
    }
    
    It "Continua processamento mesmo com erro em uma órfã" {
        # Arrange: 2 órfãs, 1 com erro
        $pos1 = New-MockPosition -Market "BTCUSDT" -Side "long" -Entry 76000
        $pos2 = [PSCustomObject]@{ market = ""; side = "long"; avg_entry_price = 0; amount = 0 }  # inválida
        Mock-CoinExPositions -Positions @($pos1, $pos2)
        
        # Act
        $result = Sync-OrphanPositions
        
        # Assert: 1 registrada, 1 erro
        $result.success | Should Be $true
        $result.registered | Should Be 1
        $result.errors | Should Be 1
        
        # BTC deve estar registrada
        $local = Get-TrailingPositions | Where-Object { $_.market -eq "BTCUSDT" -and $_.active }
        $local | Should Not Be $null
    }
}

Describe "Integration: trailing_stop_monitor.ps1 com orphan detection" {
    
    BeforeEach {
        if (Test-Path $global:TRAILING_FILE) {
            Remove-Item $global:TRAILING_FILE -Force
        }
    }
    
    It "Monitor detecta e registra órfãs automaticamente no ciclo normal" {
        # Arrange: posições órfãs na exchange
        $pos1 = New-MockPosition -Market "LINKUSDT" -Side "long" -Entry 9.58 -StopLoss 9.15 -TakeProfit 10.0
        $pos2 = New-MockPosition -Market "BNBUSDT" -Side "long" -Entry 647.06 -StopLoss 627.82 -TakeProfit 679.60
        Mock-CoinExPositions -Positions @($pos1, $pos2)
        
        # Act: simular ciclo do monitor
        $syncResult = Sync-OrphanPositions
        
        # Assert: órfãs registradas
        $syncResult.registered | Should Be 2
        
        # Verificar que trailing stop pode gerenciar agora
        $local = Get-TrailingPositions | Where-Object { $_.active }
        $local.Count | Should Be 2
        
        # Verificar metadados de rastreabilidade
        $link = $local | Where-Object { $_.market -eq "LINKUSDT" }
        $link.source | Should Be "orphan_auto_register"
        $link.mode | Should Be "ORPHAN_AUTO"
    }
}

# Cleanup inline (Pester 3.x: AfterAll so pode ser usado dentro de Describe)
if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -EA SilentlyContinue }
    
    # Limpar diretório temporário
    if (Test-Path $tmpDir) {
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
