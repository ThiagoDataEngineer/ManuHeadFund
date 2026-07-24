# forced_test_trade_2026_07_16.ps1 -- ONE-SHOT: prova o caminho de execucao
# real (pos-gates) nunca exercitado em producao ate agora, com teto HARD de
# risco. NAO edita gem_executor.ps1 -- sobrescreve Invoke-OrderRouted DEPOIS
# do dot-source (mesmo padrao que os testes Pester ja usam pra mockar),
# validando o valor USD da ordem ANTES de repassar pra funcao real. Se o
# valor calculado por qualquer via de sizing (inclusive Get-DynamicCapitalAllocation,
# que ignora sizing_pct customizado) ultrapassar o teto, aborta sem enviar
# nada -- nao deixa a formula de producao decidir sozinha o risco desse teste.
#
# Uso: pwsh forced_test_trade_2026_07_16.ps1 -Market <par> -Direction LONG|SHORT -MaxUsd 15
# Remover apos uso. Nao faz parte do pipeline.

param(
    [Parameter(Mandatory)] [string] $Market,
    [ValidateSet("LONG", "SHORT")] [string] $Direction = "LONG",
    [double] $MaxUsd = 15.0,
    [switch] $ForceGatesPass,   # mocka Test-ParallelBreadthGate pra sempre permitir (mercado real esta neutro)
    [switch] $DryRun   # valida o mecanismo do guard sem enviar ordem real
)

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "gem_executor.ps1")

Write-Host ""
Write-Host "=== FORCED TEST TRADE (teto hard `$$MaxUsd) ===" -ForegroundColor Cyan
Write-Host "Market=$Market Direction=$Direction MaxUsd=$MaxUsd" -ForegroundColor Cyan
Write-Host ""

# === Guard hard: intercepta Invoke-OrderRouted, valida valor ANTES de repassar ===
# Redefine no mesmo escopo -- ultima definicao vence (dot-source ja carregou
# a real via gem_executor.ps1 -> lib_order_routed.ps1). Assinatura identica.
$script:__realOrderFn = ${function:Invoke-OrderRouted}
$script:__maxUsdGuard = $MaxUsd

function Invoke-OrderRouted {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Route,
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Side,
        [Parameter(Mandatory)] [string] $Type,
        [double] $Amount = 0,
        [double] $Price = 0,
        [double] $QuoteAmountUsd = 0,
        [double] $StopLoss = 0,
        [double] $Target = 0,
        [string] $StpMode = "ct"
    )

    # Estima valor USD da ordem: QuoteAmountUsd (spot market buy) ou Amount*Price (demais)
    $estimatedUsd = if ($QuoteAmountUsd -gt 0) { $QuoteAmountUsd }
                    elseif ($Price -gt 0) { $Amount * $Price }
                    else { $Amount }  # fallback grosseiro, so pra nao passar sem checagem

    Write-Host "  [GUARD] Invoke-OrderRouted interceptado: Route=$Route Side=$Side estimatedUsd=`$$([Math]::Round($estimatedUsd,2))" -ForegroundColor Magenta

    if ($estimatedUsd -gt $script:__maxUsdGuard) {
        Write-Host "  [GUARD] ABORTADO: valor estimado `$$([Math]::Round($estimatedUsd,2)) excede teto `$$($script:__maxUsdGuard) -- ordem NAO enviada" -ForegroundColor Red
        throw "forced_test_trade: valor excede teto hard (`$$estimatedUsd > `$$($script:__maxUsdGuard)) -- abortado por seguranca"
    }

    Write-Host "  [GUARD] OK: dentro do teto, repassando pra execucao real" -ForegroundColor Green
    return & $script:__realOrderFn @PSBoundParameters
}

# === Monta candidato minimo, deixa o resto do pipeline (gates, sizing, etc) rodar normal ===
$gem = [PSCustomObject]@{
    market    = $Market
    direction = $Direction
    score     = 65
    mode      = "DISCOVERY"
    sizing_pct = [Math]::Round($MaxUsd / 2333.0, 6)  # so usado se Get-DynamicCapitalAllocation falhar
    change_24h = 0
}

# 2026-07-16: threshold customizado nao basta -- Test-ParallelBreadthGate
# exige $breadth.trend -eq "bullish"/"bearish" (classificacao calculada
# dentro de Get-AltcoinBreadth, nao afetada por threshold percentual
# passado como parametro). Mercado real hoje esta genuinamente neutro
# (breadth ~50%, nem bullish nem bearish o suficiente) -- pra provar o
# caminho POS-gates (que e o objetivo deste teste, o gate de breadth em
# si ja foi validado em producao com Breadth=neutral correto), mocka a
# funcao inteira nesta chamada em vez de tentar contornar so o threshold.
if ($ForceGatesPass) {
    function Test-ParallelBreadthGate {
        param([string]$BtcScenario, [bool]$BtcAllowLong, [bool]$BtcAllowShort)
        return [PSCustomObject]@{
            allow_long = $true; allow_short = $true
            breadth_trend = "forced_test"; breadth_pct = 0
            source = "forced_test_trade_override"
        }
    }
    # Mercado real esta em cenario NEUTRO (allow_long=allow_short=$false por
    # design, "chop sem direcao") -- mockando pra permitir ambos so nesta
    # chamada, mesmo motivo do breadth acima.
    function Get-MarketScenario {
        param([int]$CacheMinutes = 10)
        return [PSCustomObject]@{
            scenario = "forced_test"; strategy = "forced_test"
            allow_long = $true; allow_short = $true
            reason = "forced_test_trade_override"; momentum_30d = 0
        }
    }
    # Tori confluence (lib_tori_gate_wrapper.ps1): score tecnico real
    # calculado sobre 100 candles reais da CoinEx -- LINKUSDT deu 65/100
    # agora, abaixo do threshold 80. E o gate mais "de mercado real" dos
    # tres (nao e regime artificial, e forca tecnica momentanea do par);
    # mockado tambem so pra completar a prova do caminho pos-gates.
    function Test-ToriConfluence {
        param([string]$Market, [string]$SetupType, [int]$TimeframeMinutes = 60, [double]$Price = 0.0, [int]$TimeoutSeconds = 8)
        return [PSCustomObject]@{
            allows = $true; confluence_score = 85
            signals_fired = @("forced_test"); reason = "forced_test_trade_override"
            details = [PSCustomObject]@{}; audit_log = "forced_test_trade_override"
        }
    }
    # 2026-07-16 rodada 2: ETHUSDT SHORT bloqueou em pump_short_blocked
    # (Pump=natural_uptrend -- ETH real esta em alta natural saudavel agora,
    # gate corretamente recusa SHORT em uptrend organico, so libera SHORT em
    # pump_and_dump). Mockando tambem pra completar a prova do SHORT.
    function Test-PumpDumpGate {
        param([string]$Market, [hashtable]$Metadata)
        return [PSCustomObject]@{
            allow_long = $true; allow_short = $true
            pump_class = "forced_test"; pump_score = 0
            reason = "forced_test_trade_override"
        }
    }
    Write-Host "  [OVERRIDE] Test-ParallelBreadthGate + Get-MarketScenario + Test-ToriConfluence + Test-PumpDumpGate mockadas -- todas permitem" -ForegroundColor Yellow
}

if ($DryRun) {
    Write-Host "  [DRY RUN] Guard sera testado mas Invoke-GemExecute roda em modo DryRun (nenhuma ordem real)." -ForegroundColor Yellow
}

# O guard (Invoke-OrderRouted sobrescrita acima) lanca excecao de proposito
# quando o valor excede o teto -- e o resultado ESPERADO de seguranca, nao
# um erro fatal do job. Captura aqui pra sair com exit 0 (job GitHub Actions
# nao falha por um abort de seguranca funcionando corretamente).
try {
    $result = if ($DryRun) { Invoke-GemExecute -Gem $gem -DryRun } else { Invoke-GemExecute -Gem $gem }
    Write-Host ""
    Write-Host "=== RESULTADO ===" -ForegroundColor Cyan
    $result | Format-List
} catch {
    if ($_.Exception.Message -match "^forced_test_trade: valor excede teto hard") {
        Write-Host ""
        Write-Host "=== ABORTADO PELO GUARD (esperado, sem erro) ===" -ForegroundColor Yellow
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        exit 0
    }
    Write-Host ""
    Write-Host "=== ERRO INESPERADO ===" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
