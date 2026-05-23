
# Credenciais via env var (config.local.ps1 ou shell environment).
# NUNCA hardcode keys aqui. Ver SECURITY.md.
$accessId     = $env:COINEX_ACCESS_ID
$secretKey    = $env:COINEX_SECRET_KEY
if (-not $accessId -or -not $secretKey) {
    throw "COINEX_ACCESS_ID / COINEX_SECRET_KEY nao definidos. Carregar agents/config.local.ps1 antes."
}
$market       = "TONUSDT"
$trailPct     = 0.03
$checkSecs    = 30
$entryPrice   = 2.4624
$highestPrice = 2.4624
$currentStop  = 2.3885
$pctSign      = "%"

function Get-CoinExHeaders($method, $path, $body) {
    $ts     = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
    $toSign = $method + $path + $body + $ts
    $hmac   = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($secretKey)
    $sig    = [System.BitConverter]::ToString($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($toSign))).Replace("-","").ToLower()
    return @{
        "X-COINEX-KEY"       = $accessId
        "X-COINEX-SIGN"      = $sig
        "X-COINEX-TIMESTAMP" = $ts
        "Content-Type"       = "application/json"
    }
}

function CoinEx-Get($path) {
    $h = Get-CoinExHeaders "GET" $path ""
    return Invoke-RestMethod -Uri ("https://api.coinex.com" + $path) -Method GET -Headers $h
}

function CoinEx-Post($path, $bodyObj) {
    $json = $bodyObj | ConvertTo-Json -Compress
    $h    = Get-CoinExHeaders "POST" $path $json
    return Invoke-RestMethod -Uri ("https://api.coinex.com" + $path) -Method POST -Headers $h -Body $json
}

function Set-StopLoss($price) {
    $r = CoinEx-Post "/v2/futures/set-position-stop-loss" @{
        market          = $market
        market_type     = "FUTURES"
        stop_loss_type  = "mark_price"
        stop_loss_price = [math]::Round($price, 4).ToString()
    }
    return $r.code -eq 0
}

function Close-All() {
    return CoinEx-Post "/v2/futures/close-position" @{
        market      = $market
        market_type = "FUTURES"
        type        = "market"
    }
}

function Get-OpenPosition() {
    $r = CoinEx-Get ("/v2/futures/pending-position?market=" + $market + "&market_type=FUTURES")
    if ($r.code -eq 0 -and $r.data -and $r.data.open_interest -gt 0) { return $r.data }
    return $null
}

function Log($msg) {
    $t = (Get-Date).ToString("HH:mm:ss")
    Write-Host ($t + " | " + $msg)
}

Log "=============================="
Log " TRAILING STOP INICIADO"
Log " Par:     $market LONG"
Log " Entrada: $entryPrice"
Log " Trail:   3 por cento abaixo do topo"
Log " Stop:    $currentStop"
Log "=============================="

while ($true) {
    try {
        $pos = Get-OpenPosition
        if (-not $pos) {
            Log "POSICAO FECHADA - encerrando"
            break
        }

        $ticker = Invoke-RestMethod -Uri ("https://api.coinex.com/v2/futures/ticker?market=" + $market) -Method GET
        $mark   = [double]$ticker.data[0].mark_price
        $last   = [double]$ticker.data[0].last
        $pnl    = [math]::Round([double]$pos.unrealized_pnl, 4)
        $pnlPct = [math]::Round(($mark - $entryPrice) / $entryPrice * 100, 2)

        if ($mark -gt $highestPrice) {
            $highestPrice = $mark
        }

        $newStop = [math]::Round($highestPrice * (1 - $trailPct), 4)

        if ($newStop -gt $currentStop) {
            $ok = Set-StopLoss $newStop
            if ($ok) {
                $msg = "STOP SUBIU " + $currentStop + " -> " + $newStop + " | Topo: " + $highestPrice + " | PnL: " + $pnl + " (" + $pnlPct + $pctSign + ")"
                Log $msg
                $currentStop = $newStop
            } else {
                Log "ERRO ao atualizar stop"
            }
        } else {
            $msg = "Price: " + $last + " | Mark: " + $mark + " | Topo: " + $highestPrice + " | Stop: " + $currentStop + " | PnL: " + $pnl + " (" + $pnlPct + $pctSign + ")"
            Log $msg
        }

        if ($mark -le $currentStop) {
            Log "!! STOP ATINGIDO - Fechando posicao !!"
            $close = Close-All
            if ($close.code -eq 0) {
                Log ("POSICAO FECHADA. PnL final: " + $pnl)
            } else {
                Log ("ERRO ao fechar: " + $close.message)
            }

            # ── GEM safety: registrar resultado para circuit breaker ─────────
            try {
                $libGemSafety = Join-Path $PSScriptRoot "agents\lib_gem_safety.ps1"
                if (Test-Path $libGemSafety) {
                    . $libGemSafety
                    $exit_reason = "STOP_LOSS"
                    $result = if ($pnl -gt 0)                   { "WIN" }
                              elseif ($exit_reason -eq "STOP_LOSS") { "STOP" }
                              elseif ($exit_reason -eq "TIMEOUT")   { "EXPIRED" }
                              else                              { "LOSS" }
                    Add-GemTradeResult -Market $market -Result $result -PnlUsdt ([double]$pnl)
                }
            } catch {
                Log ("AVISO: Add-GemTradeResult falhou: " + $_.Exception.Message)
            }
            break
        }

    } catch {
        Log ("ERRO: " + $_.Exception.Message)
    }

    Start-Sleep -Seconds $checkSecs
}

Log "TRAILING STOP ENCERRADO"
