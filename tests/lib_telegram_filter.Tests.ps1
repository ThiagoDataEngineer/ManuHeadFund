Describe "Telegram Noise Filter" {
    BeforeAll {
        Set-Location $PSScriptRoot/..
        . agents/lib_telegram.ps1
    }

    Context "Deveria SILENCIAR (ruído)" {
        It "silencia SPOT com PnL" {
            $msg = "[SPOT] [PERDA] OPNUSDT: Price=0.07535 | PnL=-69% (-12.68 USD)"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Be $true
        }

        It "silencia WATCH com PnL" {
            $msg = "[WATCH] [UP] HYPEUSDT: Price=75.82 | PnL=1.57pct (0 USD)"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Be $true
        }

        It "silencia FALLBACK com mark=0" {
            $msg = "[FALLBACK] HYPEUSDT: mark=0 -> ticker last=75.72 | pnl(price)=1.43%"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Be $true
        }

        It "silencia heartbeat" {
            $msg = "Heartbeat ciclo 42 — 12 gems encontrados, 3 em análise"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Be $true
        }

        It "silencia GemScan 0 gems" {
            $msg = "GemScan ciclo 5: 0 gems encontrados (baixa volatilidade)"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Be $true
        }
    }

    Context "Deveria DEIXAR PASSAR (acionável)" {
        It "bloqueia ENTRADA por token falso (nao foi silenciado)" {
            $msg = "🎯 ENTRADA EXECUTADA: BASEDUSDT | Preço 0.0778 | SL=0.036 | TP=0.22"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Not Be $true
        }

        It "bloqueia FECHAMENTO por token falso" {
            $msg = "❌ TRADE FECHADO: XMRUSDT | PnL=-8.2% (-$12.34)"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Not Be $true
        }

        It "bloqueia STOP HIT por token falso" {
            $msg = "🛑 STOP HIT: HYPEUSDT | SL=68.50 atingido"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Not Be $true
        }

        It "bloqueia CIRCUIT BREAKER por token falso" {
            $msg = "🚨 CIRCUIT BREAKER ATIVADO — Perdemos -2% do capital hoje"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Not Be $true
        }

        It "bloqueia REGIME CHANGE por token falso" {
            $msg = "📊 REGIME: BEAR_WEAK → BEAR_STRONG (liquidez seca)"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Not Be $true
        }

        It "bloqueia ERROR por token falso" {
            $msg = "❌ ERRO: CoinEx API timeout — retentando em 30s"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Not Be $true
        }
    }

    Context "Ruído adicional (2026-06-17 expansão)" {
        It "silencia 'daemon alive'" {
            $msg = "gem_loop daemon alive — 42 ciclos processados"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Be $true
        }

        It "silencia 'auto-recovered'" {
            $msg = "Auto-recovered: limpou cache e reinicializou conexão"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Be $true
        }

        It "silencia 'Position update' sem evento" {
            $msg = "Position update: HYPEUSDT atualizado — PnL sem mudança"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Be $true
        }

        It "silencia 'whale detectado' (monitoring passivo)" {
            $msg = "Whale detectado: $500k em buy orders a $75.50"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Be $true
        }

        It "passa 'Position update com STOP' (acionável)" {
            $msg = "Position update: XMRUSDT — STOP ATIVADO em SL"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Not Be $true
        }
    }

    Context "Bloqueios e Info logs (2026-06-17 v2 expansão)" {
        It "silencia [BLOCKED] sizing_invalido" {
            $msg = "[BLOCKED] ASTERUSDT -- sizing_invalido"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Be $true
        }

        It "silencia [BLOCKED] trendline" {
            $msg = "[BLOCKED] EPIC -- trendline_invalida"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Be $true
        }

        It "silencia [BLOCKED] recent_decision" {
            $msg = "[BLOCKED] XRP -- recent_decision_cache"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Be $true
        }

        It "silencia [INFO] Dormindo" {
            $msg = "[INFO] Dormindo 60min ate proximo cycle"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Be $true
        }

        It "silencia cache cleared" {
            $msg = "Cache cleared — reinicializou conexão"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Be $true
        }
    }

    Context "Casos edge" {
        It "acionável sobrescreve ruído (prioriza acionável)" {
            $msg = "[SPOT] PnL=5% (10 USD) — ENTRADA executada!"
            $result = Send-TelegramAlert -Message $msg -Enabled "true" -Token "fake" -ChatId "fake"
            $result | Should Not Be $true
        }
    }
}
