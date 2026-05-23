# Telegram Setup Guide - ManuHeadFund

## Guia Rapido de Configuracao

### Passo 1: Criar Bot no Telegram

1. Abrir Telegram e buscar por **@BotFather**
2. Enviar comando: `/newbot`
3. Escolher nome do bot: `ManuHeadFund Bot`
4. Escolher username: `manuheadfund_bot` (deve terminar com `_bot`)
5. Copiar o **token** fornecido (ex: `1234567890:ABCdefGHIjklMNOpqrsTUVwxyz`)

### Passo 2: Obter Chat ID

**Opcao A: Via API (Recomendado)**

1. Enviar qualquer mensagem para o bot criado
2. Acessar no navegador:
   ```
   https://api.telegram.org/bot<SEU_TOKEN>/getUpdates
   ```
3. Procurar por `"chat":{"id":123456789`
4. Copiar o numero (ex: `123456789`)

**Opcao B: Via Bot @userinfobot**

1. Buscar por **@userinfobot** no Telegram
2. Enviar `/start`
3. Copiar o **ID** fornecido

### Passo 3: Configurar Sistema

```powershell
# Editar config/telegram.json
notepad config\telegram.json
```

**Substituir:**
```json
{
  "enabled": true,
  "bot_token": "1234567890:ABCdefGHIjklMNOpqrsTUVwxyz",
  "chat_id": "123456789",
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

### Passo 4: Testar

```powershell
# Carregar biblioteca
. ".\agents\lib_telegram.ps1"

# Enviar mensagem de teste
Telegram-SendMessage -Message "✅ ManuHeadFund conectado com sucesso!"
```

**Resultado Esperado:**
- Mensagem aparece no Telegram
- Console mostra: `[TELEGRAM] Mensagem enviada com sucesso`

### Passo 5: Testar Alertas

```powershell
# Testar alerta de posicao aberta
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

## Troubleshooting

### Erro: "Config not found"

**Problema:** Arquivo `config/telegram.json` nao existe

**Solucao:**
```powershell
# Criar diretorio
New-Item -ItemType Directory -Path "config" -Force

# Criar arquivo
@"
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
"@ | Out-File -FilePath "config\telegram.json" -Encoding UTF8
```

### Erro: "Unauthorized"

**Problema:** Bot token invalido

**Solucao:**
1. Verificar se copiou token completo (incluindo `:`)
2. Verificar se nao tem espacos extras
3. Criar novo bot se necessario

### Erro: "Chat not found"

**Problema:** Chat ID invalido

**Solucao:**
1. Verificar se enviou mensagem para o bot ANTES de pegar o ID
2. Usar `/start` no bot
3. Tentar novamente obter ID via API

### Mensagem nao chega

**Problema:** Bot nao tem permissao para enviar

**Solucao:**
1. Enviar `/start` para o bot
2. Verificar se bot nao foi bloqueado
3. Verificar se chat_id esta correto

---

## Alertas Automaticos

### Quando sao enviados?

1. **Position Opened:** Quando nova posicao e aberta
2. **Position Closed:** Quando posicao e fechada
3. **Trailing Activated:** Quando trailing stop e ativado (lucro > 3%)
4. **Risk Alert:** Quando distancia para liquidacao < 10%
5. **Daily Summary:** Todo dia as 23:59

### Como desabilitar alertas especificos?

```powershell
# Editar config
$config = Get-Content config\telegram.json | ConvertFrom-Json

# Desabilitar trailing alerts
$config.alerts.trailing_activated = $false

# Salvar
$config | ConvertTo-Json -Depth 10 | Out-File config\telegram.json
```

### Como desabilitar completamente?

```powershell
# Editar config
$config = Get-Content config\telegram.json | ConvertFrom-Json

# Desabilitar Telegram
$config.enabled = $false

# Salvar
$config | ConvertTo-Json -Depth 10 | Out-File config\telegram.json
```

---

## Quiet Hours (Opcional)

Para nao receber alertas durante a noite:

```json
{
  "enabled": true,
  "bot_token": "...",
  "chat_id": "...",
  "alerts": { ... },
  "quiet_hours": {
    "enabled": true,
    "start": "22:00",
    "end": "08:00"
  }
}
```

**Nota:** Alertas criticos (risk alerts) sempre sao enviados, mesmo em quiet hours.

---

## Comandos Uteis

### Testar Conexao
```powershell
. ".\agents\lib_telegram.ps1"
Telegram-SendMessage -Message "Test"
```

### Enviar Alerta Manual
```powershell
Telegram-SendRiskAlert -Alert @{
    market = "BNBUSDT"
    type = "High Risk"
    severity = "WARNING"
    details = "Distance to liquidation < 10%"
    current_price = 640.00
    liq_price = 630.00
    distance_pct = 1.56
    action = "Add margin or close position"
}
```

### Enviar Resumo Diario Manual
```powershell
Telegram-SendDailySummary -Summary @{
    trades_count = 3
    wins = 2
    losses = 1
    win_rate = 66.7
    daily_pnl = 5.42
    daily_pnl_pct = 0.2
    total_pnl = -607.30
    open_positions = 1
    capital = 2757.93
    best_trade = 3.50
    worst_trade = 1.20
}
```

---

## Seguranca

### Proteger Token

**NUNCA** compartilhe o bot token publicamente!

```powershell
# Adicionar ao .gitignore
echo "config/telegram.json" >> .gitignore
```

### Revogar Token

Se token foi exposto:

1. Abrir @BotFather
2. Enviar `/mybots`
3. Selecionar bot
4. Clicar em "API Token"
5. Clicar em "Revoke current token"
6. Copiar novo token
7. Atualizar `config/telegram.json`

---

## Conclusao

✅ Bot criado
✅ Chat ID obtido
✅ Config atualizado
✅ Testes realizados
✅ Alertas funcionando

**ManuHeadFund agora envia alertas automaticos via Telegram!**

---

**Data:** 2026-05-23
**Status:** ✅ COMPLETO
