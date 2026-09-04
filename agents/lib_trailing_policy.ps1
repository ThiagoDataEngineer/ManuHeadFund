# lib_trailing_policy.ps1 -- Politica de saida PURA por tipo de operacao + motor
# de reversao-vs-manter. Sem LLM (barato), deterministico, 100% TDD-able.
#
# Combo (opcoes 1+2):
#   (2) Resolve-ExitPolicy: scalp/swing/short/long/runner -> parametros proprios.
#   (1) Get-ExitDecision: dado os params + contexto da barra, decide
#       HOLD / TIGHTEN(aperta stop) / PARTIAL / EXIT, incluindo o ladder de
#       reversao: 0 sinais=HOLD, >=tighten_n aperta (nao vende no fundo,
#       trava ganhos -0.5R), >=exit_n sai. Espelhado p/ SHORT.
#
# 2026-09-02 FIX CRITICO: reversal_exit_signals=3 (tighten=2) nunca disparava
# EXIT em producao real -- achado apos o fix de ordem de execucao de ontem
# (2026-09-01, commit 92a4bff) nao resolver o "toma muito stop" reportado
# pelo owner. Investigacao com 59 execucoes reais do Trailing Stop Monitor
# confirmou: o MAXIMO de sinais de reversao simultaneos ja observado em
# qualquer posicao real (CRVUSDT, SKYUSDT, etc) foi 2 -- nunca 3. O detector
# de padroes (lib_chart_patterns.ps1/lib_auto_market_analysis.ps1) raramente
# confirma mais de 2 sinais tecnicos ao mesmo tempo na pratica, entao o
# threshold de 3 era estruturalmente quase inatingivel -- o motor so apertava
# o stop (tighten, sempre ativo com 2 sinais) e nunca chegava a EXIT/realizar,
# deixando o trade correr ate o stop apertado bater na corretora (mesmo
# resultado pratico de "sempre stop", so que via ordem normal em vez de saida
# proativa por reversao real ja confirmada). Reduzido pra exit=2/tighten=1 --
# 1 sinal isolado ja aperta o stop (protege lucro sem vender no fundo por
# ruido), 2 sinais simultaneos (o teto real observado) ja e' confirmacao
# suficiente pra sair de fato.
#
# Plugga no harness: PolicyFn = { param($ctx) Get-ExitDecision -Policy $p -Context $ctx }
# PS 5.1 safe. PURO.

function Resolve-ExitPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TradeType,
        [string] $Direction = "LONG",
        [string] $Regime = ""
    )
    $isShort = ($Direction -eq "SHORT")
    $t = $TradeType.ToLower()

    switch ($t) {
        "scalp" {
            $p = @{
                breakeven_at_r = 0.5
                trail_method   = "chandelier"; trail_atr_mult = 1.5
                partials       = @(@{ at_r = 1.0; pct = 0.6 })
                time_stop_bars = 8
                reversal_exit_signals = 2; reversal_tighten_signals = 1
                # 2026-09-02: PARTIAL por reversao isolada + lucro real, mesmo
                # sem chegar em R=1.0 (achado real: maioria dos trades nunca
                # chega la antes de reverter). Ver comentario completo acima.
                reversal_partial_pct = 0.3
            }
        }
        "swing" {
            $p = @{
                breakeven_at_r = 1.0
                trail_method   = "chandelier"; trail_atr_mult = $(if ($isShort) { 2.0 } else { 3.0 })
                partials       = $(if ($isShort) { @(@{ at_r=1.0; pct=0.5 }) } else { @(@{ at_r=1.0; pct=0.33 }, @{ at_r=2.0; pct=0.33 }) })
                time_stop_bars = $(if ($isShort) { 40 } else { 60 })
                reversal_exit_signals = 2; reversal_tighten_signals = 1
                reversal_partial_pct = 0.3
            }
        }
        "runner" {
            # pos-parcial / em breakeven: ja e "dinheiro da casa". Sem novas parciais
            # ESTRUTURAIS (por R-multiple). So sai em reversao confirmada; trail
            # largo p/ deixar correr.
            # 2026-09-03: reversal_partial_pct adicionado -- achado da auditoria
            # profunda pos-fix-do-piso-em-R (64eba60): "runner" e o perfil mais
            # escolhido pra LONG saudavel em uptrend (Resolve-ExitPolicyGated),
            # exatamente o caso mais comum de "sobe bem e depois volta tudo". Sem
            # este campo, so tinha 2 saidas possiveis: EXIT total (2+ sinais) ou
            # nada -- perdendo 100% do lucro enquanto so 1 sinal de reversao
            # isolado aparecia. Mesmo valor (0.3) usado nas outras policies;
            # nao muda a filosofia de "deixa correr" (so ativa com sinal real).
            $p = @{
                breakeven_at_r = 0.0
                trail_method   = "chandelier"; trail_atr_mult = 4.0
                partials       = @()
                time_stop_bars = 0
                reversal_exit_signals = 2; reversal_tighten_signals = 1
                reversal_partial_pct = 0.3
            }
        }
        default {
            $t = "standard"
            $p = @{
                breakeven_at_r = 1.0
                trail_method   = "chandelier"; trail_atr_mult = $(if ($isShort) { 2.0 } else { 2.5 })
                partials       = @(@{ at_r=1.0; pct=0.5 })
                time_stop_bars = 30
                reversal_exit_signals = 2; reversal_tighten_signals = 1
                reversal_partial_pct = 0.3
            }
        }
    }
    $p.trade_type = $t
    $p.direction  = $Direction
    $p.regime     = $Regime   # hook p/ ajuste regime-aware futuro (validar antes de ativar)
    return $p
}


function Resolve-ExitPolicyGated {
    <#
    .SYNOPSIS
    Seletor GATED por tendencia/regime -- encoda o achado validado (walk-forward
    2026-06-21): runner (trail largo, deixa correr) so vence em UPTREND
    (delta +0.183 ROBUST); em DOWNTREND PERDE (delta -0.111). Logo:
      - LONG em uptrend confirmado + regime nao-bear -> runner
      - resto -> politica ATUAL (melhor em downtrend/chop)
    Conservador: regime BEAR_* vence o sinal de SMA (nao liga runner em bear).

    .PARAMETER TrendUp  close > SMA (ex: SMA50) na entrada/no momento.
    .PARAMETER Regime   regime corrente (BULL_STRONG/BULL_WEAK/BEAR_WEAK/...).
    .PARAMETER Direction LONG|SHORT (achado validado e LONG; SHORT defere ao atual).
    #>
    [CmdletBinding()]
    param(
        [bool]   $TrendUp = $false,
        [string] $Regime = "",
        [string] $Direction = "LONG"
    )
    $isBear = ($Regime -match '^(?i)bear')
    $useRunner = ($Direction -eq "LONG") -and $TrendUp -and (-not $isBear)

    if ($useRunner) {
        $p = Resolve-ExitPolicy -TradeType "runner" -Direction "LONG"
        $p.selected = "runner"
        $p.gate_reason = "uptrend+non_bear -> let it run (validated +0.18R)"
    } else {
        $p = Get-CurrentTrailingPolicy
        $p.selected = "atual"
        $p.gate_reason = if ($isBear) { "regime bear -> atual (runner perde -0.11R em downtrend)" }
                         elseif (-not $TrendUp) { "downtrend -> atual (melhor em chop/down)" }
                         else { "short/outro -> atual" }
    }
    return $p
}


function Get-ExitDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $Policy,
        [Parameter(Mandatory)] [hashtable] $Context
    )
    $side    = [string]$Context.side
    $isLong  = ($side -ne "SHORT")
    $entry   = [double]$Context.entry
    $risk    = [double]$Context.risk
    $rNow    = [double]$Context.r_now
    $peak    = [double]$Context.peak
    $curStop = [double]$Context.current_stop
    $remaining = [double]$Context.remaining_size
    $bars    = [int]$Context.bars_held
    $signals = if ($null -ne $Context.signals) { [int]$Context.signals } else { 0 }
    $atr = 0.0
    if ($null -ne $Context.atr) { $atr = [double]$Context.atr }
    elseif ($Context.bar -and $Context.bar.PSObject.Properties['atr'] -and $Context.bar.atr) { $atr = [double]$Context.bar.atr }

    # ── candidatos de novo stop (ratchet aplicado abaixo) ──
    $cands = New-Object System.Collections.ArrayList
    $beR = [double]$Policy.breakeven_at_r
    if ($beR -gt 0 -and $rNow -ge $beR) { [void]$cands.Add($entry) }

    if ([string]$Policy.trail_method -eq "chandelier" -and $atr -gt 0) {
        $mult = [double]$Policy.trail_atr_mult
        if ($isLong) { [void]$cands.Add($peak - $mult * $atr) } else { [void]$cands.Add($peak + $mult * $atr) }
    }

    # reversao ambigua -> aperta travando ganhos -0.5R (NAO vende no fundo)
    $tightenN = [int]$Policy.reversal_tighten_signals
    if ($tightenN -gt 0 -and $signals -ge $tightenN) {
        $lockR = $rNow - 0.5
        if ($lockR -gt 0) {
            if ($isLong) { [void]$cands.Add($entry + $lockR * $risk) } else { [void]$cands.Add($entry - $lockR * $risk) }
        }
    }

    # escolhe o melhor candidato na direcao do ratchet vs stop atual
    $newStop = $null
    foreach ($c in $cands) {
        if ($isLong) { if ($c -gt $curStop -and ($null -eq $newStop -or $c -gt $newStop)) { $newStop = $c } }
        else         { if ($c -lt $curStop -and ($null -eq $newStop -or $c -lt $newStop)) { $newStop = $c } }
    }
    if ($null -ne $newStop) { $newStop = [math]::Round($newStop, 8) }

    # ── precedencia de acao ──
    # 1. reversao confirmada -> sai
    $exitN = [int]$Policy.reversal_exit_signals
    if ($exitN -gt 0 -and $signals -ge $exitN) {
        return @{ action = "exit"; new_stop = $newStop; size_pct = $remaining }
    }
    # 2. time-stop (barreira vertical)
    $ts = [int]$Policy.time_stop_bars
    if ($ts -gt 0 -and $bars -ge $ts) {
        return @{ action = "exit"; new_stop = $newStop; size_pct = $remaining }
    }
    # 3. parcial (stateless: reduz ate o target_remaining do maior nivel atingido)
    $partials = @($Policy.partials)
    if ($partials.Count -gt 0) {
        $cum = 0.0; $bestTarget = $null
        foreach ($pp in ($partials | Sort-Object { [double]$_.at_r })) {
            $cum += [double]$pp.pct
            if ($rNow -ge [double]$pp.at_r) { $bestTarget = 1.0 - $cum }
        }
        if ($null -ne $bestTarget -and $remaining -gt ($bestTarget + 0.001)) {
            $sz = [math]::Round($remaining - $bestTarget, 4)
            return @{ action = "partial"; new_stop = $newStop; size_pct = $sz }
        }
    }
    # 3b. parcial por REVERSAO ISOLADA (2026-09-02 FIX CRITICO): achado real
    # -- a maioria dos trades reais NUNCA chega a R=1.0 (piso dos partials
    # acima) antes de reverter e bater o stop, entao PARTIAL por R-multiple
    # sozinho nunca disparava na pratica. Se ha lucro real (rNow>0) e pelo
    # menos $tightenN sinais de reversao (o mesmo piso que ja apertava o
    # stop sem vender, achado 2026-09-02: max real observado e' 2, exit_n
    # agora=2), realiza uma fatia CONSERVADORA (default 30%) mesmo sem R=1.0
    # -- trava parte do lucro que ja existe em vez de deixar reverter tudo
    # pro stop. So dispara se ainda nao houve NENHUM partial por R-multiple
    # (remaining=1.0 -- se ja realizou parcial acima, essa camada nao repete).
    # Opt-in via $Policy.reversal_partial_pct (ausente/0 preserva 100% o
    # comportamento antigo -- so as policies que setarem esse campo ativam).
    $reversalPartialPct = if ($Policy.ContainsKey('reversal_partial_pct')) { [double]$Policy.reversal_partial_pct } else { 0.0 }
    if ($reversalPartialPct -gt 0 -and $tightenN -gt 0 -and $signals -ge $tightenN -and $rNow -gt 0 -and $remaining -ge 0.999) {
        $sz = [math]::Round([Math]::Min($remaining, $reversalPartialPct), 4)
        if ($sz -gt 0) {
            return @{ action = "partial"; new_stop = $newStop; size_pct = $sz }
        }
    }
    # 4. hold (com stop possivelmente apertado)
    return @{ action = "hold"; new_stop = $newStop; size_pct = 0 }
}
