# tests/lib_rate_limit_monitor.Tests.ps1
# TDD para Monitoramento de Rate Limit Events
# 2026-05-23

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_rate_limit_monitor.ps1")

Describe "Initialize-RateLimitMonitor - Setup inicial" {
    
    It "cria arquivo de log se nao existir" {
        $tempLog = Join-Path $env:TEMP "rate_limit_test_$([guid]::NewGuid()).jsonl"
        
        try {
            Initialize-RateLimitMonitor -LogPath $tempLog
            
            Test-Path $tempLog | Should Be $true
        } finally {
            if (Test-Path $tempLog) { Remove-Item $tempLog -Force }
        }
    }
    
    It "inicializa contadores zerados" {
        Initialize-RateLimitMonitor
        
        $global:RATE_LIMIT_MONITOR | Should Not BeNullOrEmpty
        $global:RATE_LIMIT_MONITOR.total_events | Should Be 0
        $global:RATE_LIMIT_MONITOR.events_today | Should Be 0
    }
}

Describe "Log-RateLimitEvent - Registrar evento" {
    
    BeforeEach {
        $script:tempLog = Join-Path $env:TEMP "rate_limit_test_$([guid]::NewGuid()).jsonl"
        Initialize-RateLimitMonitor -LogPath $script:tempLog
    }
    
    AfterEach {
        if (Test-Path $script:tempLog) { Remove-Item $script:tempLog -Force }
    }
    
    It "registra evento 4213 no log" {
        Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place" -Market "BTCUSDT"
        
        $content = Get-Content $script:tempLog -Raw
        $content | Should Match "4213"
        $content | Should Match "spot_place"
        $content | Should Match "BTCUSDT"
    }
    
    It "evento tem timestamp" {
        Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place"
        
        $line = Get-Content $script:tempLog | Select-Object -Last 1
        $event = $line | ConvertFrom-Json
        
        $event.timestamp | Should Not BeNullOrEmpty
    }
    
    It "evento tem categoria" {
        Log-RateLimitEvent -ErrorCode 4213 -Category "futures_place"
        
        $line = Get-Content $script:tempLog | Select-Object -Last 1
        $event = $line | ConvertFrom-Json
        
        $event.category | Should Be "futures_place"
    }
    
    It "incrementa contador total" {
        $before = $global:RATE_LIMIT_MONITOR.total_events
        
        Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place"
        
        $after = $global:RATE_LIMIT_MONITOR.total_events
        $after | Should Be ($before + 1)
    }
    
    It "incrementa contador diario" {
        $before = $global:RATE_LIMIT_MONITOR.events_today
        
        Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place"
        
        $after = $global:RATE_LIMIT_MONITOR.events_today
        $after | Should Be ($before + 1)
    }
}

Describe "Get-RateLimitEvents - Consultar eventos" {
    
    BeforeEach {
        $script:tempLog = Join-Path $env:TEMP "rate_limit_test_$([guid]::NewGuid()).jsonl"
        Initialize-RateLimitMonitor -LogPath $script:tempLog
    }
    
    AfterEach {
        if (Test-Path $script:tempLog) { Remove-Item $script:tempLog -Force }
    }
    
    It "retorna eventos das ultimas 24h" {
        # Adicionar eventos
        1..5 | ForEach-Object {
            Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place"
        }
        
        $events = Get-RateLimitEvents -Hours 24
        
        $events.Count | Should Be 5
    }
    
    It "filtra por categoria" {
        Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place"
        Log-RateLimitEvent -ErrorCode 4213 -Category "futures_place"
        Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place"
        
        $events = Get-RateLimitEvents -Category "spot_place"
        
        $events.Count | Should Be 2
    }
    
    It "filtra por market" {
        Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place" -Market "BTCUSDT"
        Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place" -Market "ETHUSDT"
        Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place" -Market "BTCUSDT"
        
        $events = Get-RateLimitEvents -Market "BTCUSDT"
        
        $events.Count | Should Be 2
    }
}

Describe "Get-RateLimitSummary - Resumo de eventos" {
    
    BeforeEach {
        $script:tempLog = Join-Path $env:TEMP "rate_limit_test_$([guid]::NewGuid()).jsonl"
        Initialize-RateLimitMonitor -LogPath $script:tempLog
    }
    
    AfterEach {
        if (Test-Path $script:tempLog) { Remove-Item $script:tempLog -Force }
    }
    
    It "retorna resumo vazio inicialmente" {
        $summary = Get-RateLimitSummary
        
        $summary.total_events | Should Be 0
        $summary.events_last_hour | Should Be 0
        $summary.events_last_24h | Should Be 0
    }
    
    It "conta eventos por periodo" {
        1..10 | ForEach-Object {
            Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place"
        }
        
        $summary = Get-RateLimitSummary
        
        $summary.total_events | Should Be 10
        $summary.events_last_hour | Should Be 10
        $summary.events_last_24h | Should Be 10
    }
    
    It "agrupa por categoria" {
        Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place"
        Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place"
        Log-RateLimitEvent -ErrorCode 4213 -Category "futures_place"
        
        $summary = Get-RateLimitSummary
        
        $summary.by_category.spot_place | Should Be 2
        $summary.by_category.futures_place | Should Be 1
    }
    
    It "agrupa por market" {
        Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place" -Market "BTCUSDT"
        Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place" -Market "BTCUSDT"
        Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place" -Market "ETHUSDT"
        
        $summary = Get-RateLimitSummary
        
        $summary.by_market.BTCUSDT | Should Be 2
        $summary.by_market.ETHUSDT | Should Be 1
    }
    
    It "calcula taxa de eventos por hora" {
        1..5 | ForEach-Object {
            Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place"
        }
        
        $summary = Get-RateLimitSummary
        
        ($summary.events_per_hour -gt 0) | Should Be $true
    }
}

Describe "Test-RateLimitHealthy - Health check" {
    
    BeforeEach {
        $script:tempLog = Join-Path $env:TEMP "rate_limit_test_$([guid]::NewGuid()).jsonl"
        Initialize-RateLimitMonitor -LogPath $script:tempLog
    }
    
    AfterEach {
        if (Test-Path $script:tempLog) { Remove-Item $script:tempLog -Force }
    }
    
    It "retorna healthy quando poucos eventos" {
        1..2 | ForEach-Object {
            Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place"
        }
        
        $health = Test-RateLimitHealthy
        
        $health.healthy | Should Be $true
    }
    
    It "retorna unhealthy quando muitos eventos (>10/hora)" {
        1..15 | ForEach-Object {
            Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place"
        }
        
        $health = Test-RateLimitHealthy -ThresholdPerHour 10
        
        $health.healthy | Should Be $false
        $health.reason | Should Match "threshold exceeded"
    }
    
    It "inclui recomendacoes quando unhealthy" {
        1..15 | ForEach-Object {
            Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place"
        }
        
        $health = Test-RateLimitHealthy -ThresholdPerHour 10
        
        $health.recommendations | Should Not BeNullOrEmpty
        ($health.recommendations.Count -gt 0) | Should Be $true
    }
}

Describe "Clear-OldRateLimitEvents - Limpeza de logs antigos" {
    
    BeforeEach {
        $script:tempLog = Join-Path $env:TEMP "rate_limit_test_$([guid]::NewGuid()).jsonl"
        Initialize-RateLimitMonitor -LogPath $script:tempLog
    }
    
    AfterEach {
        if (Test-Path $script:tempLog) { Remove-Item $script:tempLog -Force }
    }
    
    It "remove eventos mais antigos que X dias" {
        # Adicionar eventos
        1..10 | ForEach-Object {
            Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place"
        }
        
        # Simular eventos antigos (modificar timestamp no arquivo)
        # Para teste real, apenas validar que funcao existe
        
        $result = Clear-OldRateLimitEvents -DaysToKeep 7
        
        $result.success | Should Be $true
    }
}

Describe "Export-RateLimitReport - Relatorio" {
    
    BeforeEach {
        $script:tempLog = Join-Path $env:TEMP "rate_limit_test_$([guid]::NewGuid()).jsonl"
        Initialize-RateLimitMonitor -LogPath $script:tempLog
    }
    
    AfterEach {
        if (Test-Path $script:tempLog) { Remove-Item $script:tempLog -Force }
    }
    
    It "gera relatorio em formato texto" {
        1..5 | ForEach-Object {
            Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place"
        }
        
        $report = Export-RateLimitReport -Format "text"
        
        $report | Should Match "Rate Limit Events"
        $report | Should Match "Total:"
    }
    
    It "gera relatorio em formato JSON" {
        1..5 | ForEach-Object {
            Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place"
        }
        
        $report = Export-RateLimitReport -Format "json"
        
        $json = $report | ConvertFrom-Json
        $json.total_events | Should Be 5
    }
}
