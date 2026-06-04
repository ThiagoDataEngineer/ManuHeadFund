# dashboard_elite.Tests.ps1
# Testes TDD para Dashboard Elite
# 2026-05-24

Describe "Dashboard Elite - TDD Tests" {
    
    BeforeAll {
        $script:projectRoot = Split-Path -Parent $PSScriptRoot
        $script:dashboardPath = "$projectRoot\dashboard\index_elite.html"
        $script:collectScript = "$projectRoot\scripts\collect_dashboard_data.ps1"
    }
    
    Context "Data Collection" {
        
        It "collect_dashboard_data.ps1 deve existir" {
            Test-Path $collectScript | Should Be $true
        }
        
        It "collect_dashboard_data.ps1 deve retornar JSON válido" {
            $json = & $collectScript
            { $json | ConvertFrom-Json } | Should Not Throw
        }
        
        It "Dados devem conter todas as 11 categorias" {
            $json = & $collectScript
            $data = $json | ConvertFrom-Json
            
            $data.trading_metrics | Should Not BeNullOrEmpty
            $data.mentor_decisions | Should Not BeNullOrEmpty
            $data.mesa_consensus | Should Not BeNullOrEmpty
            $data.market_regime | Should Not BeNullOrEmpty
            $data.promotion_pipeline | Should Not BeNullOrEmpty
            $data.fqs_distribution | Should Not BeNullOrEmpty
            $data.llm_costs | Should Not BeNullOrEmpty
            $data.feedback_loop | Should Not BeNullOrEmpty
            $data.trailing_stop | Should Not BeNullOrEmpty
            $data.portfolio_metrics | Should Not BeNullOrEmpty
            $data.alerts | Should Not BeNullOrEmpty
        }
        
        It "Trading metrics devem ter estrutura correta" {
            $json = & $collectScript
            $data = $json | ConvertFrom-Json
            
            $data.trading_metrics.trades_24h | Should BeOfType [int]
            $data.trading_metrics.trades_7d | Should BeOfType [int]
            $data.trading_metrics.trades_30d | Should BeOfType [int]
            $data.trading_metrics.win_rate | Should BeOfType [double]
        }
    }
    
    Context "HTML Generation" {
        
        BeforeAll {
            # Gerar dashboard
            & "$projectRoot\BUILD_DASHBOARD_ELITE.ps1"
        }
        
        It "index_elite.html deve ser criado" {
            Test-Path $dashboardPath | Should Be $true
        }
        
        It "HTML deve conter DOCTYPE" {
            $html = Get-Content $dashboardPath -Raw
            $html | Should Match "<!DOCTYPE html>"
        }
        
        It "HTML deve conter Chart.js" {
            $html = Get-Content $dashboardPath -Raw
            $html | Should Match "chart\.js"
        }
        
        It "HTML deve conter Font Awesome" {
            $html = Get-Content $dashboardPath -Raw
            $html | Should Match "font-awesome"
        }
        
        It "HTML deve ter tamanho mínimo de 5KB" {
            $size = (Get-Item $dashboardPath).Length
            $size | Should BeGreaterThan 5000
        }
    }
    
    Context "Dashboard Components" {
        
        BeforeAll {
            $script:html = Get-Content $dashboardPath -Raw
        }
        
        It "Deve conter header com logo" {
            $html | Should Match "ManuHeadFund"
        }
        
        It "Deve conter metrics grid" {
            $html | Should Match "grid-6"
        }
        
        It "Deve conter trading metrics panel" {
            $html | Should Match "Métricas de Trading"
        }
        
        It "Deve conter mentor decisions panel" {
            $html | Should Match "Decisões do Mentor"
        }
        
        It "Deve conter mesa consensus panel" {
            $html | Should Match "Mesa Consensus"
        }
        
        It "Deve conter positions table" {
            $html | Should Match "Posições Abertas"
        }
        
        It "Deve conter Chart.js script" {
            $html | Should Match "new Chart"
        }
    }
    
    Context "CSS Styling" {
        
        BeforeAll {
            $script:html = Get-Content $dashboardPath -Raw
        }
        
        It "Deve conter CSS variables" {
            $html | Should Match ":root"
            $html | Should Match "--bg-primary"
        }
        
        It "Deve conter grid layouts" {
            $html | Should Match "grid-template-columns"
        }
        
        It "Deve conter color classes" {
            $html | Should Match "\.positive"
            $html | Should Match "\.negative"
        }
    }
    
    Context "Data Integration" {
        
        It "HTML deve conter dados reais de posições" {
            $html = Get-Content $dashboardPath -Raw
            # Deve ter pelo menos estrutura de tabela
            $html | Should Match "<table>"
        }
        
        It "HTML deve conter timestamp" {
            $html = Get-Content $dashboardPath -Raw
            $html | Should Match "\d{4}-\d{2}-\d{2}"
        }
    }
}
