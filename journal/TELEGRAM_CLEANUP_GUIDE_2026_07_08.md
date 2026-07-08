# Telegram Cleanup Guide — Remove Spam, Keep Essential

**Objetivo:** Reduzir de 100+ msg/dia → ~10-15 msg/dia  
**Escopo:** Remover bloqueios, info redundante, success cases

---

## 📋 Checklist de Linhas a Remover/Modificar

### gem_executor.ps1 (22 sends → 6 essenciais)

**✂️ REMOVER completamente:**

```powershell
Line 548  | try { Send-TelegramAlert -Message "*GEM BLOQUEADO* -- $mkt`nMotivo: CoinEx..." }
         | Motivo: Já logado, não impacta usuário

Line 594  | try { Send-TelegramAlert -Message "🚫 GEM bloqueado (cascata): $mkt leverage=..." }
         | Motivo: Muito frequente (3-5x/hora em bear), automático

Line 603  | try { Send-TelegramAlert -Message "🚫 GEM bloqueado (cascata): $mkt tem..." }
         | Motivo: Redundante com line 594

Line 624  | try { Send-TelegramAlert -Message "GEM bloqueado: $($safety.reason)..." }
         | Motivo: 10-15 msg/ciclo, automático (segurança funcionando)

Line 633  | try { Send-TelegramAlert -Message "GEM aviso: $($safety.telegram_message)" }
         | Motivo: Warning, não crítico

Line 659  | try { Send-TelegramAlert -Message "GEM bloqueado ${mkt}: $($cap.reason)..." }
         | Motivo: 5+ msg/ciclo em bear, automático

Line 778  | try { Send-TelegramAlert -Message "GEM bloqueado ${mkt}: cenario BTC=..." }
         | Motivo: 20+ msg/ciclo quando BEAR (regime conhecida)

Line 842  | try { Send-TelegramAlert -Message "GEM bloqueado: $mkt -- Get-ToriTrendlineSignal..." }
         | ⚠️ MANTER — é erro crítico de carregamento

Line 929  | try { Send-TelegramAlert -Message "CONVICCAO venceu Tori: $mkt..." }
         | Motivo: Success case, não necessário

Line 941  | try { Send-TelegramAlert -Message "GEM bloqueado por Tori ($tori_signal)..." }
         | Motivo: 30-50 msg/ciclo em BEAR (tori rejeitando tudo)

Line 1231 | try { Send-TelegramAlert -Message "*GEM BLOQUEADO* -- $mkt..." }
         | Motivo: Consolidado redundante

Line 1288 | try { Send-TelegramAlert -Message "*GEM BLOQUEADO* -- $mkt`nMotivo: Multi-TF..." }
         | Motivo: Informativo, não crítico

Line 1382 | try { Send-TelegramAlert -Message "✅ PROTEÇÃO ATIVA: $mkt SL=..." }
         | Motivo: Success case

Line 1450 | Send-TelegramAlert -Message (Format-TgAutoAnalysis -Analysis $autoAnalysis)
         | Motivo: Análise automática, pedantic
```

**✅ MANTER (essenciais):**

```powershell
Line 863  | try { Send-TelegramAlert -Message "GEM bloqueado por Tori (error): $mkt..." }
         | Motivo: Tori crash = problema crítico

Line 1251 | try { Send-TelegramAlert -Message $blockMsg }
         | Motivo: TP validation falhou = bug API

Line 1260 | Send-TelegramAlert -Message $preMsg
         | ✅ TRADE OPENED — ESSENCIAL

Line 1385 | try { Send-TelegramAlert -Message "🚨 CRÍTICO: SL/TP FALHOU em $mkt..." }
         | ✅ CRÍTICO — Posição sem proteção!

Line 1389 | try { Send-TelegramAlert -Message "🚨 CRÍTICO: $mkt ABERTO SEM SL/TP..." }
         | ✅ CRÍTICO — Lib não carregou

Line 1416 | Send-TelegramAlert -Message (Format-TgGemExecuted...)
         | ✅ TRADE RECAP — manter

Line 1437 | Send-TelegramAlert -Message (Format-TgTradeOpenedHighlight...)
         | ✅ Visual confirmation — manter
```

---

## 📊 lib_trailing.ps1 (3 sends)

**Remover:**
- Nenhum — trailing é crítico (SL hit, TP hit, trailing gain)

**Manter:**
- Todos os 3 (STOP, TP, TRAILING GAIN)

---

## 🔄 Implementação

### Opção 1: Quick (15 min) — Comment out lines

Abrir gem_executor.ps1:
1. Navegar para linha 548
2. Comentar: `# try { Send-TelegramAlert -Message... } catch {}`
3. Repetir para 12 linhas listadas acima

### Opção 2: Proper (1 hora) — Replace com lib_telegram_essential_alerts

```powershell
# Em gem_executor.ps1, seção de EXECUTANDO GEM (linha ~1260):

# ANTES:
Send-TelegramAlert -Message $preMsg | Out-Null

# DEPOIS:
if (Get-Command Send-TradeOpenAlert -ErrorAction SilentlyContinue) {
    Send-TradeOpenAlert -Market $mkt -Direction $direction `
        -Entry $price -Stop $stop_price -Target $tgt_price `
        -SizeUSD $usd_size -MarketType $marketType
}
```

---

## ✅ Checklist

- [ ] Backup gem_executor.ps1
- [ ] Remove 12 Send-TelegramAlert calls (comment or delete)
- [ ] Test: Run 1 scan cycle, verify Telegram quiet
- [ ] Verify: Trade opened → message sent
- [ ] Verify: Trade closed → message sent
- [ ] Verify: Trailing gain → message sent
- [ ] Commit: "refactor: Remove telegram spam, keep essential alerts only"

---

## 📈 Esperado Pós-Cleanup

**Antes:** 100+ msg/dia
```
15:00 GEM bloqueado ADAUSDT (exposure)
15:01 GEM bloqueado BONK (safety)
15:02 GEM bloqueado DOGE (cenario)
15:03 GEM bloqueado PEPE (tori skip)
... (100+ bloqueios)
```

**Depois:** 10-15 msg/dia
```
15:05 🟢 ENTRADA — BTCUSDT 📈
      Entry: 63000 / Stop: 59000 / Alvo: 70000
      Capital: $50 USDT

15:45 ✅ TP BATIDO — BTCUSDT
      Entry: 63000 / Exit: 70000
      Lucro: +$55.55 USD (+88%)
      Tempo: 40min

16:00 📈 GANHO GARANTIDO — ETHUSDT
      Lucro atual: +$42.10 USD (+12%)
      SL movido para: 1820 (breakeven + buffer)
```

---

**Status:** Pronto pra implementar. Quer quick (comment out) ou proper (lib_essential)?

