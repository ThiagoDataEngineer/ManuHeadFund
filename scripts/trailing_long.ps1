# trailing_long.ps1 â€” Trailing stop para posicoes LONG (parametrizado)
# Suporta: trailing % fixo ou ATR-adaptativo
# Uso: .\trailing_long.ps1 -Market BTCUSDT -EntryPrice 65000 -TrailPct 0.03
# Uso ATR: .\trailing_long.ps1 -Market BTCUSDT -EntryPrice 65000 -ATRMultiplier 2.0
#
# Para registrar saida no journal, passe o -TradeId
# .\trailing_long.ps1 -Market BTCUSDT -EntryPrice 65000 -TrailPct 0.03 -TradeId abc123

param(
    [string]$Market          = "BTCUSDT",
    [double]$EntryPrice      = 0,          # Preco de entrada (obrigatorio)
    [double]$InitialStop     = 0,          # Stop inicial (0 = calcular via Trail)
    [double]$TrailPct        = 0.03,       # Trail % abaixo do topo (0.03 = 3%)
    [double]$ATRMultiplier   = 0,          # Se > 0, usa ATR-based trail (ignora TrailPct)
    [int]   $CheckSecs       = 30,         # Intervalo de verificacao (segundos)
    [string]$TradeId         = "",         # ID no journal para auto-fechar
    [switch]$DryRun                        # Simula sem executar ordens reais
)

# â”€â”€ Carregar libs se nao estiverem carregadas â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

$scriptDir = $PSScriptRoot
if (-not (Get-Command CoinEx-GetTicker -ErrorAction SilentlyContinue)) {
    . (Join-Path (Join-Path $scriptDir "agents") "config.ps1")
    . (Join-Path (Join-Path $scriptDir "agents") "lib_coinex.ps1")
}

# Override com credenciais diretas se env vars nao configuradas
if (-not $COINEX_ACCESS_ID) {
    Write-Warning "COINEX_ACCESS_ID nao configurado. Configure env vars ou agents/config.ps1"
    exit 1
}

# â”€â”€ Validacoes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

if ($EntryPrice -le 0) {
    Write-Error "EntryPrice deve ser maior que 0. Use: -EntryPrice <preco>"
    exit 1
}

# â”€â”€ Funcoes auxiliares â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function Get-CurrentATR {
    param([string]$Market, [int]$Period = 14)
    # ATR simplificado dos ultimos candles 1H
    try {
        $candles = CoinEx-GetKlines -Market $Market -TimeFrame "1hour" -Limit ($Period + 2)
        if (-not $candles -or $candles.Count -lt $Period) { return $null }

        $trs = for ($i = 1; $i -lt $candles.Count; $i++) {
            $high = [double]$candles[$i][3]
            $low  = [double]$candles[$i][4]
            $prevClose = [double]$candles[$i-1][2]
            $tr = [math]::Max($high - $low,
                  [math]::Max([math]::Abs($high - $prevClose),
                              [math]::Abs($low - $prevClose)))
            $tr
        }
        $atr = ($trs | Select-Object -Last $Period | Measure-Object -Average).Average
        return [math]::Round($atr, 6)
    } catch { return $null }
}

function Get-MarkPrice {
    param([string]$Market)
    try {
        $ticker = Invoke-RestMethod `
            -Uri "https://api.coinex.com/v2/futures/ticker?market=$Market" `
            -Method GET -ErrorAction Stop
        return [double]$ticker.data[0].mark_price
    } catch { return 0 }
}

function Set-PositionStop {
    param([string]$Market, [double]$Price)
    if ($DryRun) {
        Write-Host "  [DRY_RUN] Set-StopLoss: $Price" -ForegroundColor DarkGray
        return $true
    }
    try {
        $r = CoinEx-SetStopLoss -Market $Market -StopPrice $Price
        return ($r -and $r.code -eq 0)
    } catch { return $false }
}

function Close-Position {
    param([string]$Market)
    if ($DryRun) {
        Write-Host "  [DRY_RUN] ClosePosition chamado" -ForegroundColor DarkGray
        return $true
    }
    try {
        $r = CoinEx-ClosePosition -Market $Market
        return ($r -and $r.code -eq 0)
    } catch { return $false }
}

function Get-OpenPosition {
    param([string]$Market)
    try {
        $r = Invoke-RestMethod `
            -Uri "https://api.coinex.com/v2/futures/pending-position?market=$Market&market_type=FUTURES" `
            -Method GET `
            -Headers (CoinEx-Headers "GET" "/v2/futures/pending-position?market=$Market&market_type=FUTURES" "") `
            -ErrorAction Stop
        if ($r.code -eq 0 -and $r.data -and $r.data.open_interest -gt 0) { return $r.data }
        return $null
    } catch { return $null }
}

function Log {
    param([string]$Message, [string]$Color = "White")
    $t = (Get-Date).ToString("HH:mm:ss")
    Write-Host "$t | $Message" -ForegroundColor $Color
}

# â”€â”€ Inicializacao â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

$highestPrice = $EntryPrice

# Calcular stop inicial
if ($InitialStop -gt 0) {
    $currentStop = $InitialStop
} elseif ($ATRMultiplier -gt 0) {
    $atr = Get-CurrentATR $Market
    if ($atr) {
        $currentStop = [math]::Round($EntryPrice - ($atr * $ATRMultiplier), 4)
        Log "ATR=$atr | Stop inicial ATR-based: $currentStop" "Cyan"
    } else {
        $currentStop = [math]::Round($EntryPrice * (1 - $TrailPct), 4)
        Log "ATR indisponivel, usando trail % padrao: $currentStop" "Yellow"
    }
} else {
    $currentStop = [math]::Round($EntryPrice * (1 - $TrailPct), 4)
}

$trailMode = if ($ATRMultiplier -gt 0) { "ATR x$ATRMultiplier" } else { "Fixed $([math]::Round($TrailPct*100,1))%" }

Log "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•"
Log " TRAILING STOP LONG â€” $Market"
Log " Modo: $trailMode$(if($DryRun){' [DRY RUN]'} else {''})"
Log " Entrada: $EntryPrice"
Log " Stop inicial: $currentStop"
if ($TradeId) { Log " TradeId journal: $TradeId" }
Log "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•"

# Definir stop inicial na exchange
if (-not $DryRun) {
    $ok = Set-PositionStop $Market $currentStop
    if ($ok) { Log "Stop inicial definido: $currentStop" "Green" }
    else { Log "AVISO: Falha ao definir stop inicial" "Yellow" }
}

# â”€â”€ Loop principal â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

$iteration    = 0
$stopAtingido = $false

while ($true) {
    $iteration++
    try {
        # Verificar se posicao ainda esta aberta
        $pos = Get-OpenPosition $Market
        if (-not $pos -and -not $DryRun) {
            Log "POSICAO FECHADA EXTERNAMENTE â€” encerrando trailing" "Yellow"
            $stopAtingido = $true
            break
        }

        $mark   = Get-MarkPrice $Market
        if ($mark -le 0) {
            Log "AVISO: Nao foi possivel obter mark price" "Yellow"
            Start-Sleep -Seconds $CheckSecs
            continue
        }

        $pnlUSD = [math]::Round(($mark - $EntryPrice) * (if ($pos) { [double]$pos.open_interest } else { 0 }), 2)
        $pnlPct = [math]::Round(($mark - $EntryPrice) / $EntryPrice * 100, 2)

        # Atualiza topo
        if ($mark -gt $highestPrice) { $highestPrice = $mark }

        # Calcula novo stop
        $newStop = if ($ATRMultiplier -gt 0) {
            # Recalcula ATR a cada 10 iteracoes
            if ($iteration % 10 -eq 0) {
                $freshATR = Get-CurrentATR $Market
                if ($freshATR) {
                    [math]::Round($highestPrice - ($freshATR * $ATRMultiplier), 4)
                } else {
                    [math]::Round($highestPrice * (1 - $TrailPct), 4)
                }
            } else {
                [math]::Round($highestPrice * (1 - ($TrailPct)), 4)
            }
        } else {
            [math]::Round($highestPrice * (1 - $TrailPct), 4)
        }

        # Sobe o stop se novo stop e maior
        if ($newStop -gt $currentStop) {
            $ok = Set-PositionStop $Market $newStop
            if ($ok) {
                Log "STOP SUBIU $currentStop -> $newStop | Topo: $highestPrice | PnL: $pnlUSD ($pnlPct%)" "Green"
                $currentStop = $newStop
            } else {
                Log "ERRO ao atualizar stop para $newStop" "Red"
            }
        } else {
            # Log normal a cada 5 iteracoes para nao poluir
            if ($iteration % 5 -eq 0 -or $mark -le ($currentStop * 1.005)) {
                $distPct = [math]::Round(($mark - $currentStop) / $mark * 100, 2)
                Log "Mark: $mark | Topo: $highestPrice | Stop: $currentStop ($distPct% dist) | PnL: $pnlUSD ($pnlPct%)" "White"
            }
        }

        # Verifica se stop foi atingido
        if ($mark -le $currentStop) {
            Log "!! STOP ATINGIDO !! Mark=$mark <= Stop=$currentStop" "Red"
            $closed = Close-Position $Market
            if ($closed) {
                Log "POSICAO FECHADA. PnL final: $pnlUSD ($pnlPct%)" $(if($pnlUSD -ge 0){"Green"}else{"Red"})
            } else {
                Log "ERRO ao fechar posicao â€” verificar manualmente!" "Red"
            }
            $stopAtingido = $true
            break
        }

    } catch {
        Log "ERRO: $($_.Exception.Message)" "Red"
    }

    Start-Sleep -Seconds $CheckSecs
}

# â”€â”€ Pos-loop: atualizar journal se TradeId foi fornecido â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

if ($TradeId -and $stopAtingido) {
    $journalPath = (Join-Path (Join-Path $scriptDir "agents") "journal.ps1")
    if (Test-Path $journalPath) {
        try {
            . $journalPath
            $finalMark = Get-MarkPrice $Market
            $motivo    = if ($finalMark -le $currentStop) { "STOP_LOSS" } else { "MANUAL" }
            Close-Trade -TradeId $TradeId -ExitPrice $currentStop -MotivoSaida $motivo
            Log "Journal atualizado: $TradeId fechado com $motivo" "Cyan"
        } catch {
            Log "AVISO: Falha ao atualizar journal: $_" "Yellow"
        }
    }
}

Log "TRAILING STOP ENCERRADO â€” $Market"
