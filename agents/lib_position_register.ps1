# agents/lib_position_register.ps1
# Wrapper que escolhe entre trailing classico (Add-TrailingPosition) e
# Moon Bag split (Add-MoonBagPair) baseado em flag opt-in.
#
# Flag: journal/MOON_BAG_ENABLED.flag (presence = enabled)
# Default: OFF (back-compat, todos callers continuam usando trailing classico)
#
# Para ativar:
#   New-Item journal/MOON_BAG_ENABLED.flag -ItemType File
#
# Para desativar:
#   Remove-Item journal/MOON_BAG_ENABLED.flag -Force
#
# Dot-source: . (Join-Path $PSScriptRoot "lib_position_register.ps1")

# Helpers internos
$_posRegAgentsDir = $PSScriptRoot
$_posRegJournalDir = Join-Path (Split-Path $_posRegAgentsDir -Parent) "journal"
$MOON_BAG_FLAG_FILE = Join-Path $_posRegJournalDir "MOON_BAG_ENABLED.flag"

function Test-MoonBagEnabled {
    <#
    .SYNOPSIS
    Verifica se Moon Bag esta ativado para entradas novas.

    .DESCRIPTION
    Checa primeiro a flag global $global:MOON_BAG_ENABLED (override para testes),
    depois a presenca do arquivo flag em journal/MOON_BAG_ENABLED.flag.

    .PARAMETER FlagPath
    Override do caminho do arquivo flag (testing).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$FlagPath = $MOON_BAG_FLAG_FILE
    )

    # Override por variavel global (prioridade maxima, util pra testes)
    if ($null -ne $global:MOON_BAG_ENABLED) {
        return [bool]$global:MOON_BAG_ENABLED
    }

    return (Test-Path $FlagPath)
}

function Register-PositionTrailing {
    <#
    .SYNOPSIS
    Registra trailing para uma nova posicao. Decide automaticamente entre
    trailing classico (Add-TrailingPosition) e Moon Bag split (Add-MoonBagPair).

    .DESCRIPTION
    Default: trailing classico (Add-TrailingPosition).
    Se MOON_BAG_ENABLED.flag presente E source nao for 'orphan_auto_register':
      - GEM     -> Moon Bag com harvest 4% / moon 50% (gem coins explosivos)
      - TIER_A  -> Moon Bag com harvest 5% / moon 30% (default conservador)
      - GEM_FAST_DEMOTE / outros: trailing classico (back-compat)

    Orphans (source=orphan_auto_register) SEMPRE usam trailing classico
    pois ja foram criados na exchange como posicao unica - nao podem ser splittados.

    .PARAMETER Market, Side, Entry, Stop, Target, OrderId, Source, Mode, MaxDays, DdThresholdPct
    Mesmos parametros do Add-TrailingPosition (back-compat).

    .PARAMETER Size
    Tamanho da posicao em USD (apenas usado quando Moon Bag ativo).
    Default: 0 (Moon Bag desliga e cai no trailing classico se Size=0).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Market,
        [Parameter(Mandatory=$true)][ValidateSet("LONG","SHORT")][string]$Side,
        [Parameter(Mandatory=$true)][double]$Entry,
        [Parameter(Mandatory=$true)][double]$Stop,
        [Parameter(Mandatory=$true)][double]$Target,
        [string]$OrderId  = "",
        [string]$Source   = "orchestrator",
        [string]$Mode     = "",
        [int]   $MaxDays  = 0,
        [double]$DdThresholdPct = 0,
        [double]$Size = 0,
        # A.1 wire pass-through pra reflection ledger
        [string]$MentorVeredicto = "",
        [int]   $MentorConfidence = 0,
        [string]$MentorMensagem = "",
        [string]$MesaSinal = "",
        [string]$Tier = "",
        # 2026-08-06 FIX: Register-PositionTrailing nunca teve -Origin desde
        # que o campo foi introduzido em Add-TrailingPosition (2026-07-18) --
        # achado real: lib_regime_surf_executor.ps1/scan_master.ps1 chamam
        # esta funcao SEM Origin, mesmo sabendo a origem real do trade (ex:
        # regime_surf sempre abre FUTURES/SWING), entao toda posicao desses
        # callers nascia com origin=UNKNOWN/UNKNOWN -- travando pra sempre em
        # HOLD no motor unificado (Resolve-TrailingDecision exige trade_style
        # SCALP|SWING, "UNKNOWN" nunca bate). ARBUSDT/NEARUSDT/OPUSDT ficaram
        # 42h+ sem trailing avancar fase por causa disso. Optativo (default
        # $null): callers que ja nao passavam continuam com o mesmo
        # comportamento de antes (fallback UNKNOWN em Add-TrailingPosition).
        [hashtable]$Origin = $null
    )

    $useMoonBag = $false

    # Decisao em camadas (qualquer regra que falhe -> trailing classico)
    if (Test-MoonBagEnabled) {
        # Orphans nao podem ser splittados (sao posicoes unicas ja na exchange)
        if ($Source -ne "orphan_auto_register") {
            # Precisa de Size pra calcular pernas
            if ($Size -gt 0) {
                # Precisa da lib carregada
                if (Get-Command Add-MoonBagPair -ErrorAction SilentlyContinue) {
                    $useMoonBag = $true
                }
            }
        }
    }

    if ($useMoonBag) {
        # Defaults adaptativos por source
        $harvestPct = 5.0
        $moonPct    = 30.0
        switch ($Source) {
            "gem" {
                # GEM coins sao mais volateis: harvest mais cedo, moon mais agressivo
                $harvestPct = 4.0
                $moonPct    = 50.0
            }
            default {
                # TIER_A / orchestrator: defaults equilibrados
                $harvestPct = 5.0
                $moonPct    = 30.0
            }
        }

        try {
            $result = Add-MoonBagPair `
                -Market $Market `
                -Side $Side `
                -Entry $Entry `
                -Size $Size `
                -OrderId $OrderId `
                -HarvestTargetPct $harvestPct `
                -MoonTargetPct $moonPct
            Write-Host ("  [Register] {0} {1}: Moon Bag pair (harvest +{2}% / moon +{3}%) source={4} pairId={5}" -f $Market, $Side, $harvestPct, $moonPct, $Source, $result.pairId) -ForegroundColor Magenta
            return $result
        } catch {
            Write-Host ("  [Register] Moon Bag falhou pra {0}, fallback trailing classico: {1}" -f $Market, $_) -ForegroundColor DarkYellow
            # Fall through pro Add-TrailingPosition abaixo
        }
    }

    # Trailing classico (default ou fallback)
    $addTrailingArgs = @{
        Market = $Market
        Side = $Side
        Entry = $Entry
        Stop = $Stop
        Target = $Target
        OrderId = $OrderId
        Source = $Source
        Mode = $Mode
        MaxDays = $MaxDays
        DdThresholdPct = $DdThresholdPct
        MentorVeredicto = $MentorVeredicto
        MentorConfidence = $MentorConfidence
        MentorMensagem = $MentorMensagem
        MesaSinal = $MesaSinal
        Tier = $Tier
    }
    if ($Origin) { $addTrailingArgs.Origin = $Origin }
    Add-TrailingPosition @addTrailingArgs
}

# Functions exported:
# - Test-MoonBagEnabled
# - Register-PositionTrailing
