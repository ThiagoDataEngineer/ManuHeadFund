# gem_executor_csv_fix.Tests.ps1
# TDD: Testes para corrigir bug de CSV em Write-GemTradeJournal
# 2026-05-29

Describe "Write-GemTradeJournal CSV Fix" {
    
    BeforeAll {
        # Setup
        $testDir = Join-Path $env:TEMP "gem_test_$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        $global:JOURNAL_DIR = $testDir
        
        # Dot-source a função
        . (Join-Path $PSScriptRoot "..\agents\gem_executor.ps1")
    }
    
    AfterAll {
        # Cleanup
        Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ========================================================================
    # TESTE 3: Validar que números não são corrompidos (InvariantCulture)
    # ========================================================================
    Context "Teste 3: Números com InvariantCulture" {
        
        It "Deve salvar preço com ponto decimal (não vírgula PT-BR)" {
            Write-GemTradeJournal -Market "INJUSDT" -Price 6.4235 -Qty 18.526056 `
                -StopPrice 4.3323 -TargetPrice 8.5 -SizingUsd 119.45 `
                -GemScore 95 -Mode "DISCOVERY" -MarketType "FUTURES" `
                -DryRun $false -OrderId "208723061381" -ToriSignal "ENTER"
            
            $csv = Get-Content (Join-Path $global:JOURNAL_DIR "gem_trades.csv") -Tail 1
            
            # Verificar que contém ponto, não vírgula
            ($csv -match "6\.4235") | Should Be $true
            ($csv -match "6,4235") | Should Be $false
        }
        
        It "Deve salvar quantidade com precisão completa" {
            Write-GemTradeJournal -Market "TESTUSDT" -Price 100 -Qty 18.526056 `
                -StopPrice 90 -TargetPrice 110 -SizingUsd 1852.6056 `
                -GemScore 85 -Mode "DISCOVERY" -MarketType "FUTURES" `
                -DryRun $false -OrderId "test123" -ToriSignal "ENTER"
            
            $csv = Get-Content (Join-Path $global:JOURNAL_DIR "gem_trades.csv") -Tail 1
            
            # Verificar que quantidade não foi truncada
            ($csv -match "18\.526056") | Should Be $true
        }
        
        It "Deve salvar sizing_usd sem corrupção" {
            Write-GemTradeJournal -Market "BTCUSDT" -Price 73928.30 -Qty 0.001 `
                -StopPrice 70000 -TargetPrice 80000 -SizingUsd 3715.79 `
                -GemScore 90 -Mode "DISCOVERY" -MarketType "FUTURES" `
                -DryRun $false -OrderId "btc123" -ToriSignal "ENTER"
            
            $csv = Get-Content (Join-Path $global:JOURNAL_DIR "gem_trades.csv") -Tail 1
            
            # Verificar que sizing foi salvo corretamente
            ($csv -match "3715\.79") | Should Be $true
        }
    }

    # ========================================================================
    # TESTE 2: Validar escape de aspas em campos de texto
    # ========================================================================
    Context "Teste 2: Escape de aspas em campos" {
        
        It "Deve escapar aspas em Market" {
            Write-GemTradeJournal -Market 'TEST"USDT' -Price 100 -Qty 1 `
                -StopPrice 90 -TargetPrice 110 -SizingUsd 100 `
                -GemScore 80 -Mode "DISCOVERY" -MarketType "FUTURES" `
                -DryRun $false -OrderId "test" -ToriSignal "ENTER"
            
            $csv = Get-Content (Join-Path $global:JOURNAL_DIR "gem_trades.csv") -Tail 1
            
            # Aspas devem ser escapadas como ""
            ($csv -match 'TEST""USDT') | Should Be $true
        }
        
        It "Deve escapar aspas em OrderId" {
            Write-GemTradeJournal -Market "INJUSDT" -Price 6.42 -Qty 18.5 `
                -StopPrice 4.33 -TargetPrice 8.5 -SizingUsd 119.45 `
                -GemScore 95 -Mode "DISCOVERY" -MarketType "FUTURES" `
                -DryRun $false -OrderId 'order"123' -ToriSignal "ENTER"
            
            $csv = Get-Content (Join-Path $global:JOURNAL_DIR "gem_trades.csv") -Tail 1
            
            # Aspas devem ser escapadas
            ($csv -match 'order""123') | Should Be $true
        }
        
        It "Deve escapar aspas em ToriSignal" {
            Write-GemTradeJournal -Market "INJUSDT" -Price 6.42 -Qty 18.5 `
                -StopPrice 4.33 -TargetPrice 8.5 -SizingUsd 119.45 `
                -GemScore 95 -Mode "DISCOVERY" -MarketType "FUTURES" `
                -DryRun $false -OrderId "test123" -ToriSignal 'ENTER"SIGNAL'
            
            $csv = Get-Content (Join-Path $global:JOURNAL_DIR "gem_trades.csv") -Tail 1
            
            # Aspas devem ser escapadas
            ($csv -match 'ENTER""SIGNAL') | Should Be $true
        }
    }

    # ========================================================================
    # TESTE 1: Validar estrutura completa do CSV
    # ========================================================================
    Context "Teste 1: Estrutura completa do CSV" {
        
        It "Deve criar header correto na primeira linha" {
            $csvFile = Join-Path $global:JOURNAL_DIR "gem_trades.csv"
            
            Write-GemTradeJournal -Market "INJUSDT" -Price 6.42 -Qty 18.5 `
                -StopPrice 4.33 -TargetPrice 8.5 -SizingUsd 119.45 `
                -GemScore 95 -Mode "DISCOVERY" -MarketType "FUTURES" `
                -DryRun $false -OrderId "test" -ToriSignal "ENTER"
            
            $lines = Get-Content $csvFile
            $header = $lines[0]
            
            # Verificar que header contém todas as colunas
            ($header -match "timestamp") | Should Be $true
            ($header -match "market") | Should Be $true
            ($header -match "price_entry") | Should Be $true
            ($header -match "qty") | Should Be $true
            ($header -match "stop_price") | Should Be $true
            ($header -match "target_price") | Should Be $true
            ($header -match "sizing_usd") | Should Be $true
            ($header -match "order_id") | Should Be $true
            ($header -match "tori_signal") | Should Be $true
        }
        
        It "Deve ter 17 colunas em cada linha" {
            $csv = Get-Content (Join-Path $global:JOURNAL_DIR "gem_trades.csv") -Tail 1
            $columns = $csv -split ","
            
            # Deve ter exatamente 17 colunas
            $columns.Count | Should Be 17
        }
        
        It "Deve salvar status como OPEN para novo trade" {
            Write-GemTradeJournal -Market "INJUSDT" -Price 6.42 -Qty 18.5 `
                -StopPrice 4.33 -TargetPrice 8.5 -SizingUsd 119.45 `
                -GemScore 95 -Mode "DISCOVERY" -MarketType "FUTURES" `
                -DryRun $false -OrderId "test" -ToriSignal "ENTER"
            
            $csv = Get-Content (Join-Path $global:JOURNAL_DIR "gem_trades.csv") -Tail 1
            
            # Status deve ser OPEN
            ($csv -match ",OPEN,") | Should Be $true
        }
        
        It "Deve salvar dry_run como false para trade real" {
            Write-GemTradeJournal -Market "INJUSDT" -Price 6.42 -Qty 18.5 `
                -StopPrice 4.33 -TargetPrice 8.5 -SizingUsd 119.45 `
                -GemScore 95 -Mode "DISCOVERY" -MarketType "FUTURES" `
                -DryRun $false -OrderId "test" -ToriSignal "ENTER"
            
            $csv = Get-Content (Join-Path $global:JOURNAL_DIR "gem_trades.csv") -Tail 1
            
            # dry_run deve ser false
            ($csv -match ",false,") | Should Be $true
        }
        
        It "Deve salvar dry_run como true para dry run" {
            Write-GemTradeJournal -Market "INJUSDT" -Price 6.42 -Qty 18.5 `
                -StopPrice 4.33 -TargetPrice 8.5 -SizingUsd 119.45 `
                -GemScore 95 -Mode "DISCOVERY" -MarketType "FUTURES" `
                -DryRun $true -OrderId "" -ToriSignal "ENTER"
            
            $csv = Get-Content (Join-Path $global:JOURNAL_DIR "gem_trades.csv") -Tail 1
            
            # dry_run deve ser true
            ($csv -match ",true,") | Should Be $true
        }
    }
}
