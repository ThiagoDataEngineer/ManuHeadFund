# lib_mentor_shadow.ps1 -- Fase 0 do plano de integracao do Mentor LLM
# (Sonnet/Groq/Mistral com debate + deteccao de alucinacao, ver
# agents/mentor_agent.ps1::Invoke-MentorDebate).
#
# Achado 2026-07-24: o mentor LLM completo (Invoke-MentorDebate, via
# Invoke-V6Cascade em orchestrator_v6.ps1) nunca foi conectado ao executor
# real (gem_executor.ps1) -- decisao de entrada roda 100% deterministica
# hoje. Antes de dar poder de veto ao LLM, esta Fase 0 so REGISTRA o que o
# LLM teria decidido, comparando com a decisao real, sem influenciar nada.
#
# Contrato: Invoke-MentorShadowObservation NUNCA deve afetar a execucao real
# (nunca lanca excecao pro chamador, nunca modifica $usd_size/$direction/
# bloqueio). Gated por journal/MENTOR_SHADOW_ENABLED.flag -- ausencia do
# flag = no-op total (nem tenta rodar, nem faz dot-source das libs pesadas).

# 2026-07-25 FIX (mesmo bug achado em lib_mentor_live.ps1, run 30145266606):
# dot-source DENTRO de uma funcao define as funcoes carregadas so no escopo
# LOCAL dessa funcao (comentario de topo de lib_loader_auto.ps1) -- o
# dot-source precisa rodar no nivel de MODULO deste arquivo, fora de
# qualquer funcao, pra herdar o escopo de quem fizer ". lib_mentor_shadow.ps1".
if (-not (Get-Command Invoke-V6Cascade -ErrorAction SilentlyContinue)) {
    try {
        . (Join-Path $PSScriptRoot "mentor_agent.ps1")
        . (Join-Path $PSScriptRoot "mesa_agent.ps1")
        . (Join-Path $PSScriptRoot "triagem_agent.ps1")
        . (Join-Path $PSScriptRoot "orchestrator_v6.ps1")
    } catch {
        Write-Host "  [MENTOR SHADOW WARN] falha ao carregar dependencias: $_" -ForegroundColor DarkYellow
    }
}

$script:__mentorShadowLibsLoaded = $null -ne (Get-Command Invoke-V6Cascade -ErrorAction SilentlyContinue)

function Invoke-MentorShadowObservation {
    <#
    .SYNOPSIS
    Roda a cascade Triagem->Mesa->Mentor (orchestrator_v6.ps1) em modo
    observacao pura e loga o resultado vs a decisao real do gem_executor.
    Falha sempre silenciosa -- nunca deve afetar o caminho de execucao real.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $RealDirection,
        [Parameter(Mandatory)] [double] $RealPrice,
        [Parameter(Mandatory)] [double] $RealUsdSize,
        [double] $Change24h = 0,
        [string] $Regime = "UNKNOWN"
    )

    $flagPath = Join-Path $PSScriptRoot "..\journal\MENTOR_SHADOW_ENABLED.flag"
    if (-not (Test-Path $flagPath)) { return }

    if (-not $script:__mentorShadowLibsLoaded) { return }

    try {
        $context = [PSCustomObject]@{
            pair_change_24h  = $Change24h
            mode             = "GEM"
            source           = "GEM"
            regime           = $Regime
            scanner_score    = 50
            scanner          = [PSCustomObject]@{ score = 50; change = $Change24h }
            macro            = [PSCustomObject]@{ macro_bias = "NEUTRAL" }
            seasonal         = [PSCustomObject]@{ dayOfWeek = (Get-Date).DayOfWeek.ToString(); marketTier = "alt"; momentScore = 50 }
            day_of_week_brt  = [int](Get-Date).DayOfWeek
        }

        $stopPct = [math]::Abs($Change24h) * 0.5
        if ($stopPct -lt 2.0) { $stopPct = 2.0 }
        if ($stopPct -gt 8.0) { $stopPct = 8.0 }
        $rr = 5.0
        $setup = if ($RealDirection -eq "SHORT") {
            [PSCustomObject]@{
                entry  = $RealPrice
                stop   = [math]::Round($RealPrice * (1 + $stopPct / 100), 6)
                target = [math]::Round($RealPrice * (1 - $stopPct * $rr / 100), 6)
                rr     = $rr
            }
        } else {
            [PSCustomObject]@{
                entry  = $RealPrice
                stop   = [math]::Round($RealPrice * (1 - $stopPct / 100), 6)
                target = [math]::Round($RealPrice * (1 + $stopPct * $rr / 100), 6)
                rr     = $rr
            }
        }

        $started = Get-Date
        $cascade = Invoke-V6Cascade -Market $Market -Context $context -Setup $setup
        $elapsedMs = [int]((Get-Date) - $started).TotalMilliseconds

        $llmDecision = if ($cascade.decisao -eq "ABORTAR") { "SKIP" }
                       elseif ($cascade.mentor -and $cascade.mentor.decision) { [string]$cascade.mentor.decision }
                       else { "UNKNOWN" }

        # 2026-07-27: mentor_confidence nunca era extraido aqui (so decisao
        # binaria) -- owner quer usar a nota real do Mentor pra validar se
        # correlaciona com resultado, precisa do numero persistido.
        # 2026-07-28 FIX: o objeto retornado por Invoke-MentorDebate
        # (mentor_agent.ps1 linha ~1227) usa a propriedade "confianca"
        # (portugues), nunca "confidence" -- confirmado real: as 3 primeiras
        # observacoes persistidas em mentor_shadow_observations tinham
        # mentor_confidence sempre vazio, apesar do flag/persistencia
        # funcionando (decision/llm_decision ja liam corretamente porque
        # coincidentemente o campo .decision existe em ingles).
        $mentorConfidence = if ($cascade.mentor -and $null -ne $cascade.mentor.confianca) {
            try { [double]$cascade.mentor.confianca } catch { $null }
        } else { $null }

        $tsUtc = (Get-Date).ToUniversalTime().ToString("o")
        $entry = [ordered]@{
            ts_utc            = $tsUtc
            market            = $Market
            real_direction    = $RealDirection
            real_usd_size     = $RealUsdSize
            llm_decision      = $llmDecision
            mentor_confidence = $mentorConfidence
            llm_motivo        = [string]$cascade.motivo
            triagem_tier      = if ($cascade.triagem) { [string]$cascade.triagem.tier } else { $null }
            mesa_consensus    = if ($cascade.mesa) { [string]$cascade.mesa.consensus } else { $null }
            elapsed_ms        = $elapsedMs
            agrees_with_real  = ($llmDecision -eq "APROVAR")
        }

        $logPath = Join-Path $PSScriptRoot "..\journal\mentor_shadow_log.jsonl"
        Add-Content -Path $logPath -Value ($entry | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8

        # 2026-07-27: persiste no Supabase (cloud-persistente) -- o jsonl local
        # e efemero no runner do GitHub Actions e se perde a cada job (mesmo
        # bug ja corrigido para conviction_observations/beta_history). Fail-
        # gracious: shadow e Fase 0, nunca deve quebrar por falha de rede/schema.
        if (Get-Command Save-StateRecords -ErrorAction SilentlyContinue) {
            try {
                $record = [PSCustomObject]@{
                    pk_id             = "${Market}_${RealDirection}_${tsUtc}"
                    ts_utc            = $tsUtc
                    market            = $Market
                    real_direction    = $RealDirection
                    real_usd_size     = $RealUsdSize
                    llm_decision      = $llmDecision
                    mentor_confidence = $mentorConfidence
                    llm_motivo        = [string]$cascade.motivo
                    triagem_tier      = if ($cascade.triagem) { [string]$cascade.triagem.tier } else { $null }
                    mesa_consensus    = if ($cascade.mesa) { [string]$cascade.mesa.consensus } else { $null }
                    elapsed_ms        = $elapsedMs
                    agrees_with_real  = ($llmDecision -eq "APROVAR")
                }
                Save-StateRecords -Table "mentor_shadow_observations" -Records @($record) -PrimaryKey "pk_id"
            } catch {
                # persist na nuvem falhando nao deve afetar a observacao local nem a execucao real
            }
        }
    } catch {
        # Fase 0 e' observacao pura -- qualquer falha aqui NUNCA deve
        # propagar pro executor real. So loga um warning leve.
        Write-Host "  [MENTOR SHADOW WARN] $_" -ForegroundColor DarkYellow
    }
}
