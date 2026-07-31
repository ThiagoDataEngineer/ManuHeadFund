# trailing_unified_promotion_2026_07_29.Tests.ps1 -- TDD da promocao do
# motor de trailing unificado (lib_trailing_unified.ps1, Resolve-TrailingDecision)
# de SHADOW pra ATIVO em scripts/trailing_stop_monitor.ps1.
#
# Contexto: owner reportou ao vivo posicoes "seta apaga seta apaga" (TP/SL
# some por alguns minutos, depois volta) -- causa raiz confirmada: 2 motores
# fragmentados (Update-AllTrailingStops, Invoke-TrailingPolicyLive) calculando
# o stop de forma independente, cada chamada set-position-stop-loss (sem
# stop_loss_amount) cancela/recria a ordem anterior na CoinEx. Evidencia real
# (1000 observacoes shadow desde 2026-07-19, 73.7% would_have_differed=true,
# sempre na direcao de proteger MAIS cedo/forte) deu suporte pra promover.
#
# Owner tambem pediu explicitamente: SPOT deve usar a MESMA logica de decisao
# (ATR+exhaustion+trendline) que FUTURES -- so o TIPO de execucao muda (ordem
# SPOT normal via Sync-SpotStopsToExchange, nao modify-position).
#
# Pester 3.4 / ASCII-only. Testes read-only sobre o conteudo do script (nao
# executa o monitor inteiro -- setup de rede/credenciais e' grande demais pra
# TDD unitario; mesmo padrao ja usado em online_trailing_executor.Tests.ps1).

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Describe "trailing_stop_monitor.ps1 -- motores fragmentados desativados" {

    BeforeAll {
        $script:mon = Get-Content ".\scripts\trailing_stop_monitor.ps1" -Raw
    }

    It "Update-AllTrailingStops NAO e mais chamado incondicionalmente (guard `$false)" {
        ($script:mon -match '\$false\s+-and\s+\(Get-Command\s+Update-AllTrailingStops') | Should Be $true
    }

    It "Invoke-TrailingPolicyLive NAO e mais chamado incondicionalmente (guard `$false)" {
        ($script:mon -match '\$false\s+-and\s+\(Test-Path\s+\$tpFlag\)') | Should Be $true
    }

    It "codigo legado permanece no arquivo (comentado/desativado, nao apagado -- rollback facil)" {
        ($script:mon -match [regex]::Escape('Update-AllTrailingStops -DryRun $false')) | Should Be $true
        ($script:mon -match [regex]::Escape('Invoke-TrailingPolicyLive -Positions')) | Should Be $true
    }

    It "Sync-TrailingToExchange NAO e mais chamado incondicionalmente -- 3o motor fragmentado achado pos-promocao (2026-07-30, guard `$false)" {
        # Confirmado em producao (runs 30517140015/30514386549/30511299233):
        # Sync-TrailingToExchange rodava sem guard LOGO DEPOIS do bloco UNIFIED,
        # lia o journal que o UNIFIED tinha acabado de atualizar e empurrava o
        # MESMO stop de novo (SL_PUSH SOLUSDT/SUIUSDT com melhora de 0.09%-4%
        # minutos apos o UNIFIED ja ter processado a mesma posicao) -- um 2o
        # cancelamento/recriacao de ordem por ciclo, mesma classe de bug da
        # promocao original (2 motores concorrentes = colisao by design da API).
        ($script:mon -match '\$false\s+-and\s+\(Get-Command\s+Sync-TrailingToExchange') | Should Be $true
        ($script:mon -match [regex]::Escape('$sync = Sync-TrailingToExchange')) | Should Be $true
    }
}

Describe "trailing_stop_monitor.ps1 -- motor unificado ATIVO" {

    BeforeAll {
        $script:mon = Get-Content ".\scripts\trailing_stop_monitor.ps1" -Raw
    }

    It "carrega lib_tori_proximity (trendline, dependencia do 3o fator)" {
        ($script:mon -match "lib_tori_proximity") | Should Be $true
    }

    It "chama Resolve-TrailingDecision (motor unico)" {
        ($script:mon -match "Resolve-TrailingDecision") | Should Be $true
    }

    It "empurra o stop real via CoinEx-ModifyPositionStopLoss quando FUTURES" {
        ($script:mon -match 'tuActive\s+-and\s+\$tuIsFutures\s+-and\s+\(Get-Command\s+CoinEx-ModifyPositionStopLoss') | Should Be $true
    }

    It "atualiza o journal via Save-TrailingPositions para SPOT mesmo sem push direto (mesma logica de saida, execucao via Sync-SpotStopsToExchange)" {
        ($script:mon -match '\(-not\s+\$tuIsFutures\)\s+-or\s+\$tuPushed') | Should Be $true
    }

    It "persiste telemetria em trailing_unified_shadow com campo pushed_live (rastreia se o push real aconteceu)" {
        ($script:mon -match "pushed_live") | Should Be $true
    }

    It "Sync-SpotStopsToExchange roda DEPOIS do bloco unificado (ordem no arquivo -- SPOT executa a decisao ja atualizada no journal)" {
        $idxUnified = $script:mon.IndexOf("2.55c TRAILING UNIFIED")
        $idxSpotSync = $script:mon.IndexOf("Sync-SpotStopsToExchange -Positions")
        ($idxUnified -ge 0) | Should Be $true
        ($idxSpotSync -ge 0) | Should Be $true
        ($idxUnified -lt $idxSpotSync) | Should Be $true
    }
}

Describe "lib_trailing_unified.ps1 -- carregado com dependencias corretas" {

    It "arquivo existe e faz parse limpo" {
        $path = ".\agents\lib_trailing_unified.ps1"
        (Test-Path $path) | Should Be $true
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors) | Out-Null
        $errors.Count | Should Be 0
    }

    It "Resolve-TrailingDecision fica disponivel apos dot-source na ordem exigida" {
        . ".\agents\lib_trailing_exhaustion.ps1"
        . ".\agents\lib_multiframe_analysis.ps1"
        . ".\agents\lib_trailing_stop_intelligent.ps1"
        . ".\agents\lib_tori_proximity.ps1"
        . ".\agents\lib_trailing_unified.ps1"
        (Get-Command Resolve-TrailingDecision -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
    }
}

Describe "trailing_stop_monitor.ps1 -- execucao REAL de PARTIAL/EXIT (2026-07-31)" {

    BeforeAll {
        $script:mon = Get-Content ".\scripts\trailing_stop_monitor.ps1" -Raw
    }

    It "carrega lib_trailing_partial_exit.ps1 (Register-PartialExitLadder)" {
        ($script:mon -match [regex]::Escape('lib_trailing_partial_exit.ps1')) | Should Be $true
    }

    It "gated por PARTIAL_EXIT_EXECUTION_ENABLED.flag -- ausencia = so log, comportamento antigo preservado" {
        ($script:mon -match [regex]::Escape('PARTIAL_EXIT_EXECUTION_ENABLED.flag')) | Should Be $true
    }

    It "so executa em FUTURES (tuIsFutures) -- SPOT fica so no log por enquanto" {
        ($script:mon -match '\$tuIsFutures\s+-and\s+\(Test-Path\s+\$tuPartialFlag\)') | Should Be $true
    }

    It "busca quantidade real via CoinEx-GetPendingPositions (nao existe no journal trailing_state)" {
        ($script:mon -match [regex]::Escape('CoinEx-GetPendingPositions -Market $tuMarket')) | Should Be $true
    }

    It "chama Register-PartialExitLadder com a posicao real e os partials da policy atual" {
        ($script:mon -match [regex]::Escape('Register-PartialExitLadder -Position $tuLadderPos')) | Should Be $true
    }

    It "EXIT (reversao/time-stop) fecha a posicao INTEIRA via CoinEx-ClosePosition -- nao registra ladder parcial" {
        # 2026-07-31 FIX: perfil 'runner' tem partials=@() de proposito ("dinheiro
        # da casa", ver lib_trailing_policy.ps1) -- so sai via EXIT (reversao
        # confirmada/time-stop), nunca via PARTIAL. Tratar EXIT igual a PARTIAL
        # registraria um ladder vazio em vez de fechar a posicao inteira quando
        # o motor ja decidiu que a tese do trade acabou.
        ($script:mon -match [regex]::Escape('$tuDecision.action -eq "EXIT"')) | Should Be $true
        ($script:mon -match [regex]::Escape('CoinEx-ClosePosition $tuMarket')) | Should Be $true
    }

    It "PARTIAL e EXIT sao ramos DISTINTOS (elseif), nao o mesmo tratamento" {
        ($script:mon -match [regex]::Escape('$tuDecision.action -eq "PARTIAL" -and (Get-Command Register-PartialExitLadder')) | Should Be $true
    }
}
