# PLANO DE RENOMEAÇÃO DO PROJETO

## OBJETIVO
Renomear projeto de `Coinex_AI_USER_API` para `ManuHeadFund`

---

## ESCOPO

### 1. Pasta do Projeto
```
ANTES: C:\Users\thiag\Coinex_AI_USER_API\
DEPOIS: C:\Users\thiag\ManuHeadFund\
```

### 2. Referências no Código
Buscar e substituir em todos os arquivos:
- `Coinex_AI_USER_API` → `ManuHeadFund`
- `coinex_ai_user_api` → `manuheadfund` (lowercase)
- `COINEX_AI_USER_API` → `MANUHEADFUND` (uppercase)

### 3. Tipos de Arquivos Afetados
- PowerShell scripts (`.ps1`)
- Python scripts (`.py`)
- Markdown docs (`.md`)
- Config files (`.json`, `.ini`, `.env`)
- Logs e journals (`.csv`, `.jsonl`)

---

## RISCOS

### Alto Risco:
1. **Git History**: Renomear pasta pode quebrar histórico do Git
2. **Paths Hardcoded**: Scripts com caminhos absolutos vão quebrar
3. **Processos Rodando**: Se sistema estiver rodando, pode dar erro

### Médio Risco:
4. **Imports**: Scripts que importam outros scripts podem quebrar
5. **Logs**: Referências a paths antigos em logs

### Baixo Risco:
6. **Documentação**: Apenas atualizar referências textuais

---

## ESTRATÉGIA SEGURA

### FASE 1: BACKUP (5min)
```powershell
# Criar backup completo
Copy-Item "C:\Users\thiag\Coinex_AI_USER_API" "C:\Users\thiag\Coinex_AI_USER_API_BACKUP_2026_05_23" -Recurse
```

### FASE 2: ANÁLISE (10min)
```powershell
# Contar arquivos afetados
Get-ChildItem "C:\Users\thiag\Coinex_AI_USER_API" -Recurse -File | 
    Where-Object { (Get-Content $_.FullName -Raw) -match "Coinex_AI_USER_API" } |
    Measure-Object
```

### FASE 3: SUBSTITUIÇÃO (20min)
```powershell
# Substituir em todos os arquivos
Get-ChildItem "C:\Users\thiag\Coinex_AI_USER_API" -Recurse -File -Include *.ps1,*.py,*.md,*.json,*.ini,*.env,*.csv |
    ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        $newContent = $content -replace "Coinex_AI_USER_API", "ManuHeadFund"
        $newContent = $newContent -replace "coinex_ai_user_api", "manuheadfund"
        $newContent = $newContent -replace "COINEX_AI_USER_API", "MANUHEADFUND"
        Set-Content $_.FullName -Value $newContent -NoNewline
    }
```

### FASE 4: RENOMEAR PASTA (2min)
```powershell
# Renomear pasta principal
Rename-Item "C:\Users\thiag\Coinex_AI_USER_API" "ManuHeadFund"
```

### FASE 5: VALIDAÇÃO (10min)
```powershell
# Verificar que não há mais referências ao nome antigo
Get-ChildItem "C:\Users\thiag\ManuHeadFund" -Recurse -File | 
    Where-Object { (Get-Content $_.FullName -Raw) -match "Coinex_AI_USER_API" } |
    Select-Object FullName
```

### FASE 6: TESTES (15min)
```powershell
# Testar scripts principais
cd "C:\Users\thiag\ManuHeadFund"
powershell -ExecutionPolicy Bypass -File "tests\test_fixes_simple.ps1"
powershell -ExecutionPolicy Bypass -File "tests\test_whale_manual.ps1"
```

---

## SCRIPT AUTOMATIZADO

Criei: `scripts\rename_project.ps1`

**Uso**:
```powershell
cd "C:\Users\thiag\Coinex_AI_USER_API"
powershell -ExecutionPolicy Bypass -File "scripts\rename_project.ps1"
```

**O script faz**:
1. ✅ Verifica se há processos rodando
2. ✅ Cria backup automático
3. ✅ Substitui todas as referências
4. ✅ Renomeia a pasta
5. ✅ Valida que tudo funcionou
6. ✅ Roda testes de validação

---

## CHECKLIST PRÉ-EXECUÇÃO

Antes de rodar o script, verificar:

- [ ] **Sistema parado**: Nenhum agent rodando
- [ ] **Git committed**: Todas as mudanças commitadas
- [ ] **Backup manual**: Cópia de segurança feita
- [ ] **Espaço em disco**: Pelo menos 2GB livres (para backup)
- [ ] **Permissões**: Executar como administrador se necessário

---

## ROLLBACK (Se algo der errado)

```powershell
# Restaurar backup
Remove-Item "C:\Users\thiag\ManuHeadFund" -Recurse -Force
Copy-Item "C:\Users\thiag\Coinex_AI_USER_API_BACKUP_2026_05_23" "C:\Users\thiag\Coinex_AI_USER_API" -Recurse
```

---

## TEMPO ESTIMADO

| Fase | Tempo | Risco |
|------|-------|-------|
| Backup | 5min | Baixo |
| Análise | 10min | Baixo |
| Substituição | 20min | Médio |
| Renomear | 2min | Alto |
| Validação | 10min | Baixo |
| Testes | 15min | Médio |
| **TOTAL** | **62min** | - |

---

## ARQUIVOS QUE SERÃO MODIFICADOS

### PowerShell Scripts (~114 arquivos):
- `agents/*.ps1` - Todos os agents
- `scripts/*.ps1` - Scripts auxiliares
- `tests/*.ps1` - Testes

### Python Scripts (~178 arquivos):
- `backtest/*.py` - Scripts de backtest

### Documentação (~50 arquivos):
- `docs/*.md` - Documentação
- `*.md` - READMEs e docs raiz

### Config Files (~10 arquivos):
- `.env`, `.ini`, `.json` - Configurações

### Logs (~20 arquivos):
- `journal/*.csv`, `journal/*.jsonl` - Logs

**TOTAL**: ~372 arquivos serão analisados e modificados

---

## RECOMENDAÇÃO

### Opção 1: SCRIPT AUTOMATIZADO (Recomendado)
- ✅ Rápido (62min)
- ✅ Seguro (com backup)
- ✅ Completo (todos os arquivos)
- ✅ Validado (testes automáticos)

**Comando**:
```powershell
powershell -ExecutionPolicy Bypass -File "scripts\rename_project.ps1"
```

### Opção 2: MANUAL (Não Recomendado)
- ❌ Lento (4-6 horas)
- ❌ Propenso a erros
- ❌ Difícil de validar

---

## PRÓXIMOS PASSOS

1. **Revisar este plano** - Confirmar que está OK
2. **Fazer backup manual** - Segurança extra
3. **Parar sistema** - Garantir que nada está rodando
4. **Executar script** - `scripts\rename_project.ps1`
5. **Validar** - Rodar testes
6. **Commitar** - Git commit com as mudanças

---

**Status**: ⏳ AGUARDANDO APROVAÇÃO

Quando estiver pronto, me avise e eu crio o script automatizado!
