# 📱 Resumo Executivo - Otimização de Mensagens Telegram

**Data**: 2026-06-01  
**Objetivo**: Reduzir ruído no Telegram (327 → 7 mensagens/dia)  
**Redução**: 98%

---

## 🎯 O Problema

Você está recebendo **muitas mensagens repetidas e não-acionáveis** no Telegram:

- ❌ Heartbeats a cada 1 hora (24/dia)
- ❌ PRE-SCREEN BLOQUEOU (75/dia)
- ❌ ABORTAR (150/dia)
- ❌ Trailing stop updates (35/dia)
- ❌ Fase transitions (20/dia)
- ❌ Layer advisories (15/dia)
- ❌ Moon bag advisories (8/dia)

**Total**: 327 mensagens/dia que você não pode fazer nada

---

## ✅ A Solução

Categorizar mensagens por importância:

### **TIER 1: CRÍTICO** (Enviar Sempre)
- ✅ Posição aberta (EXECUTAR)
- ✅ Posição fechada (STOP HIT, TP HIT)
- ✅ Liquidação próxima
- ✅ Posição sem proteção
- ✅ Whale alert
- ✅ Erro crítico

### **TIER 2: IMPORTANTE** (Enviar com Dedup)
- ⚠️ Gem aprovado
- ⚠️ Promotion/Demotion
- ⚠️ Regime change
- ⚠️ Kelly sizing ativado

### **TIER 3: INFORMATIVO** (Apenas Dashboard)
- ℹ️ Heartbeat (1x por 6h, não 1x por 1h)
- ℹ️ Trailing updates (apenas >5% mudança)
- ℹ️ Fase transitions (apenas final)
- ℹ️ Layer advisories (apenas CLOSE)
- ℹ️ Moon bag advisories (apenas CLOSE)

### **TIER 4: DEBUG** (Nunca Enviar)
- ❌ PRE-SCREEN BLOQUEOU
- ❌ ABORTAR
- ❌ Triagem score
- ❌ Mesa consensus
- ❌ Mentor reasoning

---

## 📊 Resultado Esperado

| Tipo | Antes/dia | Depois/dia | Redução |
|------|-----------|-----------|---------|
| Heartbeats | 24 | 2 | -92% |
| PRE-SCREEN | 75 | 0 | -100% |
| ABORTAR | 150 | 0 | -100% |
| Trailing | 35 | 5 | -86% |
| Fase | 20 | 0 | -100% |
| Layer | 15 | 0 | -100% |
| Moon Bag | 8 | 0 | -100% |
| **TOTAL** | **327** | **7** | **-98%** |

---

## 🚀 Como Funciona

### Modo Production (Padrão)
```powershell
$global:TELEGRAM_SEND_CRITICAL = $true      # Sempre
$global:TELEGRAM_SEND_IMPORTANT = $true     # Sempre
$global:TELEGRAM_SEND_INFORMATIVE = $false  # Nunca
$global:TELEGRAM_SEND_DEBUG = $false        # Nunca
```

**Resultado**: Apenas 7 mensagens/dia (críticas + importantes)

### Modo Debug (Desenvolvimento)
```powershell
$global:TELEGRAM_SEND_CRITICAL = $true      # Sempre
$global:TELEGRAM_SEND_IMPORTANT = $true     # Sempre
$global:TELEGRAM_SEND_INFORMATIVE = $true   # Sempre
$global:TELEGRAM_SEND_DEBUG = $true         # Sempre
```

**Resultado**: Todas as mensagens (para troubleshooting)

### Modo Verbose (Monitoramento)
```powershell
$global:TELEGRAM_SEND_CRITICAL = $true      # Sempre
$global:TELEGRAM_SEND_IMPORTANT = $true     # Sempre
$global:TELEGRAM_SEND_INFORMATIVE = $true   # Sempre
$global:TELEGRAM_SEND_DEBUG = $false        # Nunca
```

**Resultado**: Críticas + importantes + informativas

---

## 📋 Implementação

### Arquivos a Criar
1. `agents/config.telegram_filter.ps1` - Configuração de filtros

### Arquivos a Modificar
1. `agents/lib_telegram.ps1` - Adicionar `Send-TelegramAlertFiltered`
2. `agents/orchestrator.ps1` - Remover PRE-SCREEN
3. `agents/orchestrator_v6.ps1` - Remover ABORTAR
4. `agents/lib_trailing_adaptive.ps1` - Filtrar pequenas mudanças
5. `agents/lib_layer4_tori_timestop.ps1` - Enviar apenas CLOSE
6. `agents/lib_moon_bag.ps1` - Enviar apenas CLOSE

### Tempo Estimado
- Implementação: 2-3 horas
- Testes: 30 minutos
- Total: ~3 horas

---

## 🎯 Próximos Passos

### Opção 1: Implementação Completa (Recomendado)
Eu implemento todas as mudanças, testo e faz commit.

### Opção 2: Implementação Gradual
Começamos com as mudanças mais impactantes:
1. Remover PRE-SCREEN BLOQUEOU (-75 msg/dia)
2. Remover ABORTAR (-150 msg/dia)
3. Aumentar heartbeat para 6h (-22 msg/dia)
4. Depois: trailing, layer, moon bag

### Opção 3: Apenas Configuração
Você ativa os filtros em `config.local.ps1` sem modificar código.

---

## 💡 Benefícios

✅ **Menos Ruído**: 98% redução de mensagens desnecessárias  
✅ **Mais Foco**: Apenas mensagens acionáveis  
✅ **Melhor UX**: Chat mais limpo e organizado  
✅ **Flexível**: Pode mudar modo conforme necessário  
✅ **Reversível**: Pode voltar ao modo debug a qualquer hora  

---

## 📞 Decisão

**Qual opção você prefere?**

1. ✅ Implementação Completa (3h, máxima redução)
2. ⚠️ Implementação Gradual (1h por fase)
3. ℹ️ Apenas Configuração (5 min, redução parcial)

Ou quer que eu comece com a **Opção 1 (Implementação Completa)**?

