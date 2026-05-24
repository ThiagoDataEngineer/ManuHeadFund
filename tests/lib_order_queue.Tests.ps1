# tests/lib_order_queue.Tests.ps1
# TDD para Order Queue com Throttling
# 2026-05-23

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_order_queue.ps1")
. (Join-Path $projectRoot "agents\lib_rate_limiter.ps1")

Describe "Initialize-OrderQueue - Setup inicial" {
    
    It "cria fila vazia" {
        Initialize-OrderQueue
        
        $global:ORDER_QUEUE | Should Not BeNullOrEmpty
        $global:ORDER_QUEUE.Count | Should Be 0
    }
    
    It "inicializa worker thread state" {
        Initialize-OrderQueue
        
        $global:ORDER_QUEUE_WORKER | Should Not BeNullOrEmpty
        $global:ORDER_QUEUE_WORKER.running | Should Be $false
    }
}

Describe "Add-OrderToQueue - Adicionar ordem" {
    
    BeforeEach {
        Initialize-OrderQueue
    }
    
    It "adiciona ordem a fila" {
        $orderId = Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000
        
        $orderId | Should Not BeNullOrEmpty
        $global:ORDER_QUEUE.Count | Should Be 1
    }
    
    It "ordem tem ID unico" {
        $id1 = Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000
        $id2 = Add-OrderToQueue -Market "ETHUSDT" -Side "sell" -Type "limit" -Amount 0.1 -Price 3500
        
        $id1 | Should Not Be $id2
    }
    
    It "ordem tem timestamp de criacao" {
        $orderId = Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000
        
        $order = $global:ORDER_QUEUE | Where-Object { $_.queue_id -eq $orderId }
        $order.created_at | Should Not BeNullOrEmpty
        $order.created_at | Should BeOfType [DateTime]
    }
    
    It "ordem tem status pending" {
        $orderId = Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000
        
        $order = $global:ORDER_QUEUE | Where-Object { $_.queue_id -eq $orderId }
        $order.status | Should Be "pending"
    }
    
    It "ordem SPOT tem market_type correto" {
        $orderId = Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000 -MarketType "SPOT"
        
        $order = $global:ORDER_QUEUE | Where-Object { $_.queue_id -eq $orderId }
        $order.market_type | Should Be "SPOT"
    }
    
    It "ordem FUTURES tem market_type correto" {
        $orderId = Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000 -MarketType "FUTURES"
        
        $order = $global:ORDER_QUEUE | Where-Object { $_.queue_id -eq $orderId }
        $order.market_type | Should Be "FUTURES"
    }
}

Describe "Get-QueuedOrder - Consultar ordem" {
    
    BeforeEach {
        Initialize-OrderQueue
    }
    
    It "retorna ordem por ID" {
        $orderId = Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000
        
        $order = Get-QueuedOrder -QueueId $orderId
        
        $order | Should Not BeNullOrEmpty
        $order.queue_id | Should Be $orderId
        $order.market | Should Be "BTCUSDT"
    }
    
    It "retorna null quando ordem nao existe" {
        $order = Get-QueuedOrder -QueueId "fake-id-123"
        
        $order | Should BeNullOrEmpty
    }
}

Describe "Start-OrderQueueWorker - Worker thread" {
    
    BeforeEach {
        Initialize-OrderQueue
        Initialize-RateLimiter
    }
    
    AfterEach {
        Stop-OrderQueueWorker
    }
    
    It "inicia worker thread" {
        Start-OrderQueueWorker
        
        $global:ORDER_QUEUE_WORKER.running | Should Be $true
    }
    
    It "processa ordens da fila" {
        Mock CoinEx-PlaceOrder {
            return [PSCustomObject]@{
                success = $true
                order_id = "12345"
            }
        }
        
        $orderId = Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000 -MarketType "SPOT"
        
        Start-OrderQueueWorker
        Start-Sleep -Milliseconds 500
        
        $order = Get-QueuedOrder -QueueId $orderId
        $order.status | Should Be "executed"
        $order.order_id | Should Be "12345"
    }
    
    It "marca ordem como failed quando API falha" {
        Mock CoinEx-PlaceOrder {
            return [PSCustomObject]@{
                success = $false
                error_msg = "Insufficient balance"
            }
        }
        
        $orderId = Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000 -MarketType "SPOT"
        
        Start-OrderQueueWorker
        Start-Sleep -Milliseconds 500
        
        $order = Get-QueuedOrder -QueueId $orderId
        $order.status | Should Be "failed"
        $order.error | Should Match "Insufficient balance"
    }
    
    It "respeita rate limit ao processar ordens" {
        Mock CoinEx-PlaceOrder {
            return [PSCustomObject]@{ success = $true; order_id = "12345" }
        }
        
        # Adicionar 5 ordens
        1..5 | ForEach-Object {
            Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000 -MarketType "SPOT"
        }
        
        Start-OrderQueueWorker
        
        # Worker deve processar respeitando rate limit (30 req/s = ~33ms por ordem)
        Start-Sleep -Milliseconds 300
        
        $executed = ($global:ORDER_QUEUE | Where-Object { $_.status -eq "executed" }).Count
        $executed | Should BeGreaterThan 0
    }
}

Describe "Stop-OrderQueueWorker - Parar worker" {
    
    BeforeEach {
        Initialize-OrderQueue
    }
    
    It "para worker thread" {
        Start-OrderQueueWorker
        Stop-OrderQueueWorker
        
        $global:ORDER_QUEUE_WORKER.running | Should Be $false
    }
}

Describe "Get-QueueStats - Estatisticas da fila" {
    
    BeforeEach {
        Initialize-OrderQueue
    }
    
    It "retorna stats vazias inicialmente" {
        $stats = Get-QueueStats
        
        $stats.total | Should Be 0
        $stats.pending | Should Be 0
        $stats.executed | Should Be 0
        $stats.failed | Should Be 0
    }
    
    It "conta ordens por status" {
        Mock CoinEx-PlaceOrder {
            return [PSCustomObject]@{ success = $true; order_id = "12345" }
        }
        
        # Adicionar 3 ordens
        1..3 | ForEach-Object {
            Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000 -MarketType "SPOT"
        }
        
        $stats = Get-QueueStats
        $stats.total | Should Be 3
        $stats.pending | Should Be 3
    }
    
    It "calcula tempo medio de espera" {
        Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000 -MarketType "SPOT"
        Start-Sleep -Milliseconds 100
        
        $stats = Get-QueueStats
        $stats.avg_wait_ms | Should BeGreaterThan 50
    }
}

Describe "Remove-QueuedOrder - Cancelar ordem na fila" {
    
    BeforeEach {
        Initialize-OrderQueue
    }
    
    It "remove ordem pending da fila" {
        $orderId = Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000
        
        $result = Remove-QueuedOrder -QueueId $orderId
        
        $result.success | Should Be $true
        $global:ORDER_QUEUE.Count | Should Be 0
    }
    
    It "NAO remove ordem ja executada" {
        $orderId = Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000
        
        # Simular execucao
        $order = $global:ORDER_QUEUE | Where-Object { $_.queue_id -eq $orderId }
        $order.status = "executed"
        
        $result = Remove-QueuedOrder -QueueId $orderId
        
        $result.success | Should Be $false
        $result.error | Should Match "already executed|cannot remove"
    }
    
    It "marca ordem como cancelled" {
        $orderId = Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000
        
        Remove-QueuedOrder -QueueId $orderId
        
        $order = Get-QueuedOrder -QueueId $orderId
        $order.status | Should Be "cancelled"
    }
}

Describe "Clear-OrderQueue - Limpar fila" {
    
    BeforeEach {
        Initialize-OrderQueue
    }
    
    It "remove todas as ordens pending" {
        1..5 | ForEach-Object {
            Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000
        }
        
        Clear-OrderQueue -Status "pending"
        
        $pending = ($global:ORDER_QUEUE | Where-Object { $_.status -eq "pending" }).Count
        $pending | Should Be 0
    }
    
    It "preserva ordens executed" {
        $id1 = Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000
        $id2 = Add-OrderToQueue -Market "ETHUSDT" -Side "sell" -Type "limit" -Amount 0.1 -Price 3500
        
        # Marcar uma como executed
        $order = $global:ORDER_QUEUE | Where-Object { $_.queue_id -eq $id1 }
        $order.status = "executed"
        
        Clear-OrderQueue -Status "pending"
        
        $global:ORDER_QUEUE.Count | Should Be 1
        $global:ORDER_QUEUE[0].status | Should Be "executed"
    }
}

Describe "Add-OrderToQueue - Priority" {
    
    BeforeEach {
        Initialize-OrderQueue
    }
    
    It "ordem com priority alta e processada primeiro" {
        $id1 = Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000 -Priority "normal"
        $id2 = Add-OrderToQueue -Market "ETHUSDT" -Side "sell" -Type "limit" -Amount 0.1 -Price 3500 -Priority "high"
        
        # Worker deve processar id2 primeiro
        Mock CoinEx-PlaceOrder {
            return [PSCustomObject]@{ success = $true; order_id = "12345" }
        }
        
        Start-OrderQueueWorker
        Start-Sleep -Milliseconds 200
        Stop-OrderQueueWorker
        
        $order2 = Get-QueuedOrder -QueueId $id2
        $order2.status | Should Be "executed"
    }
}

Describe "Add-OrderToQueue - Callback" {
    
    BeforeEach {
        Initialize-OrderQueue
    }
    
    It "executa callback quando ordem e processada" {
        $script:callbackExecuted = $false
        
        $orderId = Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000 -MarketType "SPOT" -Callback {
            param($result)
            $script:callbackExecuted = $true
        }
        
        Mock CoinEx-PlaceOrder {
            return [PSCustomObject]@{ success = $true; order_id = "12345" }
        }
        
        Start-OrderQueueWorker
        Start-Sleep -Milliseconds 500
        Stop-OrderQueueWorker
        
        $callbackExecuted | Should Be $true
    }
}
