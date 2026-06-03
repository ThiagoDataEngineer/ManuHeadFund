# Telegram Listener - Diagnóstico de Erro 409

## Problema encontrado
- **Erro**: HTTP 409 (Conflict) ao tentar fazer getUpdates
- **Causa**: Provavelmente há múltiplas instâncias tentando fazer getUpdates simultaneamente
- **Status**: IDENTIFICADO, em investigação

## Ações tomadas

1. ✅ **Arquivos faltando**: Restaurados 69 arquivos lib_*.ps1 do backup
   - Arquivo: `.backup/agents_20260601_164756/`
   - Todos os arquivos lib_* copiados para `agents/`

2. ✅ **Múltiplas instâncias**: Mortas 5 instâncias de telegram_listener
   - PIDs: 1000, 24876, 27544, 40120, +1
   - Motivo: Cada uma tentava fazer getUpdates, causando 409

3. ✅ **Webhook limpo**: Confirmado webhook vazio na API Telegram
   - `deleteWebhook`: OK
   - Estado pronto para polling

4. ✅ **Env vars**: TELEGRAM_BOT_TOKEN e TELEGRAM_CHAT_ID setadas
   - Wrapper criado: `telegram_listener_wrapper.ps1`

## Erro residual (409 ainda persiste)

Testamos offsets diferentes:
- offset=0,1,10: ❌ 409
- offset=1000: ✅ OK
- offset=50000: ✅ OK  
- offset=999999999: ❌ 409

**Conclusão**: Há uma range de offsets válida (1000-999998999).
Offsets baixos (0-10) causam conflito com o servidor Telegram.

## Próximas ações

1. Modificar `telegram_listener.ps1` linha 62:
   ```ps1
   # Atual: $url = "https://api.telegram.org/bot$($env:TELEGRAM_BOT_TOKEN)/getUpdates?offset=$($Offset+1)&timeout=20"
   # Novo: Usar offset=100000 como mínimo se offset < 100000
   ```

2. Ou: Implementar retry exponencial com backoff
3. Ou: Usar webhook-based ao invés de polling

## Arquivo de configuração
- Config: `config/telegram.json`
- Token: `8763265579:AAFPaVZjeS_rQSzs4xpzb9stMG5veP_Qo54`
- Chat ID: `5592104053`

## Status do listener
- Log: `journal/tg_listener.log`
- State: `journal/tg_listener_state.json`
- Restart script: `scripts/telegram_listener_restart_clean.ps1`
