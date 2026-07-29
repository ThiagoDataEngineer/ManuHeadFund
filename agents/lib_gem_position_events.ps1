# lib_gem_position_events.ps1 -- registro real de cada execucao de ordem GEM
# (abertura nova OU "Add Position" em posicao existente), persistido no
# Supabase. Fonte de verdade pro guard "CASCADING ADD POSITION PREVENTION"
# (gem_executor.ps1, 2026-07-07) -- que ate 2026-07-29 lia de
# journal/trade_outcomes.jsonl (arquivo LOCAL) pra contar quantos Add
# Positions ja ocorreram nas ultimas 6h. Runner do GitHub Actions e efemero
# (clona limpo a cada job) -- esse arquivo NUNCA sobrevive entre execucoes,
# entao $addPositionCount sempre lia 0 e o limite de "maximo 3 Add Positions
# /6h" nunca bloqueava nada de verdade. Confirmado em producao real
# (2026-07-29): DOGEUSDT SHORT recebeu 12 incrementos de ~965 DOGE cada ao
# longo de 17h (somando exatamente o open_interest final de 11597) sem o
# guard disparar uma unica vez.
#
# Tambem corrige nomes de campo: o guard original comparava contra
# .market/.entry_date/status="open", nenhum dos quais existe no schema real
# de manuheadfund.trade_outcomes (colunas reais: symbol/entry_ts/status com
# valores 'pending'|'closed', nunca 'open') -- o guard NUNCA teria batido
# com nada mesmo lendo do Supabase real. Tabela nova e dedicada
# (gem_position_events) evita reusar um schema que nao serve pro proposito.

function Add-GemPositionEvent {
    <#
    .SYNOPSIS
    Registra 1 execucao real de ordem GEM (abertura nova ou Add Position)
    -- fail-soft, nunca bloqueia o fluxo de execucao real.

    .PARAMETER Market
    .PARAMETER Side
    "LONG" | "SHORT".
    .PARAMETER UsdSize
    Tamanho em USD da ordem executada (nao da posicao total).
    .PARAMETER EventType
    "OPEN" (primeira entrada) | "ADD" (reforco em posicao existente).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Side,
        [Parameter(Mandatory)] [double] $UsdSize,
        [string] $EventType = "OPEN"
    )
    try {
        if (-not (Get-Command Save-StateRecords -ErrorAction SilentlyContinue)) { return }
        $nowUtc = (Get-Date).ToUniversalTime()
        $id = "{0}|{1}|{2}" -f $Market, $EventType, $nowUtc.Ticks
        $record = @{
            id         = $id
            market     = $Market
            side       = $Side
            usd_size   = $UsdSize
            event_type = $EventType
            created_at = $nowUtc.ToString("o")
        }
        $prevSchema = $global:STATE_STORE_SCHEMA
        try {
            $global:STATE_STORE_SCHEMA = "manuheadfund"
            Save-StateRecords -Table "gem_position_events" -Records @($record) -PrimaryKey "id"
        } finally {
            $global:STATE_STORE_SCHEMA = $prevSchema
        }
    } catch {
        Write-Warning "[gem-position-events] falha ao registrar evento (nao bloqueia): $_"
    }
}

function Get-RecentGemAddPositionCount {
    <#
    .SYNOPSIS
    Conta quantos eventos EventType=ADD reais existem pra este market nas
    ultimas N horas -- fonte real pro guard de cascata. Fail-soft: qualquer
    falha de leitura retorna 0 (comportamento conservador antigo preservado,
    nao trava o fluxo, mas tambem nao super-restringe por erro de rede).

    .PARAMETER Market
    .PARAMETER HoursBack
    Janela de tempo (default 6h, mesmo valor hardcoded no guard original).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [int] $HoursBack = 6
    )
    try {
        if (-not (Get-Command Get-StateRecords -ErrorAction SilentlyContinue)) { return 0 }
        $prevSchema = $global:STATE_STORE_SCHEMA
        $rows = @()
        try {
            $global:STATE_STORE_SCHEMA = "manuheadfund"
            $rows = @(Get-StateRecords -Table "gem_position_events" -Filter @{ market = $Market; event_type = "ADD" })
        } finally {
            $global:STATE_STORE_SCHEMA = $prevSchema
        }
        # 2026-07-29 FIX (achado ao escrever o teste): [datetime]$string faz
        # cast simples que interpreta o "Z" (UTC) do ISO 8601 como horario
        # LOCAL do runner (Kind=Local), nao UTC -- comparacao contra $cutoff
        # (Kind=Utc real) ficava desalinhada pelo offset do timezone,
        # contando eventos errados perto da fronteira da janela. Fix:
        # DateTimeStyles.RoundtripKind preserva o "Z" como Utc de verdade.
        $cutoff = (Get-Date).ToUniversalTime().AddHours(-$HoursBack)
        $recent = @($rows | Where-Object {
            try {
                $parsed = [datetime]::Parse([string]$_.created_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                $parsed -gt $cutoff
            } catch { $false }
        })
        return $recent.Count
    } catch {
        Write-Warning "[gem-position-events] falha ao contar Add Positions recentes (fallback 0): $_"
        return 0
    }
}
