# 🔍 DIAGNÓSTICO - GITHUB ACTIONS FALHANDO

## ❌ PROBLEMA IDENTIFICADO

**Sintoma**: Risk Manager falhando no GitHub Actions quando computador desligado

**Mensagens de erro**:
```
GitHub Actions Falhou
Risk Manager teve erro.
Verifique os logs.
```

## 🔎 CAUSAS PROVÁVEIS

### 1. Configuração de Credenciais
O workflow cria um arquivo `config.local.ps1` mas pode não estar no formato correto.

### 2. Dependências Faltando
Scripts podem depender de funções que não estão sendo carregadas.

### 3. Paths Incorretos
PowerShell no Linux (GitHub Actions) usa paths diferentes do Windows.

### 4. Variáveis de Ambiente
As credenciais podem não estar sendo exportadas corretamente.

---

## 🔧 CORREÇÕES NECESSÁRIAS

Vou corrigir o workflow para funcionar corretamente no GitHub Actions.
