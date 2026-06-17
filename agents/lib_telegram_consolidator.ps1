# lib_telegram_consolidator.ps1 -- Resumo inteligente de posições para Telegram
# Problema: position_watcher gera 10-20 logs/min, Telegram fica travado
# Solução: consolidar PnL, só enviar quando há MUDANÇA de status (GANHO→PERDA ou vice-versa)

function Get-PositionConsolidated {
    <#
    .SYNOPSIS
    Consolida posições ativas em resumo focado (mercados críticos)

    .DESCRIPTION
    Lê trailing_positions.json, calcula PnL, agrupa por status:
    - CRÍTICO: < -10% (sangramento severo)
    - AVISO: -10% a 0% (deterioração)
    - OK: 0% a +5% (neutro/pequeno ganho)
    - GANHO: > +5% (lucro significativo)

    Retorna resumo telegráfico (max 3 linhas por status)
    #>
    param(
        [string]$PositionFile = (Join-Path $PSScriptRoot "..\journal\trailing_positions.json"),
        [int]$LimitPerStatus = 3
    )

    if (-not (Test-Path $PositionFile)) {
        return @{ error = "trailing_positions.json não encontrado" }
    }

    $positions = Get-Content $PositionFile | ConvertFrom-Json
    $active = @($positions | Where-Object { $_.active -eq $true })

    if ($active.Count -eq 0) {
        return @{ summary = "Nenhuma posição ativa"; count = 0 }
    }

    # Agrupar por status
    $critico = @()
    $aviso = @()
    $ok = @()
    $ganho = @()

    foreach ($pos in $active) {
        $entry = [double]$pos.entry
        $current = [double]$pos.stopCurrent
        $pnl_pct = (($current - $entry) / $entry) * 100

        $item = @{
            market = $pos.market
            pnl_pct = [math]::Round($pnl_pct, 1)
            current = $current
            entry = $entry
        }

        if ($pnl_pct -lt -10) { $critico += $item }
        elseif ($pnl_pct -lt 0) { $aviso += $item }
        elseif ($pnl_pct -lt 5) { $ok += $item }
        else { $ganho += $item }
    }

    # Montar resumo
    $lines = @()

    if ($critico.Count -gt 0) {
        $lines += "🔴 **CRÍTICO** (< -10%):"
        foreach ($item in $critico | Select-Object -First $LimitPerStatus) {
            $lines += "  • $($item.market): **$($item.pnl_pct)%** ($($item.current))"
        }
    }

    if ($aviso.Count -gt 0) {
        $lines += ""
        $lines += "🟠 **AVISO** (-10% a 0%):"
        foreach ($item in $aviso | Select-Object -First $LimitPerStatus) {
            $lines += "  • $($item.market): $($item.pnl_pct)% ($($item.current))"
        }
    }

    if ($ok.Count -gt 0) {
        $lines += ""
        $lines += "🟡 **NEUTRO** (0% a +5%):"
        foreach ($item in $ok | Select-Object -First $LimitPerStatus) {
            $lines += "  • $($item.market): +$($item.pnl_pct)% ($($item.current))"
        }
    }

    if ($ganho.Count -gt 0) {
        $lines += ""
        $lines += "🟢 **GANHO** (> +5%):"
        foreach ($item in $ganho | Select-Object -First $LimitPerStatus) {
            $lines += "  • $($item.market): **+$($item.pnl_pct)%** ($($item.current))"
        }
    }

    return @{
        summary = $lines -join "`n"
        critico_count = $critico.Count
        aviso_count = $aviso.Count
        ok_count = $ok.Count
        ganho_count = $ganho.Count
        total = $active.Count
    }
}

function Send-ConsolidatedTgAlert {
    <#
    .SYNOPSIS
    Envia resumo consolidado via Telegram (máx 1x por 10 min)
    #>
    param(
        [string]$PositionFile = (Join-Path $PSScriptRoot "..\journal\trailing_positions.json"),
        [string]$LockFile = (Join-Path $PSScriptRoot "..\journal\tg_consolidate.lock"),
        [int]$IntervalSec = 600  # 10 min entre avisos
    )

    # Rate limit: não enviar se já enviou < 10 min atrás
    if (Test-Path $LockFile) {
        $lastSend = Get-Item $LockFile | Select-Object -ExpandProperty LastWriteTime
        $elapsed = ((Get-Date) - $lastSend).TotalSeconds
        if ($elapsed -lt $IntervalSec) {
            return @{ skipped = $true; reason = "rate_limit_$([math]::Round($elapsed,0))s" }
        }
    }

    $result = Get-PositionConsolidated -PositionFile $PositionFile

    if ($result.critico_count -gt 0 -or $result.aviso_count -gt 0) {
        # Enviar apenas se há posições críticas/aviso
        if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
            try {
                Send-TelegramAlert -Message $result.summary | Out-Null
                (Get-Date) | Out-File $LockFile
                return @{ sent = $true; critico = $result.critico_count; aviso = $result.aviso_count }
            } catch {
                return @{ error = $_.Exception.Message }
            }
        }
    }

    return @{ skipped = $true; reason = "no_critical_positions" }
}
