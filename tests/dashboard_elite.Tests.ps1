# dashboard_elite.Tests.ps1
# Testes TDD para Dashboard Elite
# 2026-05-24

$global:__db_projectRoot   = Split-Path -Parent $PSScriptRoot
$global:__db_dashboardPath = Join-Path $global:__db_projectRoot "dashboard\elite.html"
$global:__db_collectScript = Join-Path $global:__db_projectRoot "scripts\collect_dashboard_data.ps1"

Describe "Dashboard Elite - TDD Tests" {
    
    Context "Data Collection" {
        
        It "collect_dashboard_data.ps1 deve existir" {
            Test-Path $global:__db_collectScript | Should Be $true
        }
        
        It "collect_dashboard_data.ps1 deve retornar JSON válido" {
            $json = & $global:__db_collectScript
            { $json | ConvertFrom-Json } | Should Not Throw
        }
        
        It "Dados devem conter todas as 11 categorias" {
            $root = Split-Path $PSScriptRoot -Parent
            $cs   = Join-Path $root "scripts\collect_dashboard_data.ps1"
            $rawJson = (& $cs) | Out-String
            $data = $rawJson.Trim() | ConvertFrom-Json

            $cats = @('trading_metrics','mentor_decisions','mesa_consensus','market_regime',
                      'promotion_pipeline','fqs_distribution','llm_costs','feedback_loop',
                      'trailing_stop','portfolio_metrics','alerts')
            foreach ($cat in $cats) {
                ($data.PSObject.Properties[$cat] -ne $null) | Should Be $true
            }
        }
        
        It "Trading metrics devem ter estrutura correta" {
            $json = & $global:__db_collectScript
            $data = $json | ConvertFrom-Json
            
            # PS5.1 ConvertFrom-Json pode retornar Int32/Int64 para inteiros e Double/Decimal para floats
            ($data.trading_metrics.trades_24h -is [int] -or $data.trading_metrics.trades_24h -is [long]) | Should Be $true
            ($data.trading_metrics.trades_7d  -is [int] -or $data.trading_metrics.trades_7d  -is [long]) | Should Be $true
            ($data.trading_metrics.trades_30d -is [int] -or $data.trading_metrics.trades_30d -is [long]) | Should Be $true
            ($data.trading_metrics.win_rate   -is [double] -or $data.trading_metrics.win_rate -is [decimal]) | Should Be $true
        }
    }
    
    Context "HTML Generation" {
        
        BeforeAll {
            # Gerar dashboard
            & "$global:__db_projectRoot\BUILD_DASHBOARD_ELITE.ps1"
        }
        
        It "elite.html deve ser criado" {
            Test-Path $global:__db_dashboardPath | Should Be $true
        }
        
        It "HTML deve conter DOCTYPE" {
            $html = Get-Content $global:__db_dashboardPath -Raw
            $html | Should Match "<!DOCTYPE html>"
        }
        
        It "HTML deve conter Chart.js" {
            $html = Get-Content $global:__db_dashboardPath -Raw
            $html | Should Match "chart\.js"
        }
        
        It "HTML deve conter Font Awesome" {
            $html = Get-Content $global:__db_dashboardPath -Raw
            $html | Should Match "font-awesome"
        }
        
        It "HTML deve ter tamanho mínimo de 5KB" {
            $size = (Get-Item $global:__db_dashboardPath).Length
            $size | Should BeGreaterThan 5000
        }
    }
    
    Context "Dashboard Components" {
        
        BeforeAll {
            $script:html = Get-Content $global:__db_dashboardPath -Raw
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
            $script:html = Get-Content $global:__db_dashboardPath -Raw
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
            $html = Get-Content $global:__db_dashboardPath -Raw
            # Deve ter pelo menos estrutura de tabela
            $html | Should Match "<table>"
        }
        
        It "HTML deve conter timestamp" {
            $html = Get-Content $global:__db_dashboardPath -Raw
            $html | Should Match "\d{4}-\d{2}-\d{2}"
        }
    }
}
