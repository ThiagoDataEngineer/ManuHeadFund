# Dashboard Profissional ManuHeadFund - COMPLETO

## Status: ✅ IMPLEMENTADO

## Visao Geral

Dashboard profissional de nivel hedge fund com:
- ✅ Design moderno e atrativo (dark theme)
- ✅ Metricas avancadas (Sharpe Ratio, Max Drawdown, Profit Factor)
- ✅ Tracking de trailing stop em tempo real
- ✅ Integracao com Telegram para alertas
- ✅ Responsive design (mobile-friendly)
- ✅ Auto-refresh a cada 5 minutos
- ✅ Animacoes e efeitos visuais profissionais

---

## Design System

### Cores Profissionais

```css
Primary Background: #1a1d29 (Dark Navy)
Secondary Background: #252936 (Card Background)
Accent: #00d4aa (Teal - destaque)
Success: #00c853 (Green - lucro)
Danger: #ff1744 (Red - prejuizo)
Warning: #ffc107 (Yellow - alerta)
Text: #e4e7eb (Light Gray)
```

### Tipografia

- **Font Family:** Inter (Google Fonts)
- **Weights:** 300, 400, 500, 600, 700
- **Icons:** Font Awesome 6.4.0

### Layout

- **Max Width:** 1600px
- **Grid:** CSS Grid com auto-fit
- **Responsive:** Breakpoint em 768px
- **Spacing:** 20px gap entre cards

---

## Metricas Exibidas

### Metricas Basicas

1. **Open Positions** - Posicoes abertas
   - Icon: Briefcase
   - Color: Accent (teal) quando > 0

2. **Total PnL** - Lucro/Prejuizo total
   - Icon: Dollar Sign
   - Color: Green (lucro) / Red (prejuizo)

3. **Win Rate** - Taxa de acerto
   - Icon: Percentage
   - Color: Green (≥50%) / Yellow (≥40%) / Red (<40%)

4. **Capital** - Capital disponivel
   - Icon: Wallet
   - Color: Default (white)

### Metricas Avancadas

5. **Sharpe Ratio** - Retorno ajustado ao risco
   - Formula: `avgReturn / stdDev`
   - Color: Green (>1) / Yellow (>0) / Red (≤0)
   - Interpretacao:
     - > 1.0: Excelente
     - 0.5-1.0: Bom
     - < 0.5: Ruim

6. **Max Drawdown** - Maior queda do pico
   - Formula: `((peak - valley) / peak) * 100`
   - Color: Green (<10%) / Yellow (<20%) / Red (≥20%)
   - Interpretacao:
     - < 10%: Excelente controle de risco
     - 10-20%: Aceitavel
     - > 20%: Alto risco

7. **Profit Factor** - Lucro bruto / Prejuizo bruto
   - Formula: `grossProfit / grossLoss`
   - Interpretacao:
     - > 2.0: Excelente
     - 1.5-2.0: Bom
     - 1.0-1.5: Breakeven
     - < 1.0: Perdendo

8. **Avg Win/Loss Ratio** - Media de ganho / Media de perda
   - Formula: `avgWin / avgLoss`
   - Interpretacao:
     - > 2.0: Excelente
     - 1.0-2.0: Bom
     - < 1.0: Ruim

---

## Trailing Stop Tracking

### Indicador Visual

Quando posicao aberta, exibe:

**Trailing ATIVADO (+X%):**
```
🚀 TRAILING +2.5%
```
- Background: Teal transparente
- Border: Teal solido
- Animation: Pulse (pisca suavemente)

**Trailing AGUARDANDO:**
```
Waiting +3%
```
- Color: Gray
- Sem animacao

### Metricas de Trailing

- **Entry Price:** Preco de entrada
- **Current Price:** Preco atual (via ticker)
- **Profit %:** Lucro atual em %
- **Initial Stop:** Stop inicial (-3%)
- **Current Stop:** Stop atual (trailing ou inicial)
- **Locked Profit %:** Lucro travado pelo trailing
- **Max Profit %:** Maior lucro atingido

### Logica de Trailing

```powershell
if (profit% > 3%) {
    trailing_activated = true
    current_stop = current_price * (1 - 3%)
    locked_profit% = ((current_stop - entry) / entry) * 100
} else {
    trailing_activated = false
    current_stop = entry_price * (1 - 3%)
    locked_profit% = -3%
}
```

---

## Integracao Telegram

### Configuracao

**Arquivo:** `config/telegram.json`

```json
{
  "enabled": true,
  "bot_token": "YOUR_BOT_TOKEN",
  "chat_id": "YOUR_CHAT_ID",
  "alerts": {
    "position_opened": true,
    "position_closed": true,
    "stop_loss_hit": true,
    "take_profit_hit": true,
    "trailing_activated": true,
    "risk_alert": true,
    "daily_summary": true
  }
}
```

### Como Configurar

1. **Criar Bot no Telegram:**
   - Abrir [@BotFather](https://t.me/BotFather)
   - Enviar `/newbot`
   - Seguir instrucoes
   - Copiar `bot_token`

2. **Obter Chat ID:**
   - Enviar mensagem para o bot
   - Acessar: `https://api.telegram.org/bot<TOKEN>/getUpdates`
   - Copiar `chat.id`

3. **Atualizar Config:**
   ```powershell
   $config = Get-Content config\telegram.json | ConvertFrom-Json
   $config.enabled = $true
   $config.bot_token = "1234567890:ABCdefGHIjklMNOpqrsTUVwxyz"
   $config.chat_id = "123456789"
   $config | ConvertTo-Json -Depth 10 | Out-File config\telegram.json
   ```

### Tipos de Alertas

#### 1. Position Opened
```
🚀 POSITION OPENED

Market: BNBUSDT
Side: LONG
Entry: $647.06
Size: 0.07 BNB
Leverage: 50x

Stop Loss: $627.82 (-3%)
Take Profit: $679.60 (+5%)

Capital: $2,757.93 USDT
Time: 2026-05-23 14:45:00
```

#### 2. Position Closed
```
✅ POSITION CLOSED

Market: BNBUSDT
Side: LONG
Entry: $647.06
Exit: $679.60

PnL: +$2.27 (+5%)
Duration: 2h 15m

Reason: Take Profit
Time: 2026-05-23 17:00:00
```

#### 3. Trailing Activated
```
📈 TRAILING STOP ACTIVATED

Market: BNBUSDT
Entry: $647.06
Current: $667.08
Profit: +3.09%

New Stop: $647.06
Locked Profit: +0%

Time: 2026-05-23 15:30:00
```

#### 4. Risk Alert
```
⚠️ RISK ALERT

Market: BNBUSDT
Alert Type: High Risk
Severity: WARNING

Details: Distance to liquidation < 10%

Current Price: $640.00
Liquidation: $630.00
Distance: 1.56%

Action Required: Add margin or close position
Time: 2026-05-23 16:00:00
```

#### 5. Daily Summary
```
📈 DAILY SUMMARY

Date: 2026-05-23

Trades Today: 3
Wins: 2 | Losses: 1
Win Rate: 66.7%

Daily PnL: +$5.42 (+0.2%)
Total PnL: $-607.30

Open Positions: 1
Capital: $2,757.93 USDT

Best Trade: +$3.50
Worst Trade: -$1.20
```

---

## Arquivos Criados

### Scripts

1. **`scripts/generate_dashboard_pro.ps1`** - Dashboard profissional
   - Coleta metricas avancadas
   - Gera HTML com design moderno
   - Envia alertas Telegram
   - Auto-refresh a cada 5 minutos

### Libraries

2. **`agents/lib_telegram.ps1`** - Integracao Telegram
   - `Telegram-SendMessage` - Envia mensagem generica
   - `Telegram-SendPositionOpened` - Alerta de posicao aberta
   - `Telegram-SendPositionClosed` - Alerta de posicao fechada
   - `Telegram-SendTrailingActivated` - Alerta de trailing ativado
   - `Telegram-SendRiskAlert` - Alerta de risco
   - `Telegram-SendDailySummary` - Resumo diario

### Config

3. **`config/telegram.json`** - Configuracao Telegram
   - Bot token
   - Chat ID
   - Alertas habilitados/desabilitados
   - Quiet hours (opcional)

### Tests

4. **`tests/dashboard_professional.Tests.ps1`** - TDD tests
   - Visual design requirements
   - Telegram integration
   - Advanced metrics calculation
   - Data refresh and performance
   - Responsive design

### Output

5. **`dashboard/index.html`** - Dashboard HTML
   - Design profissional
   - Metricas em tempo real
   - Trailing stop tracking
   - Responsive layout

---

## Como Usar

### 1. Gerar Dashboard

```powershell
.\scripts\generate_dashboard_pro.ps1
```

**Output:**
```
=== MANUHEADFUND DASHBOARD ===
Coletando metricas...
[OK] Metricas coletadas
  Posicoes abertas: 1
  Total PnL: $-612.65
  Win rate: 49%
  Sharpe ratio: 0

Gerando HTML...
[OK] Dashboard gerado: C:\Users\...\dashboard\index.html

=== COMPLETO ===
```

### 2. Abrir Dashboard

```powershell
# Abrir no navegador
Start-Process "dashboard\index.html"

# Ou acessar via HTTP server (opcional)
python -m http.server 8000 --directory dashboard
# Acessar: http://localhost:8000
```

### 3. Configurar Cron Job

```powershell
# Atualizar scheduled task para usar novo script
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"C:\Users\thiag\Coinex_AI_USER_API\scripts\generate_dashboard_pro.ps1`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName "CoinEx_Dashboard_Pro" `
    -Action $action `
    -Trigger $trigger `
    -Description "ManuHeadFund Professional Dashboard" `
    -Force
```

### 4. Testar Telegram

```powershell
. ".\agents\lib_telegram.ps1"

# Testar mensagem simples
Telegram-SendMessage -Message "Test from ManuHeadFund"

# Testar alerta de posicao
Telegram-SendPositionOpened -Position @{
    market = "BNBUSDT"
    side = "long"
    entry_price = 647.06
    size = "0.07 BNB"
    leverage = 50
    stop_loss = 627.82
    stop_loss_pct = -3
    take_profit = 679.60
    take_profit_pct = 5
    capital = 2757.93
}
```

---

## Comparacao: Antes vs Depois

### Antes (Dashboard Basico)

- ❌ Design simples, sem identidade visual
- ❌ Apenas metricas basicas
- ❌ Sem tracking de trailing stop
- ❌ Sem alertas Telegram
- ❌ Sem metricas avancadas
- ❌ Layout estatico

### Depois (Dashboard Profissional)

- ✅ Design moderno, nivel hedge fund
- ✅ Metricas avancadas (Sharpe, Drawdown, Profit Factor)
- ✅ Trailing stop tracking em tempo real
- ✅ Alertas Telegram automaticos
- ✅ Animacoes e efeitos visuais
- ✅ Responsive design (mobile-friendly)
- ✅ Color-coded metrics (verde/vermelho/amarelo)
- ✅ Icons profissionais (Font Awesome)
- ✅ Tipografia moderna (Inter font)

---

## Proximos Passos

### Curto Prazo

1. ✅ Dashboard profissional implementado
2. ✅ Telegram integration implementada
3. ⏭️ Testar alertas Telegram em producao
4. ⏭️ Adicionar graficos (Chart.js)
5. ⏭️ Adicionar historico de trades

### Medio Prazo

1. Adicionar equity curve chart
2. Adicionar heatmap de performance por hora/dia
3. Adicionar comparacao com benchmark (BTC buy & hold)
4. Adicionar analise de correlacao entre markets
5. Adicionar backtesting results overlay

### Longo Prazo

1. Dashboard multi-usuario (autenticacao)
2. API REST para acesso externo
3. Mobile app (React Native)
4. Alertas via Discord/Slack
5. Machine learning insights

---

## Conclusao

**DASHBOARD PROFISSIONAL COMPLETO!**

✅ Design moderno e atrativo
✅ Metricas avancadas de hedge fund
✅ Trailing stop tracking em tempo real
✅ Integracao Telegram para alertas
✅ Responsive e mobile-friendly
✅ Auto-refresh a cada 5 minutos
✅ TDD completo

**ManuHeadFund pronto para operar com dashboard de nivel institucional!**

---

**Data:** 2026-05-23 14:50:00
**Status:** ✅ COMPLETO
**Metodologia:** TDD (RED → GREEN → REFACTOR)
**Design System:** Professional Dark Theme
**Framework:** Vanilla JS + CSS Grid + Font Awesome
