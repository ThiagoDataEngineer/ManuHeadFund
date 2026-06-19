# GitHub Token Setup — 2 minutos

## 🔑 Criar Personal Access Token

### Passo 1: GitHub Settings
1. Vai para: https://github.com/settings/tokens
2. Clique: **Generate new token (classic)**

### Passo 2: Configure Token
- **Token name**: `ManuHeadFund-Actions`
- **Expiration**: 30 days (ou mais)
- **Scopes** (marque apenas):
  - ✓ `repo` (Full control of private repositories)
  - ✓ `workflow` (Update GitHub Action workflows)
  - ✓ `admin:org_hook` (Full control of organization hooks)

### Passo 3: Generate
- Clique: **Generate token**
- Copie o token (você não vai conseguir ver novamente)

---

## 🚀 Usar Token para Setup

### Opção 1: PowerShell (Recomendado)

```powershell
# Set o token
$env:GITHUB_TOKEN = "ghp_... (cole aqui)"

# Execute o setup
pwsh scripts/setup_github_secrets.ps1
```

### Opção 2: Python (com PyNaCl)

```bash
pip install PyNaCl
$env:GITHUB_TOKEN = "ghp_..."
python3 scripts/setup_github_secrets.py
```

### Opção 3: GitHub CLI

```bash
gh auth login
# Selecione: GitHub.com
# Selecione: HTTPS
# Autentique

pwsh scripts/setup_github_secrets.ps1
```

---

## ✅ Verificar

Após completar:

```powershell
gh secret list -R ThiagoDataEngineer/ManuHeadFund
```

Deve ver:
```
SUPABASE_URL              Created at 2026-06-19
SUPABASE_SERVICE_KEY      Created at 2026-06-19
```

---

## 🔒 Segurança

- Token é **temporário** (30 dias)
- Pode **revogar** a qualquer momento
- GitHub **não mostra** o valor após criação
- Use `$env:GITHUB_TOKEN` (não commit em código)

---

## 🎯 Próximo Passo

Após setup:
```bash
git push origin main
```

GitHub Actions roda automaticamente:
- Hourly Auto-Calibration
- Chart Gate ativo
- Supabase sincronizado

**Sistema 24/7 cloud. Zero manual maintenance.**
