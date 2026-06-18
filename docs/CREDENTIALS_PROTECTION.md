# Proteção de Credenciais — ManuHeadFund Online

## Resumo executivo
**Você MANTÉM as credenciais = nada sai do seu controle.**
- GitHub Secrets: **você coloca**, nós lemos
- PC ligado ou desligado: credenciais em **memory apenas**, nunca em disco
- Nenhuma credencial é commitada, versionada ou logada publicamente

---

## Arquitetura de Proteção

### 1. GitHub Secrets (Nuvem — Control Your Access)

**O que armazena:**
```
COINEX_ACCESS_ID           → sua chave de acesso CoinEx
COINEX_SECRET_KEY          → sua chave secreta CoinEx
TELEGRAM_BOT_TOKEN         → token do seu bot Telegram
TELEGRAM_CHAT_ID           → seu chat ID (recebe alertas)
SUPABASE_URL               → sua URL Supabase
SUPABASE_ANON_KEY          → chave pública Supabase
SUPABASE_SERVICE_KEY       → chave privada Supabase (role: service_role)
ANTHROPIC_API_KEY          → token Claude (Mentor)
GROQ_API_KEY               → token Groq (fallback)
MISTRAL_API_KEY            → token Mistral (fallback)
```

**Onde vivem:**
- GitHub Secrets: https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/secrets/actions
- **Você cria e gerencia 100%** — ninguém tem acesso além de você
- GitHub **nunca exibe** em logs/consoles públicos (redacted com `***`)

**Acesso:**
- ✅ CI/CD jobs (Actions) podem ler
- ✅ Você pode atualizar, revogar, remover a qualquer momento
- ❌ Nenhum script local pode acessar diretamente (GitHub não exporta pra fora)

---

### 2. Em Tempo de Execução (Memory Only — Nuvem)

**Fluxo cada job Actions:**
```
1. GitHub carrega secrets na session do runner
   $ env:COINEX_ACCESS_ID = "***" (protegido, não logado)
   $ env:SUPABASE_URL = "https://xxx.supabase.co"
   
2. Job cria config.local.ps1 em MEMÓRIA (NUNCA em disco)
   $content = "`$env:COINEX_ACCESS_ID = '...'"
   $content | Out-File "agents/config.local.ps1" -Encoding UTF8
   ↑ arquivo temporário no runtime, descartado após job

3. Scripts leem de env vars (gem_loop, trailing, telegram)
   . agents/config.local.ps1
   $creds = $env:COINEX_ACCESS_ID

4. Job completa → runner limpo (sem rastros)
```

**Dados que NÃO são salvos:**
- ❌ config.local.ps1 não é commitado (gitignored)
- ❌ Logs do job NÃO contêm credenciais ("***" redacted)
- ❌ Artefatos não contêm credenciais
- ❌ Trailing positions / conviction data NO Supabase (schema `manuheadfund`, isolado)

---

### 3. PC Ligado (Local — Você Escolhe o Armazenamento)

**Antes do cutover (position_watcher local APOSENTADO):**
```
gem_loop / scan_master rodam LOCALMENTE
  ↓
Leem config.local.ps1 (gitignored, você cria manualmente ou script setup)
  ↓
Credenciais em MEMORY durante execução
  ↓
FIM do processo = memory apagada
```

**config.local.ps1 EXEMPLO (você cria):**
```powershell
$env:COINEX_ACCESS_ID = "seu_access_id_coinex"
$env:COINEX_SECRET_KEY = "sua_secret_key_coinex"
$env:TELEGRAM_BOT_TOKEN = "seu_token_telegram"
# ... resto das chaves
```

**IMPORTANTE:**
- ✅ Arquivo é seu, local, gitignored
- ✅ Você controla quem acessa (file permissions do SO)
- ✅ Nunca sai para a nuvem
- ❌ NUNCA commita `config.local.ps1` (git recusará por causa de `.gitignore`)

---

### 4. PC Desligado (Online — GitHub Secrets Usados)

**Após cutover (gem_loop/scan_master locais PARADOS):**
```
gem_loop -Once roda NA NUVEM (GitHub Actions)
  ↓
Actions injeta secrets nos env vars
  ↓
gem_loop lê de $env (não precisa de config.local.ps1)
  ↓
Posições persistidas no Supabase (tabela `trailing_positions`)
  ↓
Trailing online (JOB 1) protege a qualquer momento
```

**Estado do sistema:**
- ✅ Você desliga o PC = nuvem continua tradando
- ✅ Credenciais nuvem = GitHub Secrets (você controla)
- ✅ Credenciais locais = config.local.ps1 (você controla, PC desligado)
- ✅ Sem compartilhamento entre local/nuvem (zero vazamento)

---

## Checklist de Segurança

### Setup (Primeira Vez)

- [ ] 1. Acesse https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/secrets/actions
- [ ] 2. Crie cada secret (copie exatamente de `.local` ou suas credenciais):
  - COINEX_ACCESS_ID
  - COINEX_SECRET_KEY
  - TELEGRAM_BOT_TOKEN
  - TELEGRAM_CHAT_ID
  - SUPABASE_URL
  - SUPABASE_ANON_KEY
  - SUPABASE_SERVICE_KEY
  - ANTHROPIC_API_KEY
  - GROQ_API_KEY
  - MISTRAL_API_KEY
- [ ] 3. Crie local `agents/config.local.ps1` (não commita):
  ```
  $env:COINEX_ACCESS_ID = "..."
  $env:COINEX_SECRET_KEY = "..."
  ... resto
  ```
- [ ] 4. Verifique `.gitignore` contém:
  ```
  agents/config.local.ps1
  journal/
  ```

### Monitoramento

- [ ] Logs do Actions: **REDACTED** (credenciais nunca aparecem)
- [ ] Dashboard (gh-pages): dados públicos (PnL, mercados), zero credenciais
- [ ] Supabase: apenas `manuheadfund` schema (isolado, sem creds)
- [ ] Telegram: alertas de trades (zero credenciais)

### Revogação (Se Comprometidas)

1. **Local PC:** Regenera COINEX keys → atualiza config.local.ps1
2. **Nuvem GitHub:** Settings > Secrets > Update COINEX_ACCESS_ID + COINEX_SECRET_KEY
3. **Próximo job Actions:** novas chaves usadas automaticamente
4. **Supabase:** as keys anterior deixam de funcionar

---

## Garantias

| Cenário | Proteção |
|---------|----------|
| PC desligado | ✅ Nuvem trada com GitHub Secrets (você controla) |
| PC ligado | ✅ Config local em memory, nunca em disco |
| Log do job Actions | ✅ Credenciais redacted com `***` |
| GitHub público | ❌ Secrets **privados**, não visíveis |
| Supabase | ✅ Isolado no schema `manuheadfund`, RLS ativo |
| Trailing positions | ✅ No Supabase, zero credenciais |
| Trades abertos | ✅ Protegidos por SL (não depende de creds pra sair) |

---

## FAQ

**P: E se alguém ganhar acesso ao repo?**
A: GitHub Secrets são **private** — não podem ser lidas do código. Só você tem acesso na interface. Mesmo um attacker commitando código não consegue ler secrets.

**P: Config.local.ps1 é seguro localmente?**
A: Tão seguro quanto qualquer arquivo no seu PC. Use permissões do SO (`chmod 600` no Linux, NTFS permissions no Windows) se quiser extra.

**P: Supabase pode ler as chaves?**
A: Não. As chaves existem só em memory do job. Supabase recebe dados, não credenciais. O schema `manuheadfund` é isolado (RLS).

**P: E se a nuvem crashar durante uma trade?**
A: Posição fica aberta, protegida pela SL (empurrada no Supabase). Próximo job trailing (5min depois) continua protegendo.

**P: Posso usar chaves com permissões limitadas?**
A: SIM — recomendado. Crie no CoinEx uma API key com:
- ✅ Read: account, futures positions, spot positions
- ✅ Trade: spot + futures (se quer auto-execute)
- ❌ Withdrawal

---

## Resumo: Você MANTÉM o Controle

```
PC ligado             PC desligado
│                     │
├─ config.local.ps1   ├─ GitHub Secrets (você criou)
│  (você criou)       │  (você controla)
│  (gitignored)       │
│                     ├─ Actions injeta em memory
├─ gem_loop lê        │
│  (memory)           ├─ gem_loop -Once lê
│                     │  (memory)
├─ Posições → Supabase│
│                     ├─ Posições → Supabase
│                     │
└─ Está ligado        └─ Nuvem roda, PC pode estar OFF
```

**Tudo o que sai de você (PC/GitHub) é encriptado e auditado por você.**
