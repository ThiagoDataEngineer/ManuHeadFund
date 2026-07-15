# SPEC: FARO V3 na nuvem (job GitHub Actions) — reativação do detector pré-pump

> Escrita 2026-07-15 para implementação por agente executor. Âncoras referem-se
> ao commit `3f860b7`. Se linhas mudaram, buscar pelos textos-âncora.

## Contexto (por quê)

FARO V3 é o detector pré-pump do sistema (7 sinais: volume_plus, pattern_pro,
sentiment, whale_onchain, momentum, fingerprint_dna, entry_timing — 11 libs em
`agents/lib_faro_*.ps1`). Era daemon LOCAL via Task Scheduler
(`scripts/faro_v3_schedule.ps1`) — **morto desde que os daemons locais pararam**.
Zero presença em `.github/workflows/trading-pipeline.yml` (confirmado por grep).
Autópsia de 2026-07-15 nos pumps das últimas 24h (KAITO +19%, ZEC +11%, LIT +10%)
confirmou que as assinaturas pré-pump que o FARO detecta existem e são capturáveis.

Arquitetura (medida no código):
- `scripts/faro_v3_engine.ps1` (187 l): escaneia top gainers spot, pontua com as
  7 libs, grava candidatos em `journal/faro_v3_candidates.jsonl`.
- `scripts/faro_v3_entry.ps1` (157 l): lê candidatos **dos últimos 10 minutos**,
  coloca ordens FUTURES reais (`CoinEx-PlaceOrder` buy market) **com stopLoss
  (-8%) e takeProfit embutidos na ordem** (proteção exchange-side, sobrevive ao
  runner). Params: `-DryRun $false -CapitalPercent 0.01 -MaxPositions 5`.
- `scripts/faro_v3_manager.ps1`: gestão de posição — **NÃO será agendado**: os
  jobs cloud existentes (Trailing Stop Monitor, Position Risk Manager) já
  gerenciam TODAS as posições futures, e stop/TP já vão na ordem.

O elo engine→entry é arquivo local com janela de 10min — **funciona se ambos
rodarem sequencialmente no MESMO job** (mesmo runner/workspace).

## Problema de segurança a corrigir junto (obrigatório)

`faro_v3_entry.ps1` conta posições ativas lendo `journal/faro_v3_positions.jsonl`
(local). No runner efêmero esse arquivo **nunca existe** → o guard `MaxPositions`
nunca limita → risco de empilhar posições sem teto entre ciclos. Fix: contar
posições reais da exchange.

## Mudanças exatas

### 1. `scripts/faro_v3_entry.ps1` — guard MaxPositions pela exchange

**Âncora:** o bloco que começa em `# Check active position count` e termina em
`exit 0` do `if ($activePositions.Count -ge $MaxPositions)`.

SUBSTITUIR o conteúdo desse bloco para que a contagem venha da exchange quando
disponível, mantendo o arquivo local como fallback:

```powershell
# Check active position count
# 2026-07-15 cloud fix: journal/faro_v3_positions.jsonl e local e NAO persiste
# entre runs do GitHub Actions (runner efemero) -- o guard MaxPositions nunca
# limitava na nuvem. Fonte de verdade: posicoes reais abertas na exchange.
$activeCount = 0
$exchangeCountOk = $false
if (Get-Command CoinEx-GetPendingPositions -ErrorAction SilentlyContinue) {
    try {
        $exchangePos = @(CoinEx-GetPendingPositions -ErrorAction Stop)
        $activeCount = @($exchangePos).Count
        $exchangeCountOk = $true
        Write-Host "Posicoes abertas na exchange: $activeCount (fonte: API)" -ForegroundColor Yellow
    } catch {
        Write-Warning "WARN: contagem via exchange falhou: $_"
    }
}
if (-not $exchangeCountOk) {
    # Fallback legado (ambiente local com daemon)
    $posFile = Join-Path $journalDir "faro_v3_positions.jsonl"
    if (Test-Path $posFile) {
        Get-Content $posFile | ForEach-Object {
            try {
                $obj = $_ | ConvertFrom-Json
                if ($obj.status -eq "active") { $activeCount++ }
            } catch {}
        }
    }
}

if ($activeCount -ge $MaxPositions) {
    Write-Host "WARN: Max positions ($MaxPositions) reached ($activeCount abertas); skipping new entries" -ForegroundColor Yellow
    exit 0
}
```

ATENÇÃO: mais abaixo no arquivo existe `$posFile = Join-Path $journalDir
"faro_v3_positions.jsonl"` usado para GRAVAR a posição após a entrada
(`Add-Content ... $posFile`). Esse uso de escrita NÃO muda — se a variável
`$posFile` tiver ficado fora de escopo por causa da substituição acima,
garanta que ela continua definida antes do uso de escrita (pode redefinir a
linha `$posFile = ...` antes do `Add-Content` se necessário).

### 2. `.github/workflows/trading-pipeline.yml` — novo job `faro-v3`

**Local:** APÊNDICE ao final do arquivo (após o último job). Usar Python para
appendar (NUNCA sed) — padrão já usado no repo. Formato EXATO do job (espelha o
job `staleness-audit`, âncora linha ~525, para o bloco Setup de credenciais):

```yaml

  # ============================================================================
  # JOB: FARO V3 — detector pre-pump + auto-entry (2026-07-15)
  # Reativacao na nuvem do daemon local morto. Engine -> Entry sequenciais no
  # MESMO runner (o elo journal/faro_v3_candidates.jsonl e local com janela de
  # 10min -- so funciona dentro do mesmo job). Manager NAO agendado: Trailing
  # Stop Monitor + Position Risk Manager ja gerenciam todas as posicoes futures
  # e o stop/TP vai embutido na propria ordem de entrada.
  # Guard: cron_guard interval:60 (min 1h entre execucoes reais).
  # ============================================================================
  faro-v3:
    name: FARO V3 Pre-Pump (engine + entry)
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup
        shell: pwsh
        run: |
          New-Item -ItemType Directory -Path "agents","journal","logs" -Force | Out-Null
          $content = "`$env:COINEX_ACCESS_ID = '${{ secrets.COINEX_ACCESS_ID }}'" + "`n"
          $content += "`$env:COINEX_SECRET_KEY = '${{ secrets.COINEX_SECRET_KEY }}'" + "`n"
          $content += "`$env:TELEGRAM_BOT_TOKEN = '${{ secrets.TELEGRAM_BOT_TOKEN }}'" + "`n"
          $content += "`$env:TELEGRAM_CHAT_ID = '${{ secrets.TELEGRAM_CHAT_ID }}'" + "`n"
          $content += "`$env:SUPABASE_URL = '${{ secrets.SUPABASE_URL }}'" + "`n"
          $content += "`$env:SUPABASE_ANON_KEY = '${{ secrets.SUPABASE_ANON_KEY }}'" + "`n"
          $content += "`$env:SUPABASE_SERVICE_KEY = '${{ secrets.SUPABASE_SERVICE_KEY }}'" + "`n"
          $content | Out-File "agents/config.local.ps1" -Encoding UTF8

      - name: Run FARO V3
        shell: pwsh
        continue-on-error: true
        run: |
          & ./scripts/cron_guard.ps1 -JobId "faro_v3" -Schedule "interval:60"
          if ($LASTEXITCODE -eq 0) {
            Write-Host "=== FARO V3 ENGINE ===" -ForegroundColor Cyan
            try {
              & ./scripts/faro_v3_engine.ps1
              Write-Host "=== FARO V3 ENTRY ===" -ForegroundColor Cyan
              & ./scripts/faro_v3_entry.ps1 -DryRun $false -CapitalPercent 0.01 -MaxPositions 3
              Write-Host "OK" -ForegroundColor Green
            } catch {
              Write-Host "WARN: $_" -ForegroundColor Yellow
            }
          }
          exit 0
```

Notas de parametrização (NÃO alterar): `CapitalPercent 0.01` (~$50/posição no
capital atual) e `MaxPositions 3` — exposição máxima ~$150, perda máxima com
stop -8% ≈ $12. Conservador de propósito no v1.

## Regras INEGOCIÁVEIS (incidentes reais deste repo)

1. **PS 5.1**: proibido `??`, ternário `?:`, `?.` em qualquer .ps1.
2. **NUNCA sed/regex-replace em massa** — edição pontual (Edit tool) no .ps1;
   append via Python no .yml (padrão do repo).
3. **Fail-soft** no job (`continue-on-error: true` + try/catch + `exit 0`).
4. **Não tocar** em nenhum outro job do workflow nem no engine/manager.
5. Secrets EXATAMENTE como nos outros jobs: `COINEX_ACCESS_ID` (NÃO
   `COINEX_API_KEY` — incidente 2026-07-14, 5 runs quebradas por nome errado).

## Validação obrigatória (nesta ordem)

1. Parse PS5.1 de `scripts/faro_v3_entry.ps1` → 0 erros
   (`[System.Management.Automation.Language.Parser]::ParseFile`).
2. YAML válido: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/trading-pipeline.yml', encoding='utf-8'))"`
   → sem exceção, e o número de jobs deve ser o anterior +1.
3. Baseline Pester ANTES e DEPOIS (resultado idêntico):
   `Invoke-Pester -Script tests/lib_market_scenario.Tests.ps1 -PassThru` (Pester 3.4).
4. `git diff` completo dos 2 arquivos no relatório. NÃO commitar, NÃO push.

## Critério de sucesso

- Job `faro-v3` presente e YAML válido; entry conta posições pela exchange;
  parse limpo; Pester idêntico ao baseline; diff entregue para revisão.
