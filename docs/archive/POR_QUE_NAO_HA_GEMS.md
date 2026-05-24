# 🔍 POR QUE NÃO HÁ GEMS HOJE?

## ❌ PROBLEMA IDENTIFICADO

**Última gem detectada**: 12 de maio de 2026 (11 dias atrás)
**Hoje**: 23 de maio de 2026
**Gems detectadas hoje**: 0

---

## 🔎 CAUSA RAIZ

### O Gem Agent NÃO está sendo executado automaticamente!

**Verificação**:
1. ✅ Gem Agent existe: `agents/gem_agent.ps1`
2. ✅ Gem Executor existe: `agents/gem_executor.ps1`
3. ❌ **Nenhum cron job configurado** para executar o Gem Agent
4. ❌ **Não está no GitHub Actions** workflow

---

## 📊 SISTEMA ATUAL

### O que está rodando automaticamente:

**Local (5 minutos)**:
- ✅ Risk Manager (`position_risk_cron.ps1`)
- ✅ Dashboard Generator (`generate_dashboard_elite.ps1`)

**GitHub Actions (15 minutos)**:
- ✅ Risk Manager
- ✅ Dashboard Generator
- ✅ Health Check

### O que NÃO está rodando:
- ❌ Gem Agent (descoberta de micro-caps)
- ❌ Gem Executor (execução de trades de gems)
- ❌ Scan Master (scanner de mercado)

---

## 🎯 COMO O GEM AGENT FUNCIONA

### Fluxo Normal
1. **Scan de Mercado** - Busca pares com volume spike (2x+)
2. **6 Gates de Qualidade**:
   - G1: Volume spike
   - G2: Range diário
   - G3: Market cap
   - G4: Narrativa (keywords + trending)
   - G5: Estrutura intraday
   - G6: Orgânico vs wash trading
3. **Score 0-100** - Gems com score > 70 (DISCOVERY) ou > 60 (MOMENTUM)
4. **Execução** - Sizing assimétrico (0.2-0.4% do capital)
5. **Trailing Agressivo** - 30% trailing após +3%

### Modos
- **DISCOVERY**: Market cap < $2M, R:R 1:200
- **MOMENTUM**: Market cap $2M-$20M, R:R 1:20

---

## ✅ SOLUÇÃO: ATIVAR GEM AGENT

### Opção 1: Executar Manualmente (Teste)

```powershell
# Executar scan de gems
.\scripts\gem_loop.ps1
```

### Opção 2: Adicionar ao Cron Local

Criar arquivo: `scripts/gem_scan_cron.ps1`

```powershell
# gem_scan_cron.ps1 - Scan de gems a cada 2 horas
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\config.ps1"
. ".\agents\lib_coinex.ps1"
. ".\agents\lib_telegram.ps1"
. ".\agents\gem_agent.ps1"

try {
    Write-Host "=== GEM SCAN ===" -ForegroundColor Cyan
    
    # Scan top 10 pares
    $gems = Invoke-GemScan -TopN 10
    
    if ($gems -and $gems.Count -gt 0) {
        Write-Host "Gems encontradas: $($gems.Count)" -ForegroundColor Green
        
        # Enviar alerta no Telegram
        foreach ($gem in $gems) {
            if ($gem.score -ge 70) {
                $message = "==========================`n"
                $message += ">> GEM DETECTADA <<`n"
                $message += "==========================`n`n"
                $message += "Market: $($gem.market)`n"
                $message += "Score: $($gem.score)`n"
                $message += "Mode: $($gem.mode)`n"
                $message += "Mcap: `$$($gem.mcap_usd)`n"
                $message += "Narrative: $($gem.narrative)`n`n"
                $message += "Gates: $($gem.gates_passed -join ', ')"
                
                Telegram-SendMessage -Message $message
            }
        }
    } else {
        Write-Host "Nenhuma gem encontrada" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Erro: $_" -ForegroundColor Red
}
```

Adicionar ao Task Scheduler:
```powershell
# Executar a cada 2 horas
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 2)
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File C:\Users\thiag\Coinex_AI_USER_API\scripts\gem_scan_cron.ps1"
Register-ScheduledTask -TaskName "GemScan" -Trigger $trigger -Action $action
```

### Opção 3: Adicionar ao GitHub Actions

Editar `.github/workflows/trading-pipeline.yml`:

```yaml
  gem-scanner:
    name: Gem Scanner
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout código
        uses: actions/checkout@v4
      
      - name: Setup PowerShell
        shell: pwsh
        run: |
          Write-Host "PowerShell $($PSVersionTable.PSVersion) instalado"
      
      - name: Configurar credenciais
        shell: pwsh
        run: |
          $configContent = @"
`$env:COINEX_ACCESS_ID = "${{ secrets.COINEX_ACCESS_ID }}"
`$env:COINEX_SECRET_KEY = "${{ secrets.COINEX_SECRET_KEY }}"
`$env:TELEGRAM_BOT_TOKEN = "${{ secrets.TELEGRAM_BOT_TOKEN }}"
`$env:TELEGRAM_CHAT_ID = "${{ secrets.TELEGRAM_CHAT_ID }}"
"@
          
          New-Item -ItemType Directory -Path "agents" -Force | Out-Null
          $configContent | Out-File "agents/config.local.ps1" -Encoding UTF8 -Force
      
      - name: Executar Gem Scan
        shell: pwsh
        run: |
          try {
            & ./scripts/gem_scan_cron.ps1
            Write-Host "✓ Gem Scan executado"
          } catch {
            Write-Host "✗ Erro: $_"
            exit 1
          }
```

Alterar frequência para a cada 2 horas:
```yaml
on:
  schedule:
    - cron: '0 */2 * * *'  # A cada 2 horas
```

---

## ⚠️ CONSIDERAÇÕES

### Por que Gems não estão ativas por padrão?

1. **Alto Risco**: Gems são micro-caps voláteis
2. **Sizing Pequeno**: 0.2-0.4% do capital por trade
3. **R:R Extremo**: Busca 1:20 a 1:200
4. **Wash Trading**: Muitos pumps são manipulados
5. **Liquidez Baixa**: Difícil entrar/sair

### Quando ativar Gems?

- ✅ Capital > $5,000 (para diluir risco)
- ✅ Após validar sistema principal funcionando
- ✅ Com capital "especulativo" separado
- ✅ Monitoramento ativo (Telegram alerts)

---

## 📊 ESTATÍSTICAS HISTÓRICAS

**Última execução**: 12 de maio de 2026
**Gems detectadas**: Várias (ver `journal/gem_signals.csv`)
**Taxa de sucesso**: Não disponível (precisa análise)

---

## 🎯 RECOMENDAÇÃO

### Curto Prazo (Hoje)
1. **NÃO ativar gems ainda**
2. **Focar no trade principal** (BNBUSDT LONG)
3. **Validar GitHub Actions** funcionando

### Médio Prazo (Próxima semana)
1. **Testar Gem Scan manualmente**
2. **Analisar qualidade dos sinais**
3. **Decidir se vale ativar automaticamente**

### Longo Prazo
1. **Adicionar ao GitHub Actions** (se validado)
2. **Monitorar performance**
3. **Ajustar parâmetros** (score mínimo, sizing, etc)

---

## 🔧 TESTE RÁPIDO

Para testar se o Gem Agent funciona:

```powershell
# Executar scan manual
.\scripts\gem_loop.ps1

# Ou testar função diretamente
. .\agents\config.ps1
. .\agents\lib_coinex.ps1
. .\agents\gem_agent.ps1

$tickers = Get-GemSpotTickers -MinVol 5000 -MaxVol 500000
Write-Host "Pares encontrados: $($tickers.Count)"
```

---

## ✅ RESUMO

**Por que não há gems?**
- Gem Agent não está sendo executado automaticamente
- Última execução: 11 dias atrás
- Nenhum cron job configurado

**O que fazer?**
- Opção 1: Executar manualmente para testar
- Opção 2: Adicionar ao cron local (2h)
- Opção 3: Adicionar ao GitHub Actions (2h)

**Recomendação**:
- **Não ativar ainda** - Focar no sistema principal
- **Testar manualmente** primeiro
- **Validar qualidade** dos sinais
- **Ativar depois** se fizer sentido

---

**Timestamp**: 2026-05-23 18:00:00 UTC
**Status**: Gem Agent INATIVO (por design)
**Próxima ação**: Decidir se quer ativar ou não
