# Auditoria de libs órfãs em agents/ (2026-07-23)

Metodologia: análise AST cruzando funções definidas em cada `lib_*.ps1` vs.
chamadas reais em qualquer `agents/*.ps1` ou `scripts/*.ps1` (excluindo a
própria lib). `lib_loader_auto.ps1` carrega automaticamente TODOS os
lib_*.ps1 via dot-source -- ou seja, "carregado" não significa "usado".
62 arquivos identificados sem nenhuma função efetivamente chamada por
qualquer motor real (gem_executor/gem_loop/faro_v3/scan_master/mentor_agent
etc).

## FEATURE_PRONTA_NAO_CONECTADA (17) -- tem teste Pester passando, função completa, nunca chamada

- lib_alpha_wire.ps1 -- migra coluna alpha_vs_btc, Add-AlphaColumnToCsv nunca chamado
- lib_asymmetric_demote.ps1 -- Invoke-AutoDemoteIfNeeded nunca chamado por cron real
- lib_btc_regime_gate.ps1 -- gate BTC-core "causa real das perdas" (comentário próprio), nunca chamado
- lib_chart_patterns_engulfing.ps1 -- Detect-EngulfingPattern pronta, engine usa lib_chart_patterns.ps1 (ativo)
- lib_cold_wallet_alert.ps1 -- Invoke-HotWalletAuditAndAlert, nenhum cron chama
- lib_correlation_rolling.ps1 -- detector de correlação rolling completo, sem chamador
- lib_gate_safety.ps1 -- utilitário fail-closed pronto, sem uso real
- lib_human_approval_simple.ps1 -- Request-HumanApproval (>$100), substituído por fluxo Telegram approval
- lib_minmax_detector.ps1 -- helpers min/max 24h/7d, sem chamador
- lib_news_entry_boost.ps1 -- boost de score por news, não plugado em gem_executor
- lib_rate_limit_monitor.ps1 -- observabilidade rate-limit, lib_coinex_retry.ps1 tem a própria
- lib_rebalancing_daemon.ps1 -- também DUPLICATA (ver abaixo)
- lib_router_spot_futures.ps1 -- também DUPLICATA (ver abaixo)
- lib_state_reconcile.ps1 -- reconciliação testada, lib_position_sync_live.ps1 (ativo) cobre isso hoje
- lib_supabase_management.ps1 -- Management API/DDL, uso manual ad-hoc
- lib_triple_barrier_backtest.ps1 -- Invoke-TripleBarrier, só consumido manualmente
- lib_whale_detection.ps1 -- produção usa lib_whale_watcher.ps1 (ativo)

## DUPLICATA_DE_OUTRO_ARQUIVO_ATIVO (7)

- lib_rebalancing_daemon.ps1 -- lib_portfolio_rebalance.ps1 o chama de "dead code" em comentário
- lib_router_spot_futures.ps1 -- substituído por lib_market_router.ps1 + lib_market_router_wire.ps1 (ativos)
- lib_tori_simplified.ps1 -- lógica real está em lib_tori_gate_wrapper.ps1 (ativo)
- lib_vol_climax_optimized.ps1 -- produção usa lib_vol_climax_gate.ps1 + lib_vol_climax_integration.ps1 (ativos)
- lib_signal_generator_short.ps1 -- produção usa lib_short_signals.ps1 + lib_short_executor.ps1 (ativos)
- lib_sizing_centralized.ps1 -- pretendia ser "single source of truth" mas produção usa lib_sizing_dynamics.ps1/lib_executor_sizing.ps1/lib_kelly_wire.ps1
- lib_mesa_consensus_relaxed.ps1 -- compete com lib_mesa_relaxed_criteria.ps1 (também órfã) pela mesma responsabilidade

**NOTA IMPORTANTE:** lib_sizing_centralized.ps1 está classificado como duplicata/órfão
neste relatório, MAS eu já corrigi e commitei testes reais pra ele nesta mesma sessão
(tests/sizing_centralized.Tests.ps1, 10/10 pass, commit f4ddbc2) sob a premissa de que
era usado. Preciso reconciliar isso: confirmar com grep se Get-SafePositionSize é
chamado por gem_executor.ps1 ou não antes de decidir islamiento.

## LIXO_MORTO_CONFIRMADO (38)

2 intencionais confirmados pelo owner (CLAUDE.md): lib_mentor_rebalancer.ps1,
lib_realtime_position_analyzer.ps1 (vazios).

Demais 36 sem teste correspondente, sem chamador real:
lib_auto_demote_cron.ps1, lib_coinex_news.ps1, lib_dsr_confidence_advanced.ps1,
lib_dsr_live_audit.ps1, lib_faro_margin_safety.ps1, lib_faro_ml_confidence.ps1,
lib_fqs_default_quality.ps1, lib_http_error_monitor.ps1, lib_idempotency.ps1,
lib_live_integration.ps1, lib_llm_cost_telemetry.ps1, lib_llm_quota_optimizer.ps1,
lib_macro_audit.ps1, lib_market_context.ps1, lib_mce_gates.ps1,
lib_mentor_calibration.ps1, lib_mentor_hallucination_detector.ps1 (**ver alerta abaixo**),
lib_mentor_rules.ps1, lib_mesa_relaxed_criteria.ps1, lib_override_expiry.ps1,
lib_performance_refiner.ps1, lib_portfolio_rebalance.ps1 (nota: pretendia substituir
lib_rebalancing_daemon mas também nunca foi conectado), lib_prediction_engine.ps1,
lib_profit_taking_milestone.ps1 (já investigado nesta sessão -- intencionalmente não
conectado, TODO de withdrawal real pendente), lib_regime_detector_audit.ps1,
lib_self_learning.ps1, lib_short_pipeline_advanced.ps1, lib_short_rampup.ps1,
lib_signal_calibration.ps1, lib_telegram_essential_alerts.ps1,
lib_tori_integration_audit.ps1, lib_trailing_executor_phase2.ps1, lib_trailing_macro.ps1,
lib_trailing_microstructure.ps1, lib_trailing_state.ps1, lib_volatility_filter.ps1
(**ver alerta abaixo**)

## FERRAMENTA_VALIDACAO_MANUAL (0 dentre as 62)

Nenhuma das 62 se qualificou puramente aqui -- ferramentas de backtest/diagnóstico
reais do projeto vivem em scripts/ (diag_*.ps1, faro_v3_backtest_*.ps1) e SÃO
chamadas pelo workflow via workflow_dispatch, não contam como órfãs.

## ALERTAS DE RISCO REAL (requerem decisão, não só limpeza)

1. **lib_volatility_filter.ps1** nunca chamado -- pode ser um GATE DE RISCO
   ausente do pipeline (filtro de volatilidade de entrada). Precisa confirmar
   se é intencional ou gap real antes de arquivar.
2. **lib_mentor_hallucination_detector.ps1** é dot-sourceado por gem_loop.ps1
   mas nenhuma função é chamada -- e há corroboração no próprio
   tests/contract_dependencies.Tests.ps1 (baseline de "chamadas mortas" já
   rastreadas) de que Test-MentorFqsHallucination é legado conhecido. Sugere
   que a detecção de alucinação do Mentor NUNCA foi de fato ligada ao pipeline
   live apesar do nome crítico.
3. **lib_sizing_centralized.ps1** -- reconciliar com o fix já commitado nesta
   sessão (f4ddbc2) antes de decidir. Se realmente não é chamado por
   gem_executor.ps1, os testes que acabei de consertar validam uma função
   morta -- verificar com grep antes de arquivar ou remover os testes.

## CORRECAO CRITICA (2026-07-23, commit c801893)

O commit 331c6b1 (abaixo) foi REVERTIDO. Ao converter tests/tori_and_fqs.Tests.ps1
(sintaxe Pester 5->3) descobri que ele dependia de lib_fqs_default_quality.ps1,
que eu tinha acabado de deletar como "lixo confirmado sem teste". A checagem
anterior de "tem teste?" so buscava por NOME DE ARQUIVO
(tests/*lib_fqs_default_quality*Tests.ps1) -- mas o teste real se chama
tori_and_fqs.Tests.ps1, sem relacao de nome com a lib.

Busca corrigida por CONTEUDO (grep -l "$nome_da_lib" tests/*.Tests.ps1) revelou
que 23 dos 27 arquivos deletados tinham teste dedicado real (convencao
"Blocker #N" numerada: 007_auto_demote_cron.Tests.ps1,
006_dsr_live_methodology.Tests.ps1, 013_live_integration.Tests.ps1, etc) --
sao FEATURE_PRONTA_NAO_CONECTADA, nao lixo puro. Alem disso
lib_telegram_essential_alerts.ps1 E dot-sourceado de fato por
gem_executor.ps1 (linha 40, via variavel `$__essentialAlertsPath`, que o
grep anterior nao capturou por nao ser o nome literal).

**Mantidos deletados de fato, apos tripla checagem (zero funcao chamada,
zero dot-source, zero mencao em workflow, zero teste por conteudo):**
lib_http_error_monitor.ps1, lib_mesa_relaxed_criteria.ps1,
lib_tori_integration_audit.ps1 (commit c801893).

**Os outros 24 voltaram** (lib_auto_demote_cron, lib_dsr_confidence_advanced,
lib_dsr_live_audit, lib_fqs_default_quality, lib_live_integration,
lib_llm_cost_telemetry, lib_macro_audit, lib_mce_gates, lib_mentor_calibration,
lib_mentor_rules, lib_override_expiry, lib_performance_refiner,
lib_portfolio_rebalance, lib_prediction_engine, lib_profit_taking_milestone,
lib_self_learning, lib_short_pipeline_advanced, lib_short_rampup,
lib_signal_calibration, lib_telegram_essential_alerts,
lib_trailing_executor_phase2, lib_trailing_macro, lib_trailing_microstructure,
lib_trailing_state) -- entram na fila de FEATURE_PRONTA_NAO_CONECTADA real
(tem teste passando, so falta decidir conectar ou nao com o usuario).

**LICAO:** para achar "orfaos" com confianca, sempre buscar teste por
CONTEUDO (dot-source do arquivo dentro do .Tests.ps1), nunca por padrao de
nome de arquivo. Este projeto tem convencao mista (lib_X.Tests.ps1 E
NNN_descricao.Tests.ps1 numerado por "Blocker #N").

## Resultado final ORIGINAL (2026-07-23, commit 331c6b1 -- REVERTIDO, ver acima)

Re-confirmado manualmente arquivo por arquivo antes de deletar (não confiei
cegamente no relatório do agente -- achei 2 erros nele: lib_market_context.ps1
tem teste + chamador real, e 6 arquivos do lote original eram dot-sourceados
de fato em produção, só não tinham função chamada).

**27 arquivos deletados** (zero chamador real, zero dot-source, zero
referência em workflow): lib_auto_demote_cron, lib_dsr_confidence_advanced,
lib_dsr_live_audit, lib_fqs_default_quality, lib_http_error_monitor,
lib_live_integration, lib_llm_cost_telemetry, lib_macro_audit, lib_mce_gates,
lib_mentor_calibration, lib_mentor_rules, lib_mesa_relaxed_criteria,
lib_override_expiry, lib_performance_refiner, lib_portfolio_rebalance,
lib_prediction_engine, lib_profit_taking_milestone, lib_self_learning,
lib_short_pipeline_advanced, lib_short_rampup, lib_signal_calibration,
lib_telegram_essential_alerts, lib_tori_integration_audit,
lib_trailing_executor_phase2, lib_trailing_macro, lib_trailing_microstructure,
lib_trailing_state.

**Mantidos, pendentes de investigação separada (NAO sao lixo puro):**
- lib_coinex_news, lib_faro_margin_safety, lib_faro_ml_confidence,
  lib_idempotency, lib_llm_quota_optimizer, lib_regime_detector_audit --
  SAO dot-sourceados em producao mas nenhuma funcao e chamada depois
  (padrao "wired mas sem dado real"; lib_regime_detector_audit tem
  comentario "2026-07-08 ATIVACAO" sugerindo conexao parcial abandonada)
- lib_mentor_hallucination_detector.ps1 -- dot-sourceado por gem_loop.ps1,
  nenhuma funcao chamada; deteccao de alucinacao do Mentor pode nunca ter
  sido ligada ao pipeline live
- lib_volatility_filter.ps1 -- possivel gate de risco (filtro de
  volatilidade de entrada) nunca conectado
- lib_sizing_centralized.ps1 -- testes corrigidos nesta sessao (10/10 pass,
  commit f4ddbc2) sob premissa de uso real, mas confirmado via grep que
  gem_executor.ps1 usa Get-ExecutorSize/Get-SizePerTrade/Get-DynamicCapitalAllocation,
  nunca Get-SafePositionSize -- reconciliar

**FEATURE_PRONTA_NAO_CONECTADA (17) e DUPLICATA (7) restantes:** ainda nao
decididos com o usuario -- ficam para proxima rodada (usuario escolheu
"deletar o lixo confirmado direto" desta vez, nao pediu decisao sobre os
outros buckets ainda).
