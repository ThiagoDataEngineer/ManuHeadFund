# 🚀 Quick Start - Sistema de Validação

## ⚠️ AÇÃO URGENTE

### Proteger NEAR Agora
```powershell
.\PROTECT_NEAR_NOW.ps1
```

---

## 📋 Comandos Essenciais

### 1. Proteger Posição Específica
```powershell
. .\agents\config.ps1
. .\agents\lib_coinex.ps1
. .\agents\lib_order_validation.ps1

Set-PositionStopLossFallback -Market "NEARUSDT" -Price 2.35
```

### 2. Verificar Todas as Posições
```powershell
.\FIX_MISSING_STOPS.ps1
```

### 3. Executar Nova Ordem (Recomendado)
```powershell
$result = Invoke-OrderWithValidation `
    -Market "BTCUSDT" `
    -Side "buy" `
    -Amount 100 `
    -StopLoss 95000 `
    -TakeProfit 105000 `
    -Leverage 5
```

### 4. Verificar Posição
```powershell
. .\agents\lib_order_validation.ps1
Test-PositionHasStopLoss -Market "NEARUSDT"
```

### 5. Ver Logs do Monitor
```powershell
Get-Content logs\trailing_stop_monitor.log -Tail 50 -Wait
```

### 6. Executar Testes
```powershell
Invoke-Pester tests\lib_order_validation.Tests.ps1
```

---

## 📊 Status Atual

### Testes TDD
```
✅ 9 testes passando
❌ 0 testes falhando
⏱️ 4.12s tempo de execução
```

### Posições
```
BNBUSDT  : ✅ Stop $627.82
SOLUSDT  : ✅ Stop $82.30
LINKUSDT : ✅ Stop $9.15
UNIUSDT  : ✅ Stop $3.30
NEARUSDT : ❌ SEM STOP LOSS ⚠️
```

---

## 🔧 Troubleshooting

### Se PROTECT_NEAR_NOW.ps1 Falhar
```powershell
# Opção 1: Tentar novamente com mais retries
Set-PositionStopLossFallback -Market "NEARUSDT" -Price 2.35 -MaxRetries 5

# Opção 2: Configurar manualmente na exchange
# Acesse: https://www.coinex.com/futures/NEARUSDT
```

### Se FIX_MISSING_STOPS.ps1 Não Encontrar Posições
```powershell
# Verificar credenciais
. .\agents\config.ps1
Write-Host "Access ID: $COINEX_ACCESS_ID"
Write-Host "Secret Key: $(if ($COINEX_SECRET_KEY) { 'Configurado' } else { 'FALTANDO' })"
```

---

## 📚 Documentação Completa

- `ORDER_VALIDATION_SYSTEM_COMPLETE.md` - Documentação técnica
- `VALIDACAO_POS_EXECUCAO_2026_05_24.md` - Guia de uso
- `RESUMO_VALIDACAO_COMPLETO_2026_05_24.md` - Resumo executivo

---

## ✅ Próximos Passos

1. ⚠️ **URGENTE**: `.\PROTECT_NEAR_NOW.ps1`
2. 📊 Verificar outras posições: `.\FIX_MISSING_STOPS.ps1`
3. 🧪 Executar testes: `Invoke-Pester tests\lib_order_validation.Tests.ps1`
4. 📈 Monitorar logs: `Get-Content logs\trailing_stop_monitor.log -Tail 50 -Wait`
