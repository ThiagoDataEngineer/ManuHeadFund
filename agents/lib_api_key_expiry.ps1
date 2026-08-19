# lib_api_key_expiry.ps1 -- alerta de expiracao de API keys sem IP vinculado
#
# Achado real 2026-08-19: CoinEx API key ("Live01") expirou em 2026-08-17
# (90 dias sem IP vinculado, limite da propria CoinEx) sem NENHUM alerta --
# CoinEx-GetPendingPositions passou a receber code=4005 "access_id not
# exists", engolido silenciosamente (retorna @()), causando fechamento em
# massa de posicoes reais via phantom_reconciliation (ja corrigido em
# lib_trailing_orphan_detection.ps1, commit fa90c29) e depois travando
# tambem a execucao de PARTIAL/EXIT de lucro real. Owner decidiu (2026-08-19)
# NAO vincular IP fixo (exigiria infra nova, VPS/proxy dedicado) -- fica nos
# 90 dias, mas com aviso automatico com antecedencia desta vez.
#
# journal/api_key_expiry.json (commitado, curadoria manual -- mesmo padrao
# de journal/coin_registry.json): registro manual da data de criacao de
# cada key rastreada. Sem endpoint da CoinEx pra consultar validade via
# API, a unica fonte de verdade e a tela web (nao automatizavel sem
# credencial de sessao web, fora de escopo). Atualizar este arquivo toda
# vez que uma key for renovada/recriada.

function Test-ApiKeyExpiryWarning {
    <#
      Pura, sem I/O. Calcula dias restantes ate a expiracao e decide se
      deve alertar, dado hoje, a data de criacao, e o prazo de validade.

      .PARAMETER CreatedAt
      Data de criacao da key (a CoinEx conta os 90 dias a partir daqui).
      .PARAMETER ValidityDays
      Prazo total de validade (90 por padrao, key sem IP vinculado).
      .PARAMETER WarnDaysBefore
      Quantos dias antes do vencimento comeca a alertar (default 10 --
      digest roda 1x/dia, entao ~10 alertas antes do problema real dao
      folga suficiente pra agir sem spam).
      .PARAMETER Today
      Data de referencia (injetavel, testabilidade).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [datetime] $CreatedAt,
        [int] $ValidityDays = 90,
        [int] $WarnDaysBefore = 10,
        [datetime] $Today = (Get-Date)
    )
    $expiresAt = $CreatedAt.AddDays($ValidityDays)
    $daysLeft = [math]::Ceiling(($expiresAt - $Today).TotalDays)

    $shouldWarn = ($daysLeft -le $WarnDaysBefore)
    $expired = ($daysLeft -le 0)

    return [PSCustomObject]@{
        expires_at   = $expiresAt
        days_left    = $daysLeft
        should_warn  = $shouldWarn
        expired      = $expired
    }
}

function Get-ApiKeyExpiryDigestLines {
    <#
      Le journal/api_key_expiry.json (curadoria manual, ver comentario de
      topo) e retorna as linhas de alerta prontas pro digest diario -- so
      as keys que precisam de atencao (should_warn=true), silencio total
      caso contrario (nao polui o digest todo dia por 80 dias).
    #>
    [CmdletBinding()]
    param(
        [string] $RegistryPath = "",
        [datetime] $Today = (Get-Date)
    )
    if (-not $RegistryPath) {
        $base = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path (Join-Path $PSScriptRoot "..") "journal" }
        $RegistryPath = Join-Path $base "api_key_expiry.json"
    }
    if (-not (Test-Path $RegistryPath)) { return @() }

    try {
        $entries = @(Get-Content $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return @("AVISO: journal/api_key_expiry.json malformado -- $_")
    }

    $lines = @()
    foreach ($e in $entries) {
        if (-not $e.name -or -not $e.created_at) { continue }
        try {
            $createdAt = [datetime]$e.created_at
        } catch { continue }
        $validity = if ($e.validity_days) { [int]$e.validity_days } else { 90 }
        $r = Test-ApiKeyExpiryWarning -CreatedAt $createdAt -ValidityDays $validity -Today $Today
        if ($r.should_warn) {
            $tag = if ($r.expired) { "EXPIRADA" } else { "expira em $($r.days_left)d" }
            $lines += "API KEY $($e.name): $tag (vence $($r.expires_at.ToString('yyyy-MM-dd'))) -- renovar em $($e.renew_url)"
        }
    }
    return $lines
}
