# lib_regime_rr_calibration.ps1 -- Calibragem autonoma de R:R minimo por
# regime+direcao, baseada em edge REAL medido (mce_counterfactual_agg).
#
# Contexto (2026-07-29): auditoria real de trade_outcomes mostrou ganho medio
# (+1.99%) MENOR que perda media (-4.62%) nos trades rastreaveis -- o R:R
# planejado fixo de 1:5 (GEM_MIN_RR, config.ps1) nunca varia por regime, apesar
# de ja existir edge REAL medido e documentado no codigo (mce_counterfactual_agg,
# scripts/mce_counterfactual_from_supabase.ps1) mostrando que alguns pares
# regime|direction tem hit_rate muito acima da media (NEUTRO|SHORT 87.5% n=24)
# e outros edge real mas mais moderado (BEAR|LONG via breadth override 67.7% n=62).
#
# Owner pediu (2026-07-29): "calibrar conforme regime autonomo" -- refinar pra
# depender do MOVIMENTO/tendencia real (nao so um numero fixo por enum), com
# R:R minimo variando pelo edge medido, nao so o stop%. Mantem Regra de Ouro #3
# (R:R minimo nunca cai abaixo de um piso conservador) intacta onde nao ha dado
# suficiente -- so afrouxa quando ha evidencia real (n>=20) de edge forte.
#
# Principio "engine agnostico" (mesmo de lib_evolution_engine.ps1): funciona
# com Get-Command guards, nunca lanca se Supabase/mce_counterfactual_agg
# estiverem indisponiveis -- cai no default global (GEM_MIN_RR = 1:5).

# ── Tabela de calibragem (PURA, testavel sem rede) ───────────────────────────

function Get-RegimeRRCalibration {
    <#
    .SYNOPSIS
    Retorna o R:R minimo calibrado pra um par regime+direction, com base no
    edge medido (n, hit_rate) das linhas de mce_counterfactual_agg ja
    agregadas por quem chama (mesmo padrao de lib_evolution_engine.ps1:236-240
    -- pondera por n quando ha multiplas linhas/gates pro mesmo regime|direction).

    .PARAMETER Regime
    Scenario resolvido por Resolve-MarketScenario: CAPITULACAO|BEAR|BULL|NEUTRO|UNKNOWN.

    .PARAMETER Direction
    "LONG" | "SHORT".

    .PARAMETER N
    Numero de observacoes reais (soma de mce_counterfactual_agg.n pros grupos
    regime|direction, todos os gates). N < MinSampleSize = sem edge confiavel,
    usa o default conservador.

    .PARAMETER HitRate
    Taxa de acerto ponderada (0.0-1.0) do par regime+direction nos dados reais.

    .PARAMETER DefaultRR
    R:R minimo quando nao ha edge medido confiavel (Regra de Ouro #3, config.ps1
    GEM_MIN_RR). Nunca None -- sempre volta pra este piso quando em duvida.

    .PARAMETER MinSampleSize
    N minimo pra confiar no hit_rate como edge real (nao ruido). Default 20,
    mesmo piso usado em scripts/diag_real_edge_readonly_2026_07_19.ps1 (n<10
    "nao conclui nada", n<30 "hipotese" -- 20 fica no meio, exige pelo menos
    "hipotese razoavel" mas nao exige o padrao mais rigoroso de 30).

    .OUTPUTS
    [PSCustomObject]@{ rr_min; tier; reason }
    tier: "EDGE_FORTE" | "EDGE_MODERADO" | "SEM_EDGE_MEDIDO"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Regime,
        [Parameter(Mandatory)] [string] $Direction,
        [int]    $N = 0,
        [double] $HitRate = 0.0,
        [double] $DefaultRR = 5.0,
        [int]    $MinSampleSize = 20
    )

    if ($N -lt $MinSampleSize) {
        return [PSCustomObject]@{
            rr_min = $DefaultRR
            tier   = "SEM_EDGE_MEDIDO"
            reason = "n=$N < minimo $MinSampleSize amostras -- sem dado suficiente pra confiar, usa piso conservador R:R 1:$DefaultRR"
        }
    }

    # EDGE FORTE: hit_rate>=85% com n>=20 -- unico caso confirmado ate hoje e
    # NEUTRO|SHORT (mce_counterfactual_agg: hit_rate=87.5% n=24, subgrupo com
    # gate breadth_short_blocked ainda mais forte 94.4% n=18). R:R minimo cai
    # pra 1:3 -- mais trades passam o gate de qualidade, tamanho maior
    # justificado pela taxa de acerto muito acima da media.
    if ($HitRate -ge 0.85) {
        return [PSCustomObject]@{
            rr_min = 3.0
            tier   = "EDGE_FORTE"
            reason = "hit_rate=$([math]::Round($HitRate*100,1))% n=$N >= 85% -- edge forte medido, R:R minimo reduzido pra 1:3"
        }
    }

    # EDGE MODERADO: hit_rate 60-85% com n>=20 -- caso confirmado e BEAR|LONG
    # (via breadth_long_blocked override, hit_rate=67.7% n=62): edge real mas
    # margem mais estreita, R:R minimo cai so pra 1:4 (menos agressivo que o
    # edge forte, ainda mais seletivo que o default).
    if ($HitRate -ge 0.60) {
        return [PSCustomObject]@{
            rr_min = 4.0
            tier   = "EDGE_MODERADO"
            reason = "hit_rate=$([math]::Round($HitRate*100,1))% n=$N entre 60-85% -- edge real moderado, R:R minimo reduzido pra 1:4"
        }
    }

    # n>=MinSampleSize mas hit_rate<60% -- dado real existe, mas nao mostra
    # edge suficiente pra afrouxar o piso. Mantem o default conservador.
    return [PSCustomObject]@{
        rr_min = $DefaultRR
        tier   = "SEM_EDGE_MEDIDO"
        reason = "hit_rate=$([math]::Round($HitRate*100,1))% n=$N -- dado real existe mas abaixo do limiar de edge (60%), mantem piso R:R 1:$DefaultRR"
    }
}

# ── Wire I/O: consulta mce_counterfactual_agg real (Supabase) ───────────────

function Resolve-RegimeRRCalibration {
    <#
    .SYNOPSIS
    Wrapper de I/O: busca mce_counterfactual_agg (todas as linhas do par
    regime+direction, agregando todos os gates -- mesmo padrao de
    lib_evolution_engine.ps1:232-244), pondera hit_rate por n, e delega o
    calculo puro pra Get-RegimeRRCalibration. Fail-soft: qualquer falha de
    leitura (Supabase indisponivel, tabela vazia) cai no default conservador
    sem lancar -- nunca bloqueia o fluxo de execucao real.

    .PARAMETER Regime
    Scenario resolvido por Resolve-MarketScenario (CAPITULACAO|BEAR|BULL|NEUTRO).

    .PARAMETER Direction
    "LONG" | "SHORT".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Regime,
        [Parameter(Mandatory)] [string] $Direction,
        [double] $DefaultRR = 5.0
    )

    $n = 0
    $hitRate = 0.0

    try {
        if (Get-Command _Get-LearningFromSupabase -ErrorAction SilentlyContinue) {
            $rows = @(_Get-LearningFromSupabase -Table "mce_counterfactual_agg" -Filter @{ regime = $Regime; direction = $Direction })
            if ($rows.Count -gt 0) {
                $totalN = ($rows | Measure-Object -Property n -Sum).Sum
                if ($totalN -gt 0) {
                    $weightedHits = ($rows | ForEach-Object { [double]$_.n * [double]$_.hit_rate } | Measure-Object -Sum).Sum
                    $n = [int]$totalN
                    $hitRate = $weightedHits / $totalN
                }
            }
        }
    } catch {
        Write-Warning "[regime-rr-calibration] leitura de mce_counterfactual_agg falhou (fallback default): $_"
    }

    return Get-RegimeRRCalibration -Regime $Regime -Direction $Direction -N $n -HitRate $hitRate -DefaultRR $DefaultRR
}
