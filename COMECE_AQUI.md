# 🚀 COMECE AQUI - Setup Rápido

## ⚡ 1 COMANDO PARA CONFIGURAR TUDO

### Execute este comando (clique direito → Executar como Administrador):
```
SETUP_COMPLETO_OCULTO_ADMIN.ps1
```

**OU** clique com botão direito no arquivo `SETUP_COMPLETO_OCULTO_ADMIN.ps1` e escolha **"Executar com PowerShell"** (vai pedir admin automaticamente).

---

## ✅ O que vai acontecer:

1. ✅ **Trailing Stop Monitor** → Configurado para rodar OCULTO (a cada 5 min)
2. ✅ **Dashboard HTML Update** → Configurado para rodar OCULTO (a cada 5 min)
3. ✅ **Dashboard HTML** → Abre automaticamente no navegador
4. ✅ **Atalho na Área de Trabalho** → Criado

---

## 📊 Depois do Setup:

### Você vai usar APENAS o Dashboard HTML no navegador!

**Abrir Dashboard**:
- Clique no atalho "CoinEx Dashboard" na área de trabalho
- OU abra: `dashboard\index.html`

**Dashboard atualiza sozinho a cada 5 minutos!**

---

## 🔇 PowerShell NÃO vai mais aparecer!

Todas as tasks rodam **OCULTAS** em background.

Você só vê o Dashboard HTML no navegador.

---

## 📝 Se precisar ver logs:

```powershell
Get-Content logs\trailing_stop_monitor.log -Tail 50
```

---

## 🛑 Se precisar desabilitar:

```powershell
# Desabilitar trailing stop
Disable-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor"

# Desabilitar update do dashboard
Disable-ScheduledTask -TaskName "CoinEx_Update_Dashboard_HTML"
```

---

## 🔄 Se precisar habilitar novamente:

```powershell
# Habilitar trailing stop
Enable-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor"

# Habilitar update do dashboard
Enable-ScheduledTask -TaskName "CoinEx_Update_Dashboard_HTML"
```

---

## ⚠️ IMPORTANTE: Proteger NEAR

Depois do setup, execute UMA VEZ:
```powershell
.\PROTECT_NEAR_NOW.ps1
```

Isso configura o stop loss da posição NEAR que está desprotegida.

---

## 🎯 Resumo:

1. Execute: `SETUP_COMPLETO_OCULTO_ADMIN.ps1` (como admin)
2. Dashboard abre no navegador
3. Deixe aberto (atualiza a cada 5 min)
4. PowerShell NÃO aparece mais!
5. Execute uma vez: `PROTECT_NEAR_NOW.ps1`

---

**COMECE AGORA: Clique direito em `SETUP_COMPLETO_OCULTO_ADMIN.ps1` → Executar com PowerShell** 🚀
