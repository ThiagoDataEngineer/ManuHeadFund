# GitHub Secrets Setup — Cloud-Only Deployment

## ✅ Credenciais Encontradas (config.local.ps1)

```
SUPABASE_URL:         https://urcqtpklpfyvizcgcsia.supabase.co
SUPABASE_SERVICE_KEY: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVyY3F0cGtscGZ5dml6Y2djc2lhIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NjU4MDUxNiwiZXhwIjoyMDkyMTU2NTE2fQ.wrZnVH5CPX716Q8csH7MGQYhIG-xitkYAIKAPk9KiDE
```

---

## 🚀 Setup via GitHub Web UI

### Passo 1: Abra Repository Settings
1. GitHub → ThiagoDataEngineer/ManuHeadFund
2. **Settings** tab
3. Esquerda: **Secrets and variables** → **Actions**

### Passo 2: Adicione SUPABASE_URL
1. Clique: **New repository secret**
2. Name: `SUPABASE_URL`
3. Secret: `https://urcqtpklpfyvizcgcsia.supabase.co`
4. Click: **Add secret**

### Passo 3: Adicione SUPABASE_SERVICE_KEY
1. Clique: **New repository secret**
2. Name: `SUPABASE_SERVICE_KEY`
3. Secret: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVyY3F0cGtscGZ5dml6Y2djc2lhIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NjU4MDUxNiwiZXhwIjoyMDkyMTU2NTE2fQ.wrZnVH5CPX716Q8csH7MGQYhIG-xitkYAIKAPk9KiDE`
4. Click: **Add secret**

### Passo 4: Verifique
Na página de Secrets, você deve ver:
```
✓ SUPABASE_URL
✓ SUPABASE_SERVICE_KEY
```

---

## 🔄 Alternativa: GitHub CLI

Se preferir via terminal:

```bash
gh auth login
gh secret set SUPABASE_URL --body "https://urcqtpklpfyvizcgcsia.supabase.co"
gh secret set SUPABASE_SERVICE_KEY --body "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVyY3F0cGtscGZ5dml6Y2djc2lhIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NjU4MDUxNiwiZXhwIjoyMDkyMTU2NTE2fQ.wrZnVH5CPX716Q8csH7MGQYhIG-xitkYAIKAPk9KiDE"
```

---

## ✅ Pronto!

Após adicionar secrets:

1. **Push código** para main:
   ```bash
   git push origin main
   ```

2. **GitHub Actions ativa**:
   - Actions tab
   - Veja: `Hourly Auto-Calibration` rodando
   - Cron: `0 * * * *` (toda hora)

3. **Monitor**:
   - Artifacts com `journal/daily_calibration.jsonl`
   - Supabase `regime_state` table atualizada

---

## 🔒 Segurança

- Secrets são **encrypted** no GitHub
- Nunca aparecem em logs
- Apenas usados em Actions
- config.local.ps1 permanece local (gitignored)

---

**Sistema rodando 100% cloud. Zero necessidade de máquina local.**
