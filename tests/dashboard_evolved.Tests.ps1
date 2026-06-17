# dashboard_evolved.Tests.ps1 -- TDD para dashboard evoluido (4 fases)
# Valida a ESTRUTURA do arquivo dashboard/manu.html (contrato + features).
# ASCII-only de proposito (PS 5.1 sem BOM nao quebra). RED -> GREEN -> REFACTOR.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Describe "Dashboard Evolved - manu.html" {

    BeforeAll {
        $script:html = Get-Content ".\dashboard\manu.html" -Raw
    }

    Context "Contrato de publicacao (nao quebrar gh-pages)" {
        It "carrega manu_data.js (dados locais em claro)" {
            $script:html | Should Match 'manu_data\.js'
        }
        It "carrega manu_data.enc.js (dados cifrados online)" {
            $script:html | Should Match 'manu_data\.enc\.js'
        }
        It "carrega unlock.js (gate de senha)" {
            $script:html | Should Match 'unlock\.js'
        }
        It "define window.onDataReady (bootstrap do unlock.js)" {
            $script:html | Should Match 'window\.onDataReady'
        }
        It "tem viewport meta (mobile)" {
            $script:html | Should Match 'name="viewport"'
        }
    }

    Context "Fase 1 - Multi-tab (5 abas)" {
        It "tem aba Home" { $script:html | Should Match 'data-tab="home"' }
        It "tem aba Trades" { $script:html | Should Match 'data-tab="trades"' }
        It "tem aba Learning" { $script:html | Should Match 'data-tab="learning"' }
        It "tem aba System" { $script:html | Should Match 'data-tab="system"' }
        It "tem aba Settings" { $script:html | Should Match 'data-tab="settings"' }
        It "tem funcao de troca de aba" { $script:html | Should Match 'function switchTab' }
        It "tem secoes de conteudo por aba (tab-panel)" {
            ([regex]::Matches($script:html, 'class="tab-panel')).Count | Should BeGreaterThan 4
        }
    }

    Context "Fase 2 - Theme selector (3 temas)" {
        It "suporta tema dark via data-theme" { $script:html | Should Match '\[data-theme="dark"\]' }
        It "suporta tema light" { $script:html | Should Match '\[data-theme="light"\]' }
        It "suporta tema terminal" { $script:html | Should Match '\[data-theme="terminal"\]' }
        It "usa CSS variables (--bg)" { $script:html | Should Match '--bg' }
        It "tem funcao setTheme" { $script:html | Should Match 'function setTheme' }
        It "persiste tema em localStorage" { $script:html | Should Match 'localStorage' }
    }

    Context "Fase 3 - Graficos animados" {
        It "tem render de curva PnL" { $script:html | Should Match 'function renderPnlCurve' }
        It "tem render de win-rate (grafico)" { $script:html | Should Match 'function renderWinRateChart' }
        It "tem render de gauge/confluence" { $script:html | Should Match 'function renderGauge' }
        It "usa SVG para graficos inline" { $script:html | Should Match '<svg' }
        It "tem animacao CSS (keyframes ou transition)" {
            ($script:html -match '@keyframes' -or $script:html -match 'transition:') | Should Be $true
        }
        It "tenta ApexCharts (CDN) com fallback" { $script:html | Should Match 'ApexCharts' }
    }

    Context "Fase 4 - Real-time" {
        It "tem auto-refresh via setInterval" { $script:html | Should Match 'setInterval' }
        It "tem indicador de status (status-dot)" { $script:html | Should Match 'status-dot' }
        It "tem timestamp relativo (atualizado ha)" {
            ($script:html -match 'atualizado' -or $script:html -match 'last-update') | Should Be $true
        }
        It "re-renderiza ao atualizar (loadAll)" { $script:html | Should Match 'function loadAll' }
    }

    Context "Render de dados (campos reais do JSON)" {
        It "le capital" { $script:html | Should Match 'capital' }
        It "le trailing_stop" { $script:html | Should Match 'trailing_stop' }
        It "le trading_metrics" { $script:html | Should Match 'trading_metrics' }
        It "le pnl_curve" { $script:html | Should Match 'pnl_curve' }
        It "le market_regime" { $script:html | Should Match 'market_regime' }
        It "le whale_signals" { $script:html | Should Match 'whale_signals' }
        It "le llm_costs" { $script:html | Should Match 'llm_costs' }
    }
}
