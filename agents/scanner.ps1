# scanner.ps1 — Multi-pair scanner para 237 futuros CoinEx
# Logica: Elder Triple Screen simplificado + score tecnico rapido
# Uso: .\agents\scanner.ps1 -TopN 10 -MinScore 65
param(
    [string[]]$Markets         = @(),
    [int]     $TopN            = 5,
    [int]     $MinScore        = 60,
    [switch]  $FullAnalysis,
    [switch]  $UseAI,
    [switch]  $Continuous,
    [int]     $IntervalMinutes = 15
)

. (Join-Path $PSScriptRoot "config.ps1")
. (Join-Path $PSScriptRoot "lib_coinex.ps1")
. (Join-Path $PSScriptRoot "lib_claude.ps1")

$SCANNER_SYSTEM_PROMPT = @'
Voce e um scanner de mercado especializado em identificar os melhores setups
do universo de futuros de crypto. Voce filtra o ruido e encontra oportunidades
com alta probabilidade de sucesso.

Seu criterio de selecao:
- Tendencia clara (ADX > 25, preco acima/abaixo EMAs alinhadas)
- Momentum com espaco para continuar (RSI entre 45-65 para LONG, 35-55 para SHORT)
- Volume acima da media (confirmacao de interesse)
- Proximos de nivel de entrada (pullback ao suporte/EMA, nao no topo/fundo)
- R:R minimo de 1:2 visivel na estrutura

Voce REJEITA: mercados em range (ADX < 20), ativos com baixo volume absoluto,
setups onde o RSI esta extremo na direcao do trade.

Responda APENAS com JSON valido.
'@

# ── Pre-triagem de micro-cap ──────────────────────────────────────────────────

function Get-CoinGeckoIdForMarket {
    param([string]$Market)
    $base = $Market -replace "USDT$","" -replace "USD$",""
    $map = @{
        "BTC"="bitcoin";"ETH"="ethereum";"SOL"="solana";"BNB"="binancecoin"
        "XRP"="ripple";"TON"="the-open-network";"DOGE"="dogecoin";"ADA"="cardano"
        "AVAX"="avalanche-2";"DOT"="polkadot";"MATIC"="matic-network";"LINK"="chainlink"
        "UNI"="uniswap";"ATOM"="cosmos";"LTC"="litecoin";"BCH"="bitcoin-cash"
        "SUI"="sui";"APT"="aptos";"ARB"="arbitrum";"OP"="optimism"
    }
    if ($map.ContainsKey($base)) { return $map[$base] }
    return $base.ToLower()
}

function Get-CoinGeckoPrescreenData {
    param([string]$CoinId)
    try {
        $url = "https://api.coingecko.com/api/v3/coins/$CoinId`?localization=false&tickers=false&community_data=false&developer_data=false"
        $r = Invoke-RestMethod -Uri $url -Method GET -ErrorAction Stop
        $fdv = if ($r.market_data.fully_diluted_valuation.usd) {
            [double]$r.market_data.fully_diluted_valuation.usd
        } else { 0 }
        return [PSCustomObject]@{
            marketCap   = if ($r.market_data.market_cap.usd) { [double]$r.market_data.market_cap.usd } else { 0 }
            fdv         = $fdv
            genesisDate = $r.genesis_date   # string "YYYY-MM-DD" ou $null
        }
    } catch { return $null }
}

function Test-MicroCapPrescreen {
    param(
        [string]      $Market,
        [PSCustomObject]$Ticker             = $null,
        [double]      $MinVolume24hUsd      = 500000,
        [double]      $MinMcFdvRatio        = 0.20,
        [int]         $MinContractAgeDays   = 90,
        [switch]      $CheckConcentration
    )

    $result = [PSCustomObject]@{
        market        = $Market
        passed        = $false
        reason        = ""
        volumeUsd     = 0.0
        mcFdvRatio    = $null
        ageDays       = $null
        concentration = $null
    }

    # Filtro 1: Volume (CoinEx ticker — barato)
    if (-not $Ticker) {
        try { $Ticker = CoinEx-GetTicker $Market } catch {}
    }
    if (-not $Ticker) {
        $result.reason = "ticker_indisponivel"
        return $result
    }
    $vol = [double]$Ticker.volume * [double]$Ticker.last
    $result.volumeUsd = [math]::Round($vol)
    if ($vol -lt $MinVolume24hUsd) {
        $result.reason = "volume_baixo: $('{0:N0}' -f $vol) USD (min $('{0:N0}' -f $MinVolume24hUsd))"
        return $result
    }

    # Filtros 2 e 3: MC/FDV e idade (CoinGecko — 1 chamada)
    $cgId = Get-CoinGeckoIdForMarket $Market
    $cg   = Get-CoinGeckoPrescreenData $cgId
    if ($cg) {
        if ($cg.fdv -gt 0 -and $cg.marketCap -gt 0) {
            $ratio = $cg.marketCap / $cg.fdv
            $result.mcFdvRatio = [math]::Round($ratio, 3)
            if ($ratio -lt $MinMcFdvRatio) {
                $result.reason = "mc_fdv_baixo: $($result.mcFdvRatio) < $MinMcFdvRatio (diluicao futura alta)"
                return $result
            }
        }
        if ($cg.genesisDate) {
            $age = ([DateTime]::UtcNow - [DateTime]::Parse($cg.genesisDate)).TotalDays
            $result.ageDays = [math]::Round($age)
            if ($age -lt $MinContractAgeDays) {
                $result.reason = "contrato_novo: $($result.ageDays) dias (min $MinContractAgeDays)"
                return $result
            }
        }
    }

    # Filtro 4: Concentracao de holders (Etherscan — opcional, ERC-20)
    if ($CheckConcentration) {
        try {
            $conc = Get-EtherscanConcentration $Market
            $result.concentration = $conc.level
            if ($conc.level -eq "CRITICAL") {
                $result.reason = "concentracao_critica: top holders >= $($conc.threshold)%"
                return $result
            }
        } catch {}
    }

    $result.passed = $true
    $result.reason = "OK"
    return $result
}

# ── Lista de pares priorizados para scan rapido (top volume/interesse) ─────────
$DEFAULT_SCAN_MARKETS = @(
    "BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT", "XRPUSDT",
    "DOGEUSDT", "AVAXUSDT", "ADAUSDT", "DOTUSDT", "LINKUSDT",
    "UNIUSDT", "ATOMUSDT", "LTCUSDT", "BCHUSDT", "SUIUSDT",
    "APTUSDT", "ARBUSDT", "OPUSDT", "MATICUSDT", "TONUSDT"
)

# Get-ScoreClamp -- limite superior do scanner.score, com override OPT-IN.
# EUREKA B (2026-05-15): clamp hardcoded em 65 tornava Tier A inalcancavel
# (Triagem precisa scanner.score >= 75). Override SCANNER_SCORE_CLAMP_OVERRIDE
# em config.local.ps1 destrava Tier A para teste sem mudar default.
# Vide journal/diagnose_triagem_tier_d_2026_05_15.md EUREKA B + recomendacao Opcao 2.
function Get-ScoreClamp {
    [CmdletBinding()]
    param(
        [int] $Default = 65,
        [int] $Max     = 100
    )
    $override = $null
    if (Test-Path variable:global:SCANNER_SCORE_CLAMP_OVERRIDE) {
        $override = $global:SCANNER_SCORE_CLAMP_OVERRIDE
    }
    if ($null -eq $override) { return $Default }

    # Tenta converter para int. Nao numerico -> fallback.
    $n = 0
    if ($override -is [int] -or $override -is [long] -or $override -is [byte]) {
        $n = [int]$override
    } elseif ($override -is [double] -or $override -is [single] -or $override -is [decimal]) {
        $n = [int]$override
    } else {
        $parsed = 0
        if (-not [int]::TryParse([string]$override, [ref]$parsed)) {
            return $Default
        }
        $n = $parsed
    }

    if ($n -le 0) { return $Default }
    if ($n -gt $Max) { return $Max }
    return $n
}

function Get-QuickTechScore {
    param([string]$Market)
    # Score rapido sem chamar tech_agent.ps1 completo
    # Usa apenas ticker + candles 1D para triagem inicial
    try {
        $ticker = CoinEx-GetTicker $Market
        if (-not $ticker) { return $null }

        $price   = [double]$ticker.last
        $change  = [double]$ticker.change_rate * 100
        $volume  = [double]$ticker.volume

        # Score simples: variacao + volume como proxy
        $score = 50
        if ($change -gt 3)  { $score += 15 }
        elseif ($change -gt 1) { $score += 7 }
        elseif ($change -lt -3) { $score -= 15 }
        elseif ($change -lt -1) { $score -= 7 }

        $sinal = if ($change -gt 0) { "LONG" } elseif ($change -lt 0) { "SHORT" } else { "NEUTRO" }

        # Clamp: default 65, override OPT-IN via $global:SCANNER_SCORE_CLAMP_OVERRIDE.
        $clampMax = Get-ScoreClamp -Default 65 -Max 100

        return [PSCustomObject]@{
            market  = $Market
            price   = $price
            change  = [math]::Round($change, 2)
            volume  = $volume
            score   = [math]::Max(0, [math]::Min($clampMax, $score))
            sinal   = $sinal
        }
    } catch { return $null }
}

function Get-FullTechScore {
    param([string]$Market)
    # Roda tech_agent.ps1 completo para score detalhado
    $techPath = (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "scripts") "tech_agent.ps1")
    if (-not (Test-Path $techPath)) { return $null }
    try {
        $data = & $techPath -Market $Market -Once -Quiet
        if (-not $data) { return $null }
        return [PSCustomObject]@{
            market    = $Market
            price     = $data.tf1h.close
            score     = $data.totalScore
            sinal     = $data.consensus
            adx1d     = $data.tf1d.adx.adx
            rsi1d     = $data.tf1d.rsi
            weinstein = $data.tf1d.weinstein
            wyckoff   = $data.tf1d.wyckoff
            elder     = $data.elder.active
        }
    } catch { return $null }
}

function Invoke-Scanner {
    param(
        [string[]]$Markets           = $DEFAULT_SCAN_MARKETS,
        [int]    $TopN               = 5,
        [int]    $MinScore           = 60,
        [switch] $FullAnalysis,          # Se true, roda tech_agent.ps1 completo (lento)
        [switch] $UseAI,                 # Se true, usa Claude para ranking final
        [switch] $SkipPrescreen,         # Pula a pre-triagem de micro-cap
        [double] $MinVolume24hUsd    = 500000,
        [double] $MinMcFdvRatio      = 0.20,
        [int]    $MinContractAgeDays = 90,
        [switch] $CheckConcentration,    # Verifica concentracao de holders via Etherscan
        [switch] $Verbose
    )

    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  MULTI-PAIR SCANNER — $(Get-Date -Format 'HH:mm')                  ║" -ForegroundColor Cyan
    Write-Host "║  Pares: $($Markets.Count) | Top: $TopN | MinScore: $MinScore      ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    $results = @()
    $i = 0
    foreach ($market in $Markets) {
        $i++
        Write-Host "  [$i/$($Markets.Count)] $market..." -ForegroundColor DarkGray -NoNewline

        # Pre-triagem: volume, MC/FDV, idade, concentracao
        if (-not $SkipPrescreen) {
            $ps = Test-MicroCapPrescreen $market `
                -MinVolume24hUsd $MinVolume24hUsd `
                -MinMcFdvRatio $MinMcFdvRatio `
                -MinContractAgeDays $MinContractAgeDays `
                -CheckConcentration:$CheckConcentration
            if (-not $ps.passed) {
                Write-Host " prescreen: $($ps.reason)" -ForegroundColor DarkRed
                continue
            }
        }

        $data = if ($FullAnalysis) {
            Get-FullTechScore $market
        } else {
            Get-QuickTechScore $market
        }

        if ($data -and $data.score -ge $MinScore) {
            $results += $data
            Write-Host " Score=$($data.score) $($data.sinal)" -ForegroundColor $(if($data.sinal -eq "LONG"){"Green"}elseif($data.sinal -eq "SHORT"){"Red"}else{"Yellow"})
        } else {
            Write-Host " skip (score=$($data.score))" -ForegroundColor DarkGray
        }

        # Rate limit basico
        Start-Sleep -Milliseconds 200
    }

    $topResults = $results | Sort-Object score -Descending | Select-Object -First $TopN

    if (-not $topResults) {
        Write-Host "Nenhum par com score >= $MinScore encontrado." -ForegroundColor Yellow
        return @()
    }

    Write-Host ""
    Write-Host "┌─ TOP $TopN PARES ─────────────────────────────────────┐" -ForegroundColor White
    $rank = 1
    foreach ($r in $topResults) {
        $cor = if ($r.sinal -eq "LONG") { "Green" } elseif ($r.sinal -eq "SHORT") { "Red" } else { "Yellow" }
        Write-Host "│  $rank. $($r.market.PadRight(12)) | Score: $($r.score)/100 | $($r.sinal) | $($r.change)%" -ForegroundColor $cor
        $rank++
    }
    Write-Host "└───────────────────────────────────────────────────┘" -ForegroundColor White
    Write-Host ""

    # Analise IA dos top pares se solicitado
    if ($UseAI -and $topResults.Count -gt 0) {
        Write-Host "Analisando top pares com IA..." -ForegroundColor Cyan

        $topSummary = $topResults | ForEach-Object {
            "Par: $($_.market) | Score: $($_.score) | Sinal: $($_.sinal) | Variacao: $($_.change)% | Preco: $($_.price)"
        }

        $question = @"
Lista dos top pares identificados pelo scanner:
$($topSummary -join "`n")

Analise esses pares e retorne um ranking final em JSON:
{
  "ranking": [
    {
      "market": "XYZUSDT",
      "posicao": 1,
      "sinal": "LONG" | "SHORT",
      "justificativa": "por que este e o melhor setup agora",
      "urgencia": "IMEDIATO" | "AGUARDAR_PULLBACK" | "MONITORAR"
    }
  ],
  "melhor_par": "XYZUSDT",
  "par_evitar": "XYZUSDT",
  "contexto_geral": "frase sobre o estado geral do mercado agora"
}
"@

        $aiResult = Invoke-ClaudeJson $SCANNER_SYSTEM_PROMPT $question -Temperature 0.3
        if ($aiResult) {
            Write-Host ""
            Write-Host "IA Ranking:" -ForegroundColor Magenta
            Write-Host "  Melhor par: $($aiResult.melhor_par)" -ForegroundColor Green
            Write-Host "  Evitar: $($aiResult.par_evitar)" -ForegroundColor Red
            Write-Host "  Contexto: $($aiResult.contexto_geral)" -ForegroundColor White
            return [PSCustomObject]@{ topPares = $topResults; aiRanking = $aiResult }
        }
    }

    return $topResults
}

# Scan continuo com intervalo
function Start-ContinuousScan {
    param(
        [string[]]$Markets  = $DEFAULT_SCAN_MARKETS,
        [int]    $TopN      = 5,
        [int]    $MinScore  = 65,
        [int]    $IntervalMinutes = 15,
        [switch] $UseAI
    )

    Write-Host "Iniciando scan continuo. Intervalo: $IntervalMinutes min. Ctrl+C para parar." -ForegroundColor Cyan

    while ($true) {
        Invoke-Scanner -Markets $Markets -TopN $TopN -MinScore $MinScore -UseAI:$UseAI
        Write-Host "Proximo scan em $IntervalMinutes minutos... ($(Get-Date -Format 'HH:mm'))" -ForegroundColor DarkGray
        Start-Sleep -Seconds ($IntervalMinutes * 60)
    }
}

# Execucao direta
if ($MyInvocation.InvocationName -ne '.') {
    $scanMarkets = if ($Markets.Count -gt 0) { $Markets } else { $DEFAULT_SCAN_MARKETS }
    if ($Continuous) {
        Start-ContinuousScan -Markets $scanMarkets -TopN $TopN -MinScore $MinScore `
                             -IntervalMinutes $IntervalMinutes -UseAI:$UseAI
    } else {
        Invoke-Scanner -Markets $scanMarkets -TopN $TopN -MinScore $MinScore `
                       -FullAnalysis:$FullAnalysis -UseAI:$UseAI
    }
}
