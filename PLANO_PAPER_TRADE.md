# 📋 Paper Trade — Status Atual

**Data:** 2026-05-25  
**BTC:** $77,577 (abaixo SMA200 $80,447 = **regime BEAR**)

---

## 🚦 Sistema bloqueando longs (corretamente)

```
[orchestrator.ps1:117]
if ($btc.regime -eq "BEAR") {
    Write-Host "ABORTAR: BTC abaixo SMA200 (BEAR). Pausando novas longs."
    return
}
```

Esse é um **macro circuit breaker** baseado em Stan Druckenmiller / Paul Tudor Jones:
> "Não fight the trend. Em bear market macro, evitar longs."

**É a coisa CERTA estar bloqueando agora.**

---

## ✅ O que JÁ FUNCIONA

| Item | Status |
|------|--------|
| Mentor LLM (Anthropic + Groq + Gemini) | ✅ corrigido |
| TLS/DNS | ✅ corrigido |
| Trailing stops | ✅ ativo (BNB Phase 1) |
| Risk monitoring | ✅ ativo |
| Cascade Mentor | ✅ funcionando |

---

## 🎯 3 Caminhos para Paper Trade Real

### **CAMINHO A: Esperar BTC virar BULL** (recomendado)
- Sistema vai destravar sozinho quando BTC > SMA200
- Hoje: BTC $77.5k, SMA200 $80.4k → precisa subir ~3.7%
- Pode levar dias/semanas
- **Mais seguro, alinhado com macro**

### **CAMINHO B: Habilitar SHORTs**
- Orchestrator atual só procura LONG
- Em bear market, SHORT é a direção certa
- Já temos `short_scanner.ps1` rodando 1x/h no GitHub Actions
- **Setups de short detectados**: ZECUSDT, BCHUSDT, SUIUSDT, XRPUSDT, PENDLEUSDT, SKYUSDT
- Falta: orchestrator decidir LONG vs SHORT baseado em direction_bias

### **CAMINHO C: Bypass do macro filter para teste**
- Adicionar flag `BYPASS_BTC_REGIME=true` em config.local.ps1
- Permite paper trades durante BEAR para validar pipeline
- ⚠️ **Não recomendo para LIVE** — só para teste/calibração

---

## 💡 Recomendação

**Combinar A + B:**

1. **Agora**: Manter sistema bloqueando longs (correto)
2. **Habilitar shorts no orchestrator** — usa `Get-DirectionBias` que já existe no scan_master
3. **Quando BTC virar BULL**: longs destravam automaticamente
4. **Tori Proximity já roda**: estratégia validada que funciona em ambos os regimes

---

## 📊 Trades Possíveis AGORA (sem desabilitar guards)

### Via short_scanner (já rodando 1x/h)
Setups detectados nas últimas 24h: ZEC, BCH, SUI, XRP, PENDLE, SKY

### Via Tori Proximity (validada +77.6pp/ano, roda 15min)
11 markets monitorados, alertas via Telegram quando setup ripe

### Via posições já abertas
Trailing stops cuidam de UNI/LINK/BNB/SOL automaticamente
