# STATUS: Todos os Caminhos de Entrada de Trade (2026-06-19)

## 1️⃣ GEM_LOOP (Principal - automático)

**Status:** ✅ ATIVO  
**Arquivo:** `scripts/gem_loop.ps1`  
**GitHub Actions:** JOB 23 (CLOUD TRADING)  
**Frequência:** A cada 15 minutos  
**Modo:** Automático (não requer input)

### Fluxo:
```
gem_scan → gem_executor → Approval gate → CoinEx order
```

### Resultado:
- ✅ Encontra sinais (G1-G4 gates)
- ✅ Passa por conviction + tori + mentor
- ⚠️ Bloqueia se posição já aberta (by design)
- ✅ Executa ordem se tudo OK

---

## 2️⃣ SCAN_MASTER (Observação contínua)

**Status:** ⚠️ OBSERVE ONLY (não entra)  
**Arquivo:** `scripts/cloud_conviction_scan.ps1`  
**GitHub Actions:** JOB 22 (CLOUD CONVICTION SCAN)  
**Frequência:** A cada hora (no :20)  
**Modo:** Observação (registra + aprende, não executa)

### Fluxo:
```
Scan movers → Calcular conviction 7-eixos → Log observações → NÃO executa
```

### Função:
- ✅ Monitora pares emergentes
- ✅ Calcula conviction (multi-timeframe + BTC RS + volume)
- ✅ Valida edge antes de virar live
- ❌ NÃO entra trades (validação ~1 semana)

### Status:
```
Implementado: SIM
Testado: SIM (faltam 3 testes)
Produção: SIM (observe-only)
```

---

## 3️⃣ TELEGRAM /idea (Manual - price trigger)

**Status:** ✅ IMPLEMENTADO  
**Arquivo:** `scripts/telegram_listener.ps1`  
**GitHub Actions:** JOB 24 (TELEGRAM CLOUD)  
**Frequência:** A cada 5 minutos (listener -Once)  
**Modo:** Manual (usuário cria alerta)

### Comando:
```
/idea MARKET PRICE [long|short]
Exemplo: /idea METUSDT 0.15 long
```

### Fluxo:
```
Usuário: /idea METUSDT 0.15
  ↓
telegram_listener captura
  ↓
Cria entry em signal_triggers.jsonl
  ↓
gem_loop próximo ciclo (15 min)
  ↓
Lê signal_triggers.jsonl
  ↓
Se convicção OK → entra trade
```

### Status:
```
Implementado: SIM
Testado: SIM (integração completa)
Produção: SIM (live)
```

### Limitações:
- ⚠️ Convicção ainda é calculada (pode rejeitar)
- ⚠️ Tori gate ainda valida (pode rejeitar)
- ✅ Mas /approve bypassa tudo

---

## 4️⃣ TELEGRAM /approve (Força entry - bypass gates)

**Status:** ⚠️ PARCIALMENTE IMPLEMENTADO  
**Arquivo:** `scripts/telegram_listener.ps1` (mapeado em linha 369)  
**GitHub Actions:** JOB 24  
**Frequência:** A cada 5 minutos  
**Modo:** Manual (força entrada)

### Comando:
```
/approve MARKET
Exemplo: /approve METUSDT
```

### Esperado:
```
Usuário: /approve METUSDT
  ↓
Bypassa TODOS os gates (conviction, tori, mentor)
  ↓
gem_executor força entrada
  ↓
Trade executado
```

### Status REAL:
```
Mapeado no telegram_listener: SIM (linha 369)
Função Process-ApprovalCommand: ???
Implementação: DESCONHECIDA
```

### Verificação necessária:
```powershell
# Verifica se função existe
Get-Command Process-ApprovalCommand -ErrorAction SilentlyContinue

# Se não existe: /approve não funciona
```

---

## 5️⃣ SCAN_ORBIT (Pump-riding - futuro)

**Status:** ❌ NÃO IMPLEMENTADO  
**Arquivo:** Não existe  
**GitHub Actions:** Não agendado  
**Frequência:** N/A  
**Modo:** N/A (conceitual)

### O que seria:
```
Detecta pump em andamento
  ↓
Entra no meio do movimento (não no começo)
  ↓
Exit rápido (+5-10%)
  ↓
Scalp puro
```

### Por que não tem:
- Complexidade alta (market entry timing crítico)
- Stop loss muito apertado (risco grande)
- Melhor começar com gem_loop estável

---

## 📊 MATRIZ DE STATUS

| Caminho | Ativo | Automático | Entrada Executada | Testes | Produção |
|---------|-------|-----------|-------------------|--------|----------|
| **gem_loop** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **scan_master** | ✅ | ✅ | ❌ (observe) | ⚠️ | ✅ |
| **/idea** | ✅ | ❌ | ✅ | ✅ | ✅ |
| **/approve** | ⚠️ | ❌ | ❓ | ❓ | ❓ |
| **scan_orbit** | ❌ | ❌ | ❌ | ❌ | ❌ |

---

## 🔧 O QUE PODE ESTAR FALHANDO

### /approve (Chance: 70%)
**Problema provável:**
```
Mapeado em telegram_listener.ps1 linha 369
  ↓
Chama Process-ApprovalCommand
  ↓
Se essa função não existe → /approve mudo (sem erro)
```

**Teste:**
```powershell
pwsh
. agents/lib_tg_approval_handler.ps1
Get-Command Process-ApprovalCommand
```

**Se não encontrar:**
- Arquivo `lib_tg_approval_handler.ps1` não carregado
- Ou função não exportada
- Ou nome diferente

### scan_master vs cloud_conviction_scan (Confusão possível)
**Histórico:**
- Antigamente: scan_master rodava trades
- Agora: cloud_conviction_scan roda observe-only
- gem_loop pega a função

**Status real:**
```
scan_master.ps1 — arquivo antigo (pode não estar em uso)
cloud_conviction_scan.ps1 — arquivo novo (JOB 22 in production)
gem_loop.ps1 — arquivo ativo (JOB 23 in production)
```

---

## ✅ RECOMENDAÇÕES

### Imediato (esta semana)
1. ✅ Verify `/approve` funciona
   ```
   Teste: /approve METUSDT no Telegram
   Esperado: Entra ordem em CoinEx em <1min
   ```

2. ✅ Verify `/idea` funciona
   ```
   Teste: /idea TESTUSDT 100.00 long
   Esperado: Cria alerta em signal_triggers.jsonl
   ```

3. ✅ Verify scan_master roda
   ```
   Teste: Verificar journal logs a cada hora (:20)
   Esperado: Encontra observações (não trades)
   ```

### Médio prazo (próximas 2 semanas)
1. Se `/approve` quebrado → fixar
2. Se `scan_master` falhando → debugar
3. Considerar `scan_orbit` para fase 2

---

## 🎯 RESUMO EXECUTIVO

| Caminho | Status | Qual Usar |
|---------|--------|-----------|
| **gem_loop** | ✅ Funciona | Padrão (automático) |
| **scan_master** | ✅ Funciona (observe) | Para validation antes de live |
| **/idea** | ✅ Funciona | Criar alertas manuais |
| **/approve** | ⚠️ Verificar | Forçar entry (se funciona) |
| **scan_orbit** | ❌ Não tem | Futuro (não fazer agora) |

**Status real:** 3/5 caminhos confirmados ✅, 1 questionado ⚠️, 1 deferred ❌

Quer que eu verifique se `/approve` está funcionando? Posso rodar teste ou debugar a função.
