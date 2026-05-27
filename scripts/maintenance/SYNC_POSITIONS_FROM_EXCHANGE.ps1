# SYNC_POSITIONS_FROM_EXCHANGE.ps1
# Script para sincronizar posições da CoinEx com o sistema local
# Criado: 2026-05-24
# 
# PROBLEMA IDENTIFICADO:
# - trailing_positions.json está vazio mas há 4 posições ativas na exchange
# - Trailing stop monitor não consegue gerenciar posições não registradas localmente
# - Risco: posições sem proteção de trailing stop automático
#
# SOLUÇÃO:
# Este script busca todas as posições abertas na CoinEx e registra no trailing_positions.json

# Carregar libs
$scriptRoot = $PSScriptRoot
. "$scriptRoot\agents\config.ps1"
. "$scriptRoot\agents\lib_coinex.ps1"
. "$scriptRoot\agents\lib_trailing.ps1"

Write-Host "=== SYNC POSITIONS FROM EXCHANGE ===" -ForegroundColor Cyan
Write-Host ""

# Verificar credenciais
if (-not $COINEX_ACCESS_ID -or -not $COINEX_SECRET_KEY) {
    Write-Host "ERROR: Credenciais não configuradas em agents/config.ps1" -ForegroundColor Red
    exit 1
}

try {
    # 1. Buscar posições abertas na exchange
    Write-Host "Buscando posições abertas na CoinEx..." -ForegroundColor Yellow
    $positions = CoinEx-GetPendingPositions
    
    if (-not $positions -or $positions.Count -eq 0) {
        Write-Host "Nenhuma posição aberta encontrada." -ForegroundColor Green
        exit 0
    }
    
    Write-Host "Encontradas $($positions.Count) posição(ões) aberta(s):" -ForegroundColor Green
    Write-Host ""
    
    # 2. Verificar quais já estão registradas localmente
    $localPositions = Get-TrailingPositions
    $localMarkets = @($localPositions | Where-Object { $_.active } | ForEach-Object { $_.market })
    
    # 3. Registrar posições faltantes
    $synced = 0
    $skipped = 0
    
    foreach ($pos in $positions) {
        $market = $pos.market
        $side = if ($pos.side -eq "long") { "LONG" } else { "SHORT" }
        $entry = [double]$pos.avg_entry_price
        $amount = [double]$pos.amount
        
        # Verificar se já está registrada
        if ($localMarkets -contains $market) {
            Write-Host "  ✓ $market - Já registrada localmente" -ForegroundColor DarkGray
            $skipped++
            continue
        }
        
        # Buscar stop loss e take profit configurados
        $stopLoss = $null
        $takeProfit = $null
        
        if ($pos.PSObject.Properties['stop_loss_price'] -and $pos.stop_loss_price) {
            $stopLoss = [double]$pos.stop_loss_price
        }
        if ($pos.PSObject.Properties['take_profit_price'] -and $pos.take_profit_price) {
            $takeProfit = [double]$pos.take_profit_price
        }
        
        # Se não tem stop loss configurado, calcular um conservador (5% abaixo/acima)
        if (-not $stopLoss) {
            if ($side -eq "LONG") {
                $stopLoss = [math]::Round($entry * 0.95, 4)
            } else {
                $stopLoss = [math]::Round($entry * 1.05, 4)
            }
            Write-Host "  ⚠ $market - SEM STOP LOSS na exchange! Usando stop conservador: `$$stopLoss" -ForegroundColor Yellow
        }
        
        # Se não tem take profit, calcular um razoável (15% acima/abaixo)
        if (-not $takeProfit) {
            if ($side -eq "LONG") {
                $takeProfit = [math]::Round($entry * 1.15, 4)
            } else {
                $takeProfit = [math]::Round($entry * 0.85, 4)
            }
        }
        
        # Registrar no sistema local
        try {
            Add-TrailingPosition `
                -Market $market `
                -Side $side `
                -Entry $entry `
                -Stop $stopLoss `
                -Target $takeProfit `
                -Source "manual_sync" `
                -Mode "STANDARD"
            
            Write-Host "  ✓ $market - Sincronizada! Entry: `$$entry | Stop: `$$stopLoss | Target: `$$takeProfit" -ForegroundColor Green
            $synced++
        }
        catch {
            Write-Host "  ✗ $market - ERRO ao sincronizar: $_" -ForegroundColor Red
        }
    }
    
    Write-Host ""
    Write-Host "=== RESUMO ===" -ForegroundColor Cyan
    Write-Host "Total de posições na exchange: $($positions.Count)" -ForegroundColor White
    Write-Host "Sincronizadas: $synced" -ForegroundColor Green
    Write-Host "Já registradas: $skipped" -ForegroundColor DarkGray
    Write-Host ""
    
    if ($synced -gt 0) {
        Write-Host "✓ Sincronização concluída! O trailing stop monitor agora pode gerenciar todas as posições." -ForegroundColor Green
        Write-Host ""
        Write-Host "PRÓXIMOS PASSOS:" -ForegroundColor Yellow
        Write-Host "1. Verifique o arquivo: journal\trailing_positions.json" -ForegroundColor White
        Write-Host "2. O monitor de trailing stop atualizará automaticamente a cada 5 minutos" -ForegroundColor White
        Write-Host "3. Para atualização manual, execute: .\scripts\trailing_stop_monitor.ps1" -ForegroundColor White
    }
}
catch {
    Write-Host "ERRO CRÍTICO: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    exit 1
}
