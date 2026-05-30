# lib_quant_whitelist.ps1 - Le per_asset_whitelist JSON e expoe Tier A/B/C ao
# scan_master/orchestrator. Substituicao quant-priorizada do scanner heuristico.
#
# Output JSON gerado por backtest/build_per_asset_whitelist.py em
# journal/per_asset_whitelist_<DATE>.json.

function Get-QuantWhitelistPath {
    [CmdletBinding()]
    param([string]$JournalDir = "")
    if (-not $JournalDir) {
        $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
        $JournalDir = Join-Path (Split-Path -Parent $here) "journal"
    }
    $candidates = Get-ChildItem -Path $JournalDir -Filter "per_asset_whitelist_*.json" `
                                 -ErrorAction SilentlyContinue |
                                 Sort-Object LastWriteTime -Descending
    if ($candidates -and @($candidates).Count -gt 0) {
        return @($candidates)[0].FullName
    }
    return $null
}


function Get-QuantWhitelist {
    [CmdletBinding()]
    param([string]$Path = "")
    if (-not $Path) { $Path = Get-QuantWhitelistPath }
    if (-not $Path -or -not (Test-Path $Path)) {
        return [PSCustomObject]@{
            TIER_A_LIVE  = @()
            TIER_B_PAPER = @()
            TIER_C_SKIP  = @()
            source       = $null
        }
    }
    try {
        $raw = Get-Content $Path -Raw -Encoding UTF8
        $data = $raw | ConvertFrom-Json
        return [PSCustomObject]@{
            TIER_A_LIVE  = @($data.TIER_A_LIVE)
            TIER_B_PAPER = @($data.TIER_B_PAPER)
            TIER_C_SKIP  = @($data.TIER_C_SKIP)
            source       = $Path
        }
    } catch {
        Write-Warning "Get-QuantWhitelist: falha ao parsear $Path -- $($_.Exception.Message)"
        return [PSCustomObject]@{
            TIER_A_LIVE  = @()
            TIER_B_PAPER = @()
            TIER_C_SKIP  = @()
            source       = $Path
        }
    }
}


function Get-QuantWhitelistMarkets {
    [CmdletBinding()]
    param(
        [string] $Mode = "LIVE",   # LIVE | PAPER | ALL
        [string] $Path = ""
    )
    $wl = Get-QuantWhitelist -Path $Path
    $markets = @()
    if ($Mode -eq "LIVE" -or $Mode -eq "PAPER" -or $Mode -eq "ALL") {
        $markets += @($wl.TIER_A_LIVE | ForEach-Object { $_.market })
    }
    if ($Mode -eq "PAPER" -or $Mode -eq "ALL") {
        $markets += @($wl.TIER_B_PAPER | ForEach-Object { $_.market })
    }
    if ($Mode -eq "ALL") {
        $markets += @($wl.TIER_C_SKIP | ForEach-Object { $_.market })
    }
    return @($markets | Where-Object { $_ })
}


function Get-QuantWhitelistEntry {
    [CmdletBinding()]
    param([string]$Market, [string]$Path = "")
    $wl = Get-QuantWhitelist -Path $Path
    foreach ($pool in @($wl.TIER_A_LIVE, $wl.TIER_B_PAPER, $wl.TIER_C_SKIP)) {
        foreach ($e in $pool) {
            if ($e.market -eq $Market) { return $e }
        }
    }
    return $null
}


function Get-MarketRegimeFromCache {
    # Retorna regime string para o market pedido, ou $null se arquivo nao existe
    # ou market nao encontrado. Fail-soft: qualquer erro retorna $null.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $JournalDir = ""
    )
    try {
        if (-not $JournalDir) {
            $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
            $JournalDir = Join-Path (Split-Path -Parent $here) "journal"
        }
        $cachePath = Join-Path $JournalDir "regime_state.json"
        if (-not (Test-Path $cachePath)) { return $null }
        $raw = Get-Content $cachePath -Raw -Encoding UTF8
        $data = $raw | ConvertFrom-Json
        # Suporta tanto objeto plano {BTCUSDT: "BEAR_STRONG"} quanto
        # objeto com campo markets aninhado {markets: {BTCUSDT: "BEAR_STRONG"}}
        if ($data.PSObject.Properties[$Market]) {
            return [string]$data.$Market
        }
        if ($data.PSObject.Properties['markets'] -and $data.markets.PSObject.Properties[$Market]) {
            return [string]$data.markets.$Market
        }
        # FIX 2026-05-29 (Opcao A): schema GLOBAL de producao.
        # refresh_regime_state.ps1 grava regime GLOBAL (sem chaves por-mercado):
        #   {regime, phase, bias, current_regime, ...}
        # Sem este fallback, Get-MarketRegimeFromCache retornava $null pra TODOS
        # os markets -> rebaixamento regime-aware era no-op em producao (INJUSDT
        # e todo Tier A entravam tier_level=1 mesmo em mercado bear).
        # Precedencia: chave por-mercado (acima) > regime global (abaixo).
        if ($data.PSObject.Properties['regime'] -and $data.regime -and ($data.regime -is [string])) {
            return [string]$data.regime
        }
        if ($data.PSObject.Properties['current_regime'] -and $data.current_regime) {
            return [string]$data.current_regime
        }
        return $null
    } catch {
        return $null
    }
}


function Merge-QuantWhitelistIntoCandidates {
    [CmdletBinding()]
    param(
        [PSObject[]]  $Candidates = @(),
        [string]      $Mode = "LIVE",
        [string]      $Path = "",
        # Opcional: scriptblock que recebe $market e retorna regime string.
        # Quando fornecido, ativos em BEAR_STRONG ou BEAR_WEAK recebem tier_level=3
        # em vez de 1, liberando slots para candidatos organicos do scanner.
        [scriptblock] $RegimeProvider = $null,
        # Item 1 fix 2026-05-29: lista de markets que devem permanecer FORCADOS
        # no top do scan. Quando especificado, restringe o conjunto forcado a
        # apenas esses markets (intersecao com a whitelist Tier A/B). Os demais
        # ativos da whitelist permanecem VIVOS no sistema (DSR, sector_map, beta,
        # promotion ladder) mas nao sao mais forcados no top do orchestrator --
        # competem como candidatos organicos pelo compScore real.
        # Producao recomendada: -AnchorMarkets @("BTCUSDT") (so BTC anchor).
        # Default $null = backward compat (todos Tier A/B forcados).
        # @() = explicito "nenhum forcado" (zero anchors, scanner 100% organico).
        [AllowEmptyCollection()]
        [string[]]    $AnchorMarkets = $null
    )
    # FASE 4 p4 fix 2026-05-21: ler whitelist FULL pra preservar tier_level (1=A_LIVE, 2=B_PAPER).
    # Antes: Get-QuantWhitelistMarkets retornava so nomes -> sort downstream perdia info de tier.
    # Resultado: BTC/INJ entravam top-7 mas RENDER/XMR (Tier A) eram bumped por BCH/SKY (Tier B).
    $wl = Get-QuantWhitelist -Path $Path
    if (-not $wl) { return @($Candidates) }

    $tierAList = @($wl.TIER_A_LIVE | ForEach-Object { $_.market } | Where-Object { $_ })
    $tierBList = if ($Mode -eq "PAPER" -or $Mode -eq "ALL") {
        @($wl.TIER_B_PAPER | ForEach-Object { $_.market } | Where-Object { $_ })
    } else { @() }
    $forced = @(@($tierAList) + @($tierBList) | Select-Object -Unique)

    # Item 1 fix 2026-05-29: restringe forcados aos AnchorMarkets quando especificado.
    # PSBoundParameters distingue $null (parametro nao passado, backward compat)
    # de @() (passado vazio explicitamente, zero forcados).
    if ($PSBoundParameters.ContainsKey('AnchorMarkets')) {
        if ($null -eq $AnchorMarkets -or @($AnchorMarkets).Count -eq 0) {
            $forced = @()
        } else {
            $anchorSet = @{}
            foreach ($a in $AnchorMarkets) { if ($a) { $anchorSet[$a] = $true } }
            $forced = @($forced | Where-Object { $anchorSet.ContainsKey($_) })
        }
    }

    if (@($forced).Count -eq 0) { return @($Candidates) }

    # FASE 4 p5 fix 2026-05-21 sessao final: quando market forced JA EXISTE em
    # $Candidates (descoberta organica do scanner), AUGMENT os fields ao inves de skip.
    # Pre-fix: INJ apareceu organicamente cycle 11:29, ficou sem tier_level/source ->
    # scanner natural (tierLevel=99) -> bumped do top-7 atras dos 4 Tier A + Tier B forced.
    $existingByMkt = @{}
    foreach ($c in $Candidates) {
        $mktKey = if ($c.PSObject.Properties['market']) { $c.market } elseif ($c.PSObject.Properties['Market']) { $c.Market } else { $null }
        if ($mktKey) { $existingByMkt[$mktKey] = $c }
    }

    # FIX 2026-05-29: quando AnchorMarkets e especificado, remover isWhitelistForced
    # dos candidatos que nao estao em AnchorMarkets. Isso garante que Select-TopCandidates
    # os trate como organicos e nao forcados.
    $forcedSet = @{}
    foreach ($f in $forced) { $forcedSet[$f] = $true }
    
    if ($PSBoundParameters.ContainsKey('AnchorMarkets')) {
        foreach ($c in $Candidates) {
            $mktKey = if ($c.PSObject.Properties['market']) { $c.market } elseif ($c.PSObject.Properties['Market']) { $c.Market } else { $null }
            if ($mktKey -and -not $forcedSet.ContainsKey($mktKey)) {
                # Market nao esta em AnchorMarkets -> remover isWhitelistForced
                if ($c.PSObject.Properties['isWhitelistForced']) {
                    $c.isWhitelistForced = $false
                }
            }
        }
    }

    $extras = @()
    foreach ($m in $forced) {
        $entry = Get-QuantWhitelistEntry -Market $m -Path $Path
        $sharpe = if ($entry -and $entry.PSObject.Properties['sharpe']) { [double]$entry.sharpe } else { 0.0 }
        $tierLevel = if ($tierAList -contains $m) { 1 } else { 2 }
        $forcedSource = "quant_whitelist_$Mode"

        # Regime-aware tier_level: se RegimeProvider fornecido e regime for BEAR,
        # rebaixa tier_level de 1 para 3 para liberar slots para candidatos organicos.
        # EXCETO: BTC (anchor) nunca e rebaixado (sempre tier_level=1).
        $effectiveTierLevel = $tierLevel
        if ($RegimeProvider -and $m -ne "BTCUSDT") {
            try {
                $regime = & $RegimeProvider $m
                if ($regime -eq "BEAR_STRONG" -or $regime -eq "BEAR_WEAK") {
                    $effectiveTierLevel = 3
                }
            } catch {
                # Fail-soft: qualquer erro no provider mantem tier_level original
            }
        }

        if ($existingByMkt.ContainsKey($m)) {
            # FASE 4 p5: augment existing scanner-natural entry with forced fields.
            # Preserve scanner volume/change reais; sobrescreve so source + tier_level.
            $existing = $existingByMkt[$m]
            if (-not $existing.PSObject.Properties['source'] -or $existing.source -notlike 'quant_whitelist_*') {
                Add-Member -InputObject $existing -MemberType NoteProperty -Name 'source' -Value $forcedSource -Force
            }
            if (-not $existing.PSObject.Properties['tier_level']) {
                Add-Member -InputObject $existing -MemberType NoteProperty -Name 'tier_level' -Value $effectiveTierLevel -Force
            }
            if (-not $existing.PSObject.Properties['quant_priority']) {
                Add-Member -InputObject $existing -MemberType NoteProperty -Name 'quant_priority' -Value $sharpe -Force
            }
            # FIX 2026-05-29: marcar como forcado para Select-TopCandidates diferenciar
            Add-Member -InputObject $existing -MemberType NoteProperty -Name 'isWhitelistForced' -Value $true -Force
        } else {
            # Market nao apareceu organicamente -> adiciona extra forced.
            $extras += [PSCustomObject]@{
                market           = $m
                marketType       = "FUTURES"   # Tier A/B LIVE eh sempre futures (validado curated)
                score            = 100         # forcado pra entrar no top
                change           = 0.0         # neutro (scanner real preenche se aparece naturalmente)
                vol              = 0.0         # FIX 2026-05-29: usar 'vol' em vez de 'volume' para consistencia
                volume           = 0.0         # FIX 2026-05-29: manter 'volume' tambem (filtro downstream + lockdown test)
                compScore        = 100         # FIX 2026-05-29: adicionar compScore para Select-TopCandidates
                quant_priority   = $sharpe
                tier_level       = $effectiveTierLevel  # regime-aware: BEAR -> 3, outros -> original
                source           = $forcedSource
                isWhitelistForced = $true      # FIX 2026-05-29: marcar como forcado
            }
        }
    }
    return @($Candidates + $extras)
}
