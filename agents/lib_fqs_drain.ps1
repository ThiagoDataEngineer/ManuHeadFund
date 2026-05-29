# lib_fqs_drain.ps1 -- Drena fila FQS inline antes do orchestrator V6.
#
# CONTEXTO 2026-05-29 (Item 2):
#   Pre-fix: scan_master enfileirava markets novos via Add-FqsEnrichmentRequest,
#   mas o processamento (python coingecko_enrichment) so rodava no cron separado.
#   Resultado: scanner detecta IDUSDT no top -> enfileira -> orchestrator V6
#   pede contexto AGORA -> mentor le coin_registry sem entry -> "FQS indisponivel"
#   -> ABORTAR. Markets novos vetados ate proximo cron rodar.
#
#   Pos-fix: apos enqueue e antes do orchestrator, scan_master chama
#   Invoke-FqsEnrichmentDrain. Markets faltantes sao enriquecidos sincronamente
#   (3-5s) via coingecko_enrichment.py. Orchestrator recebe registry atualizado.
#
# DESIGN:
#   - Fail-soft: invoker null, python ausente, timeout -> retorna stats e segue.
#     Orchestrator decide via gates como antes (FQS indisponivel ainda eh sinal).
#   - Limite de tempo: TimeoutSec default 30s -- nao deixar 1 ciclo travar 5min.
#   - Limite de markets: MaxMarkets default 10 -- evitar burst API se backlog.
#   - Dedup interno: market 2x na lista vira 1 chamada.
#   - Skip se ja registrado: idempotente.
#
# PS 5.1. UTF-8. Sem acentos.

function Invoke-FqsEnrichmentDrain {
    <#
    .SYNOPSIS
    Enriquece sincronamente markets faltantes no coin_registry antes do orchestrator.

    .DESCRIPTION
    Recebe lista de markets candidatos, identifica os que NAO estao no
    coin_registry.json, e chama o invoker (default: python coingecko_enrichment)
    em batch para enriquece-los. Retorna estatisticas para audit/log.

    .PARAMETER Markets
    Lista de markets candidatos (ex: top do scanner).

    .PARAMETER RegistryPath
    Caminho do coin_registry.json. Default: journal/coin_registry.json.

    .PARAMETER Invoker
    ScriptBlock que recebe -Markets [string[]] -TimeoutSec [int] e retorna
    PSCustomObject @{ ok=$true|$false; exit_code=N; error=string }.
    Default null = skip drain (fail-soft).

    .PARAMETER MaxMarkets
    Limite de markets enriquecidos por chamada (anti-burst API). Default 10.
    Markets alem do limite sao reportados em skipped_overflow.

    .PARAMETER TimeoutSec
    Timeout passado ao invoker. Default 30s.

    .OUTPUTS
    PSCustomObject com:
      - enriched (int)            : markets que foram para o invoker
      - skipped_registered (int)  : markets ja no registry
      - skipped_overflow (int)    : markets cortados por MaxMarkets
      - skipped_no_invoker (int)  : markets nao processados por falta de invoker
      - failed (bool)             : invoker retornou ok=false
      - error (string)            : mensagem do invoker se failed
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Markets,

        [string] $RegistryPath = "",

        [scriptblock] $Invoker = $null,

        [int] $MaxMarkets = 10,

        [int] $TimeoutSec = 30
    )

    # Default registry path
    if (-not $RegistryPath) {
        $journalDir = if ($global:JOURNAL_DIR) {
            $global:JOURNAL_DIR
        } else {
            $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
            Join-Path (Split-Path -Parent $here) "journal"
        }
        $RegistryPath = Join-Path $journalDir "coin_registry.json"
    }

    $stats = [ordered]@{
        enriched           = 0
        skipped_registered = 0
        skipped_overflow   = 0
        skipped_no_invoker = 0
        failed             = $false
        error              = $null
    }

    # Lista vazia -> nada a fazer
    if (-not $Markets -or $Markets.Count -eq 0) {
        return [PSCustomObject]$stats
    }

    # Dedup
    $unique = @($Markets | Where-Object { $_ } | Select-Object -Unique)

    # Carrega registry para identificar faltantes
    $registered = @{}
    if (Test-Path $RegistryPath) {
        try {
            $reg = Get-Content $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $reg.PSObject.Properties) { $registered[$p.Name] = $true }
        } catch {
            # Registry corrompido: trata como vazio (todos vao virar enriched)
        }
    }

    $missing = @()
    foreach ($m in $unique) {
        if ($registered.ContainsKey($m)) {
            $stats.skipped_registered++
        } else {
            $missing += $m
        }
    }

    # Nada a enriquecer
    if ($missing.Count -eq 0) {
        return [PSCustomObject]$stats
    }

    # Invoker ausente -> fail-soft
    if (-not $Invoker) {
        $stats.skipped_no_invoker = $missing.Count
        return [PSCustomObject]$stats
    }

    # Aplica limite MaxMarkets
    if ($missing.Count -gt $MaxMarkets) {
        $stats.skipped_overflow = $missing.Count - $MaxMarkets
        $missing = $missing | Select-Object -First $MaxMarkets
    }

    # Chama invoker
    try {
        $result = & $Invoker -Markets $missing -TimeoutSec $TimeoutSec
        if ($null -eq $result -or -not $result.ok) {
            $stats.failed = $true
            $stats.error  = if ($result -and $result.error) { $result.error } else { "invoker_returned_not_ok" }
            # Nao incrementa enriched: invoker falhou, markets nao foram enriquecidos
        } else {
            $stats.enriched = $missing.Count
        }
    } catch {
        $stats.failed = $true
        $stats.error  = $_.Exception.Message
    }

    return [PSCustomObject]$stats
}


function New-CoingeckoFqsInvoker {
    <#
    .SYNOPSIS
    Cria scriptblock invoker que chama backtest/coingecko_enrichment.py.

    .DESCRIPTION
    Helper para producao. Retorna scriptblock que pode ser passado em -Invoker.
    Fail-soft se python ou script ausentes.

    .PARAMETER ProjectRoot
    Raiz do projeto (default: 2 niveis acima desta lib).
    #>
    [CmdletBinding()]
    param(
        [string] $ProjectRoot = ""
    )
    if (-not $ProjectRoot) {
        $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
        $ProjectRoot = Split-Path -Parent $here
    }
    $pyScript = Join-Path $ProjectRoot "backtest\coingecko_enrichment.py"
    if (-not (Test-Path $pyScript)) {
        return $null   # fail-soft: caller pula drain
    }
    # Closure captura $pyScript
    $pyScriptCaptured = $pyScript
    return {
        param([string[]] $Markets, [int] $TimeoutSec)
        if (-not $Markets -or $Markets.Count -eq 0) {
            return [PSCustomObject]@{ ok=$true; exit_code=0; error=$null }
        }
        $csv = [string]::Join(',', $Markets)
        try {
            # Start-Process com timeout (ChildProcess.WaitForExit do PS).
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "python"
            $psi.Arguments = ('"{0}" --markets {1}' -f $pyScriptCaptured, $csv)
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            if (-not $proc.WaitForExit([Math]::Max(1, $TimeoutSec) * 1000)) {
                try { $proc.Kill() } catch {}
                return [PSCustomObject]@{ ok=$false; exit_code=-1; error="timeout_${TimeoutSec}s" }
            }
            $code = $proc.ExitCode
            if ($code -eq 0) {
                return [PSCustomObject]@{ ok=$true; exit_code=0; error=$null }
            } else {
                $errOut = ""
                try { $errOut = $proc.StandardError.ReadToEnd() } catch {}
                return [PSCustomObject]@{ ok=$false; exit_code=$code; error="python_exit_$code $errOut" }
            }
        } catch {
            return [PSCustomObject]@{ ok=$false; exit_code=-2; error=$_.Exception.Message }
        }
    }.GetNewClosure()
}
