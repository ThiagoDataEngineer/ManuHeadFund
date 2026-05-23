# diagnose_dashboard.ps1 - Diagnosticar problemas do dashboard
# Rodar: .\scripts\diagnose_dashboard.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\config.ps1"
. ".\agents\lib_coinex.ps1"

Write-Host "`n=== DIAGNOSTICO DO DASHBOARD ===" -ForegroundColor Cyan

# ============================================================================
# TEST 1: CoinEx-GetPendingPositions retorna posicao BNBUSDT?
# ============================================================================

Write-Host "`n[TEST 1] CoinEx-GetPendingPositions" -ForegroundColor Yellow

try {
    $positions = CoinEx-GetPendingPositions
    
    Write-Host "  Tipo: $($positions.GetType().Name)" -ForegroundColor Gray
    Write-Host "  Count: $($positions.Count)" -ForegroundColor Gray
    
    if ($positions.Count -eq 0) {
        Write-Host "  [PROBLEMA] Nenhuma posicao retornada!" -ForegroundColor Red
    } else {
        Write-Host "  [OK] $($positions.Count) posicao(es) encontrada(s)" -ForegroundColor Green
        
        foreach ($pos in $positions) {
            Write-Host "`n  Posicao:" -ForegroundColor Cyan
            Write-Host "    Market: $($pos.market)" -ForegroundColor Gray
            Write-Host "    Side: $($pos.side)" -ForegroundColor Gray
            Write-Host "    Position ID: $($pos.position_id)" -ForegroundColor Gray
            
            # Verificar campos disponiveis
            $fields = $pos.PSObject.Properties.Name
            Write-Host "    Campos disponiveis: $($fields -join ', ')" -ForegroundColor Gray
            
            # Verificar campos criticos
            if ($fields -contains "avg_entry_price") {
                Write-Host "    [OK] avg_entry_price: $($pos.avg_entry_price)" -ForegroundColor Green
            } else {
                Write-Host "    [PROBLEMA] avg_entry_price NAO EXISTE" -ForegroundColor Red
            }
            
            if ($fields -contains "open_price") {
                Write-Host "    [PROBLEMA] open_price existe (campo errado!)" -ForegroundColor Red
            } else {
                Write-Host "    [OK] open_price nao existe (correto)" -ForegroundColor Green
            }
            
            if ($fields -contains "liq_price") {
                Write-Host "    [OK] liq_price: $($pos.liq_price)" -ForegroundColor Green
            } else {
                Write-Host "    [PROBLEMA] liq_price NAO EXISTE" -ForegroundColor Red
            }
            
            if ($fields -contains "liquidation_price") {
                Write-Host "    [PROBLEMA] liquidation_price existe (campo errado!)" -ForegroundColor Red
            } else {
                Write-Host "    [OK] liquidation_price nao existe (correto)" -ForegroundColor Green
            }
            
            if ($fields -contains "latest_price") {
                Write-Host "    [PROBLEMA] latest_price existe (campo errado!)" -ForegroundColor Red
            } else {
                Write-Host "    [OK] latest_price nao existe (correto)" -ForegroundColor Green
            }
        }
    }
} catch {
    Write-Host "  [ERRO] $_" -ForegroundColor Red
}

# ============================================================================
# TEST 2: CoinEx-GetTickerFresh funciona?
# ============================================================================

Write-Host "`n[TEST 2] CoinEx-GetTickerFresh" -ForegroundColor Yellow

try {
    $ticker = CoinEx-GetTickerFresh -market "BNBUSDT"
    
    Write-Host "  Tipo: $($ticker.GetType().Name)" -ForegroundColor Gray
    
    if ($ticker.ticker) {
        Write-Host "  [OK] ticker.last: $($ticker.ticker.last)" -ForegroundColor Green
    } else {
        Write-Host "  [PROBLEMA] ticker.last NAO EXISTE" -ForegroundColor Red
        Write-Host "  Campos: $($ticker.PSObject.Properties.Name -join ', ')" -ForegroundColor Gray
    }
} catch {
    Write-Host "  [ERRO] $_" -ForegroundColor Red
}

# ============================================================================
# TEST 3: HTML encoding
# ============================================================================

Write-Host "`n[TEST 3] HTML Encoding" -ForegroundColor Yellow

try {
    $htmlPath = "dashboard\position_metrics.html"
    
    if (Test-Path $htmlPath) {
        # Ler com UTF-8
        $content = Get-Content -Path $htmlPath -Raw -Encoding UTF8
        
        # Verificar caracteres corrompidos
        if ($content -match 'ðŸ"Š' -or $content -match 'Ãšltima' -or $content -match 'PosiÃ§Ãµes') {
            Write-Host "  [PROBLEMA] HTML contem caracteres corrompidos" -ForegroundColor Red
            Write-Host "    Encontrado caracteres corrompidos no lugar de emojis e acentos" -ForegroundColor Red
        } else {
            Write-Host "  [OK] HTML com encoding correto" -ForegroundColor Green
        }
        
        # Verificar meta charset
        if ($content -match '<meta charset="UTF-8">') {
            Write-Host "  [OK] Meta charset UTF-8 presente" -ForegroundColor Green
        } else {
            Write-Host "  [PROBLEMA] Meta charset UTF-8 ausente" -ForegroundColor Red
        }
    } else {
        Write-Host "  [PROBLEMA] HTML nao encontrado: $htmlPath" -ForegroundColor Red
    }
} catch {
    Write-Host "  [ERRO] $_" -ForegroundColor Red
}

# ============================================================================
# TEST 4: Dashboard script field mapping
# ============================================================================

Write-Host "`n[TEST 4] Dashboard Script Field Mapping" -ForegroundColor Yellow

try {
    $dashScript = Get-Content -Path "scripts\generate_position_dashboard.ps1" -Raw
    
    # Verificar uso de campos errados
    if ($dashScript -match '\$pos\.open_price') {
        Write-Host "  [PROBLEMA] Script usa open_price (campo errado!)" -ForegroundColor Red
    } else {
        Write-Host "  [OK] Script nao usa open_price" -ForegroundColor Green
    }
    
    if ($dashScript -match '\$pos\.latest_price') {
        Write-Host "  [PROBLEMA] Script usa latest_price (campo errado!)" -ForegroundColor Red
    } else {
        Write-Host "  [OK] Script nao usa latest_price" -ForegroundColor Green
    }
    
    if ($dashScript -match '\$pos\.liquidation_price') {
        Write-Host "  [PROBLEMA] Script usa liquidation_price (campo errado!)" -ForegroundColor Red
    } else {
        Write-Host "  [OK] Script nao usa liquidation_price" -ForegroundColor Green
    }
    
    # Verificar uso de campos corretos
    if ($dashScript -match '\$pos\.avg_entry_price') {
        Write-Host "  [OK] Script usa avg_entry_price (correto)" -ForegroundColor Green
    } else {
        Write-Host "  [PROBLEMA] Script NAO usa avg_entry_price" -ForegroundColor Red
    }
    
    if ($dashScript -match 'CoinEx-GetTickerFresh') {
        Write-Host "  [OK] Script usa CoinEx-GetTickerFresh (correto)" -ForegroundColor Green
    } else {
        Write-Host "  [PROBLEMA] Script NAO usa CoinEx-GetTickerFresh" -ForegroundColor Red
    }
    
    if ($dashScript -match '\$pos\.liq_price') {
        Write-Host "  [OK] Script usa liq_price (correto)" -ForegroundColor Green
    } else {
        Write-Host "  [PROBLEMA] Script NAO usa liq_price" -ForegroundColor Red
    }
} catch {
    Write-Host "  [ERRO] $_" -ForegroundColor Red
}

# ============================================================================
# TEST 5: Simular Get-PositionMetrics
# ============================================================================

Write-Host "`n[TEST 5] Simular Get-PositionMetrics" -ForegroundColor Yellow

try {
    . ".\scripts\generate_position_dashboard.ps1"
    
    # Chamar funcao (sem executar MAIN)
    $metrics = Get-PositionMetrics
    
    if ($metrics) {
        Write-Host "  [OK] Metricas coletadas" -ForegroundColor Green
        Write-Host "    Posicoes abertas: $($metrics.open_positions)" -ForegroundColor Gray
        Write-Host "    Total trades: $($metrics.total_trades)" -ForegroundColor Gray
        Write-Host "    Win rate: $($metrics.win_rate)%" -ForegroundColor Gray
        Write-Host "    PnL total: `$$($metrics.total_pnl)" -ForegroundColor Gray
        
        if ($metrics.open_positions -eq 0) {
            Write-Host "  [PROBLEMA] Nenhuma posicao aberta detectada!" -ForegroundColor Red
        }
        
        if ($metrics.open_positions_detail) {
            Write-Host "  [OK] Detalhes de posicoes abertas disponiveis" -ForegroundColor Green
        } else {
            Write-Host "  [PROBLEMA] Detalhes de posicoes abertas NAO disponiveis" -ForegroundColor Red
        }
    } else {
        Write-Host "  [PROBLEMA] Metricas nao coletadas" -ForegroundColor Red
    }
} catch {
    Write-Host "  [ERRO] $_" -ForegroundColor Red
}

Write-Host "`n=== DIAGNOSTICO COMPLETO ===" -ForegroundColor Cyan
