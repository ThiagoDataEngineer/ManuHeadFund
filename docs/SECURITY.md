# SECURITY.md — Padroes + Checklist

> **Doc publico (commitavel).** Lista CONVENÇÕES, não secrets.
> Secrets vivem em `agents/config.local.ps1` (gitignored) ou env vars do shell.

---

## Padrão de credenciais

### Onde os secrets DEVEM ficar

```
agents/config.local.ps1        ← gitignored, fonte única
   ↓ (set $env:*)
$env:COINEX_ACCESS_ID
$env:COINEX_SECRET_KEY
$env:ANTHROPIC_API_KEY
$env:TELEGRAM_BOT_TOKEN
$env:TELEGRAM_CHAT_ID
   ↓ (consumido por)
agents/config.ps1 + lib_coinex.ps1 + lib_telegram.ps1 + lib_claude.ps1
```

### Onde NUNCA podem aparecer

| Arquivo | Por quê |
|---|---|
| Qualquer `.ps1` ou `.py` em commits | Vai pro git history |
| `*.md` em commits (exceto CREDENTIALS.md gitignored) | Texto público |
| `journal/*.json` ou `*.csv` | Outputs podem ser shared |
| `logs/*.log` | Pode ir pra suporte / debug |
| Tests `.Tests.ps1` ou `test_*.py` | CI |
| Prints/`Write-Host` em scripts | Aparecem em terminal/logs |

### Pattern correto em código

```powershell
# ✅ Bom
$accessId  = $env:COINEX_ACCESS_ID
$secretKey = $env:COINEX_SECRET_KEY
if (-not $accessId -or -not $secretKey) {
    throw "Credenciais nao definidas. Carregar config.local.ps1 primeiro."
}

# ❌ NUNCA
$accessId = "F028C096..."   # hardcoded = leak
```

```python
# ✅ Bom
import os
api_key = os.environ.get("ANTHROPIC_API_KEY")
if not api_key:
    raise RuntimeError("ANTHROPIC_API_KEY nao definido no ambiente")

# ❌ NUNCA
api_key = "sk-ant-api03-..."
```

---

## Checklist de auditoria periódica

Rodar **mensalmente** ou antes de qualquer push pro remote:

```bash
# 1. Grep por padrões comuns de keys (devem aparecer SÓ em config.local.ps1)
grep -rE "sk-ant-api[0-9]+" --include="*.ps1" --include="*.py" --include="*.md" .
grep -rE "[A-F0-9]{32}" --include="*.ps1" --include="*.py" --include="*.md" . | grep -v _legacy
grep -rE "bot[0-9]+:[A-Za-z0-9_-]{30,}" --include="*.ps1" --include="*.py" --include="*.md" .

# 2. Verificar .gitignore cobre config.local.ps1
grep "config.local.ps1" .gitignore

# 3. Verificar CREDENTIALS.md ainda no .gitignore
grep "CREDENTIALS.md" .gitignore

# 4. Listar arquivos não-rastreados sensiveis
git status --ignored
```

---

## Surface de filesystem (alem do git)

**⚠️ B2 auditoria 2026-05-20 PM6+**: projeto **NAO eh git repo** (`Is a git repository: false`). `.gitignore` patterns (`*.env`, `agents/config.local.ps1`) sao **inertes** sem `.git/`. Surface real de exposicao:

| Vetor | Risco | Mitigacao |
|---|---|---|
| OneDrive / Dropbox sync | Auto-upload de qualquer arquivo na pasta sincronizada | Verificar `C:\Users\thiag\Coinex_AI_USER_API\` NAO esta em pasta sync |
| Windows Backup automatico | Snapshots periodicos incluem secrets | Disable backup pra essa pasta (Control Panel) |
| Share de tela / screen recording | Visual leak em demos | Fechar editor com `config.local.ps1` antes de share |
| Git accidental (futuro) | Se algum dia o user rodar `git init` + `git add .` | `.gitignore` ja protege; **manter os patterns mesmo sem repo** |
| `backtest/.env` | RFC: nao deve ter SERVICE_KEY (RLS bypass) | B2 fix 2026-05-20: removido — db.py:15 cai pra ANON_KEY |
| Backup duplicate | Cada secret em N lugares = N vetores | SSoT = `config.local.ps1`. Nunca duplicar em `.env*` |

**Defesa em profundidade futura (deferred)**:
1. Windows DPAPI: encriptar valores em `config.local.ps1` com `ConvertFrom-SecureString` + chave por usuario (decrypt so na maquina do user)
2. Pasta `C:\Users\thiag\.secrets\` fora do project root + symlink (excluido de sync por design)
3. Hardware key (YubiKey / TPM-backed) pra creds mais sensiveis

**Por hora (2026-05-20)**: capital LIVE $2762 + permissoes withdraw na CoinEx primary key = risco real, mas defesa atual (gitignore + lock visual + manual hygiene) eh **suficiente pra esse capital level**. Reavaliar quando capital > $10K.

---

## Histórico de incidentes

### 2026-05-19 (3o incidente, mesmo dia) — AI grep -n expos Hey key

**Achado:** Assistente AI rodou `grep -n "COINEX_ACCESS_ID" config.local.ps1` durante debug.
`-n` retorna conteúdo da linha → Access ID + Secret Key da "Hey" expostos no transcript.

**Remediação:** key Hey revogada + recriada. Doc atualizada com regra dura abaixo.

### 🚨 REGRA DURA pra AI assistant — não ler config.local.ps1

- **NUNCA** rodar `grep -n`, `cat`, `head`, `tail`, `Read`, `Get-Content` em `agents/config.local.ps1`
- **NUNCA** dot-source no terminal expondo output
- Patterns seguros:
  - Contar matches: `grep -c PATTERN file` (count only)
  - Verificar var set sem expor valor:
    ```powershell
    if ($env:COINEX_ACCESS_ID) { "set ($($env:COINEX_ACCESS_ID.Length) chars)" } else { "not set" }
    ```
  - Comparar prefixo (sem expor full): `$env:VAR.Substring(0,4) + "..."`
- Se AI precisa modificar config.local.ps1, sugere ao usuário o patch e ele cola local

### 2026-05-19 (2o incidente) — User colou key "HOME" em chat

**Achado:** Tela CoinEx UI com novo Access ID + Secret Key foi colada literal no chat.

**Remediação:** key HOME revogada na hora, criada e nunca foi usada.

**Lição:** UI da CoinEx mostra valores apenas uma vez. Usuário tende a copiar tudo. Padrão seguro: copiar DIRETO do navegador pro editor (Ctrl+V no `config.local.ps1`), nunca passar por chat.

### 2026-05-19 (1o incidente) — Secret key read-only exposta

**Achado:** `trailing_stop.ps1` (linhas 2-3) e `trailing_short.ps1` (linhas 5-6) tinham:
- `$accessId = "A1F59D17..."` (read-only Access ID)
- `$secretKey = "CB4B8C5E..."` (read-only Secret Key)

**Risco:** baixo (read-only, sem permissão de trade/withdraw). Mas **fora do .gitignore**, ou seja: qualquer `git add .` levaria pro repo.

**Remediação aplicada (2026-05-19):**
1. ✅ Scrubada das duas scripts, migrado pra `$env:COINEX_ACCESS_ID/SECRET_KEY`
2. ✅ Throw clear error se env não setado
3. ✅ Plaintext no CREDENTIALS.md marcado pra revogar
4. ⏳ **PENDENTE:** revogar+regerar key na UI da CoinEx (responsabilidade do user)

**Lições:**
- Scripts standalone tendem a ter creds hardcoded por conveniência
- `.gitignore` resolve commit, mas NÃO resolve filesystem leak
- Adicionar `.secret`, `.key`, `*.env`, `agents/config.local.ps1` no .gitignore não basta — precisa GREP ATIVO

---

## Setup inicial para novos contribuidores

1. Copiar template:
   ```powershell
   # NOT a real file - apenas referência. Pedir ao owner.
   # agents/config.local.ps1.example
   $env:COINEX_ACCESS_ID    = "SEU_ACCESS_ID_AQUI"
   $env:COINEX_SECRET_KEY   = "SEU_SECRET_KEY_AQUI"
   $env:ANTHROPIC_API_KEY   = "sk-ant-api..."
   $env:TELEGRAM_BOT_TOKEN  = "1234567890:..."
   $env:TELEGRAM_CHAT_ID    = "..."
   ```
2. Salvar como `agents/config.local.ps1` (já gitignored)
3. No script de entrada (ex. `start_services.ps1`) sempre fazer:
   ```powershell
   . "$PSScriptRoot\agents\config.local.ps1"
   ```
4. Confirmar `git status` NÃO mostra `config.local.ps1`

---

## Práticas mínimas

- ✅ CoinEx API key principal: IP whitelist obrigatório quando tiver VPS
- ✅ Withdraw permission só na key principal, nunca em read-only
- ✅ Read-only key separada para exploração / VS Code
- ✅ Claude API key com spending limit configurado
- ✅ Telegram bot: chat_id allowlist hardcoded no `tg_listener.ps1` (`$ALLOWED_CHAT`)
- ⏳ Rotação trimestral das keys (calendário separado)
- ⏳ Backup offline encriptado das keys (KeePass / similar)

---

## Referências

- [CREDENTIALS.md](CREDENTIALS.md) — valores reais (gitignored)
- [docs/PROJECT_MAP.md](docs/PROJECT_MAP.md) — onde tudo vive
- [.gitignore](.gitignore) — patterns protegidos
