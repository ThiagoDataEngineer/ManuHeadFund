# 🧠 Trailing Adaptativo & Auto-Mode Switching

**Conceito:** Um sistema que **muda automaticamente entre 4 modos** baseado em:
- Estado do trade (Phase, PnL, idade)
- Contexto de mercado (volatilidade, BTC, eventos)
- Confiança do algoritmo (histórico de acertos)
- Disponibilidade do trader (online/offline detection)

---

## 🎚️ OS 4 MODOS DE OPERAÇÃO

### Modo 1: 🔵 OBSERVE (passivo, total controle do trader)
```
Trailing apenas reativo (Phases 0-3)
Smart camadas analisam mas NADA notifica
Para: trades novos, mercado lateral seguro
```

### Modo 2: 🟢 SUGGEST (avisa, você decide)
```
Smart Trailing detecta sinais
Envia Telegram com botões ✅/❌
Para: trades em phase 0-1, situações ambíguas
```

### Modo 3: 🟡 CONFIRM (aplica com confirmação rápida)
```
Smart sugere ação E aplica em X minutos se nao houver veto
Para: trades em phase 2+, sinais claros (exhaustion >70)
```

### Modo 4: 🔴 AUTO (executa imediato sem perguntar)
```
Hard rules: flash crash, drawdown catastrofico, eventos macro
Para: emergências reais, sem tempo para humano decidir
```

---

## 🤖 SWITCHING AUTOMÁTICO ENTRE MODOS

### Sinais que mudam o modo

#### Para mais agressivo (OBSERVE → SUGGEST → CONFIRM → AUTO)
- **Trade idade** > X dias sem mover (vai para AUTO time-exit)
- **Phase do trade** avança (mais profit = mais protege)
- **Drawdown** se aproximando de stop (-2%, -3%, -4%)
- **Volatilidade explode** (ATR diário > 8%)
- **BTC flash crash** (-5% em 1h)
- **Algoritmo histórico**: alertas anteriores acertaram >80%

#### Para mais conservador (AUTO → CONFIRM → SUGGEST → OBSERVE)
- **Trader online detectado** (recente atividade Telegram)
- **Mercado lateral calmo** (ATR baixo, vol normal)
- **Trade em lucro** com folga grande
- **Trader desabilitou** explicitamente

---

## 🧠 ALGORITMO DECISOR

```python
def decide_trailing_mode(position, market_context, trader_context):
    # Score de "urgência" 0-100
    urgency = 0
    
    # Idade do trade
    if days_open > 7: urgency += 20
    if days_open > 14: urgency += 30  # forçar exit
    
    # Phase
    if phase >= 2: urgency += 15  # mais a perder
    if phase >= 3: urgency += 25  # trailing ativo
    
    # Distância do stop
    if stop_dist_pct < 1.5: urgency += 40  # crítico
    if stop_dist_pct < 3: urgency += 20
    
    # Volatilidade
    if atr_pct > 8: urgency += 25  # extreme vol
    
    # Macro
    if btc_change_1h < -3: urgency += 50  # crash
    if event_window_active: urgency += 30
    
    # Trader presence
    last_tg_activity_hours = get_last_telegram_activity()
    if last_tg_activity_hours > 4: urgency += 20  # offline
    if last_tg_activity_hours > 12: urgency += 30  # dormindo/ausente
    
    # Confiança histórica
    algo_accuracy = get_recent_alert_accuracy(last_30_alerts)
    if algo_accuracy > 0.8: urgency -= 10  # algoritmo confiável
    if algo_accuracy < 0.5: urgency += 20  # não confiar
    
    # Mapear urgency para modo
    if urgency < 30: return "OBSERVE"
    if urgency < 60: return "SUGGEST"
    if urgency < 85: return "CONFIRM"
    return "AUTO"
```

---

## 📊 EXEMPLO PRÁTICO COM SUAS POSIÇÕES

### UNI (-2.55%, stop a 0.66% do preço)
```
Idade: 1 dia (+0)
Phase 0 (+0)
Stop dist: 0.66% (+40 CRÍTICO!)
ATR: 0.83%/h = 20% diário (+25 extreme)
BTC: +0.6% (sem stress)
Trader: ativo (+0)
Algo: novo (+0)
TOTAL: 65 → CONFIRM mode

Ação: Smart sugere apertar + aplica em 10min se nao vetar
```

### BNB (+3.17%, Phase 2)
```
Idade: 1 dia (+0)
Phase 2 (+15)
Stop dist: 2% (+0)
ATR baixo (+0)
BTC OK (+0)
Trader ativo (+0)
TOTAL: 15 → OBSERVE mode

Ação: Trailing reativo cuida (já em Phase 2)
```

### Cenário: BTC -5% flash crash agora
```
Macro: +50
Volatilidade: +25
Trader: pode estar offline (+20)
TOTAL: 95 → AUTO mode em todas posições

Ação: Tighten stops 50% imediato, alerta TG + email
```

---

## 🎯 DETECÇÃO DE PRESENÇA DO TRADER

**Como detectar se você está online:**
1. **Telegram activity**: última mensagem/comando enviado
2. **Dashboard refresh**: GitHub Pages logs (analytics)
3. **Manual heartbeat**: comando `/online` por 4h
4. **Time of day**: 10am-22h BRT = provavelmente online
5. **Day of week**: dias úteis vs fim de semana

**Default conservador:** assume offline se não detectar atividade em 4h.

---

## 📈 APRENDIZADO CONTÍNUO

### Telemetria coletada
```json
{
  "alert_id": "abc123",
  "timestamp": "2026-05-25T14:00",
  "market": "UNIUSDT",
  "mode": "SUGGEST",
  "trigger": "exhaustion_score=72",
  "suggested_action": "tighten_stop",
  "user_response": "ignored",  // ou approved/timeout
  "outcome_24h": "trade_recovered_+1.5%",  // ou stopped/breakeven
  "algorithm_was": "wrong"  // user decision was correct
}
```

### Calibração automática semanal
- Threshold de exhaustion (atual 70) ajusta para 75 se taxa erro > 30%
- Mode switching urgency cutoffs ajustam por par
- Pesos das 5 camadas re-balanceiam por accuracy

---

## 🏗️ ARQUITETURA DE IMPLEMENTAÇÃO

```
┌─────────────────────────────────────────────────────┐
│  Trailing Mode Decider (executa a cada 5min)        │
│                                                     │
│  1. Calcula urgency score por posição              │
│  2. Decide modo (OBSERVE/SUGGEST/CONFIRM/AUTO)     │
│  3. Executa ação apropriada ao modo                │
│  4. Loga decisão para telemetria                   │
└─────────────────────────────────────────────────────┘
              │
              ↓
┌─────────────────────────────────────────────────────┐
│  Action Executor                                    │
│                                                     │
│  OBSERVE  → log only                               │
│  SUGGEST  → telegram com botões ✅/❌              │
│  CONFIRM  → telegram + timer 10min para veto       │
│  AUTO     → executa + telegram informativo         │
└─────────────────────────────────────────────────────┘
              │
              ↓
┌─────────────────────────────────────────────────────┐
│  Telemetry Logger                                   │
│                                                     │
│  Salva todas decisões para análise pós-fato        │
│  Calcula accuracy do algoritmo                     │
│  Calibra thresholds semanalmente                   │
└─────────────────────────────────────────────────────┘
```

---

## 💻 COMPONENTES NOVOS A CRIAR

### 1. `lib_trailing_mode_decider.ps1`
- `Get-TrailingMode` — calcula urgency e retorna modo
- `Get-TraderPresence` — detecta atividade recente
- `Get-AlgorithmAccuracy` — histórico de acertos

### 2. `lib_trailing_action_executor.ps1`
- `Invoke-ObserveMode` — log only
- `Invoke-SuggestMode` — telegram com botões
- `Invoke-ConfirmMode` — telegram + timer veto
- `Invoke-AutoMode` — executa direto

### 3. `lib_trailing_telemetry.ps1`
- `Log-TrailingDecision` — salva em journal
- `Get-DecisionStats` — calcula accuracy
- `Calibrate-Thresholds` — ajusta thresholds

### 4. `tests/trailing_mode_decider.Tests.ps1`
- TDD para todos os cenários de switching

---

## ⚠️ HARD RULES (sempre AUTO, sem opção)

Mesmo em modo OBSERVE, certas situações forçam ação:

| Trigger | Ação | Motivo |
|---------|------|--------|
| BTC -5% em 1h | Tighten 50% todas longs | Flash crash, sem tempo |
| Drawdown total -5% | Close worst position | Capital protection |
| Posição -7% | Close imediato | Hard stop catastrófico |
| FOMC em 30min | Tighten 30% todas | Volatilidade pré-evento |
| Stop violado | Close imediato | Disciplina |

---

## 🎓 FILOSOFIA DO SISTEMA

> "Tudor Jones disse: 'Sou primariamente um trader posicionado de risco.' 
> O sistema deve refletir isso — protege capital agressivamente em emergências, 
> mas dá liberdade humana onde a intuição agrega valor."

**3 princípios:**
1. **Hard rules para emergências** (catastrofes não esperam decisão humana)
2. **Trader-in-the-loop para ambiguidade** (intuição > algoritmo)
3. **Aprendizado contínuo** (sistema melhora com uso)

---

## 🚀 PLANO DE IMPLEMENTAÇÃO

### Fase 1 (4-5h): Mode Decider + Hard Rules
- TDD `Get-TrailingMode` (10+ testes)
- TDD `Get-TraderPresence`
- TDD hard rules emergenciais
- Wire-up no `Update-TrailingStops`

### Fase 2 (3-4h): Action Executors
- `Invoke-SuggestMode` com Telegram inline keyboard
- `Invoke-ConfirmMode` com timer veto
- Integração com cascade Mentor (opcional)

### Fase 3 (2-3h): Telemetria + Calibração
- Logger de decisões
- Stats de accuracy
- Auto-calibração semanal

### Fase 4 (1-2h): Dashboard
- Visualização do modo de cada posição
- Histórico de alertas + decisões
- Estatísticas de algoritmo

**Total: ~12-15 horas de trabalho TDD**

---

## ✅ DECISÃO

Esse é o sistema **certo** para o seu caso:

- **Inteligente**: usa as 5 camadas Smart Trailing
- **Adaptativo**: muda de modo conforme contexto
- **Respeitoso**: te dá controle quando importa
- **Protetor**: hard rules para emergências
- **Aprende**: telemetria informa evolução

**Quer que eu comece pela Fase 1 (Mode Decider + Hard Rules)?**

São os componentes mais críticos e a base para tudo depois.
