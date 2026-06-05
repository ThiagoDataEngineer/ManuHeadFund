# lib_daemon_singleton.ps1 -- Guard de instancia unica para daemons.
# Problema: watchdog/restart matam por pattern de CommandLine; processos elevados
# expoem CommandLine=NULL pra shell normal -> kill falha -> DUPLICATAS.
# Solucao: cada daemon adquire um lock (PID + start-time) no startup via
# Enter-DaemonSingleton. Se outra instancia VIVA ja roda, retorna $false e o
# daemon sai imediatamente. Imune a bug de kill (a duplicata se auto-mata).
#
# Lockfile JSON: { name, pid, start_ticks, ts }. start_ticks evita falso-positivo
# de PID-reuse (SO reaproveita PIDs). PS 5.1. UTF-8 BOM.

function Get-DaemonLockPath {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $LockDir
    )
    return (Join-Path $LockDir ($Name + ".lock"))
}

function Get-DaemonLockInfo {
    # Retorna o objeto do lock SE ele aponta pra um processo VIVO e consistente
    # (PID existe E start-time bate). Caso contrario (sem lock / PID morto /
    # PID reusado / lock corrompido) retorna $null = "ninguem rodando".
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $LockDir
    )
    $lock = Get-DaemonLockPath -Name $Name -LockDir $LockDir
    if (-not (Test-Path $lock)) { return $null }
    try {
        $raw = Get-Content $lock -Raw -ErrorAction Stop
        if (-not $raw -or $raw.Trim() -eq "") { return $null }
        $info = $raw | ConvertFrom-Json
    } catch {
        return $null   # lock corrompido = trata como ausente
    }
    if ($null -eq $info.pid) { return $null }
    $proc = Get-Process -Id ([int]$info.pid) -ErrorAction SilentlyContinue
    if ($null -eq $proc) { return $null }   # PID morto = lock stale
    # Guard de PID-reuse: se gravamos start_ticks, ele tem que bater com o processo atual.
    if ($info.start_ticks) {
        try {
            if ($proc.StartTime.Ticks -ne [long]$info.start_ticks) { return $null }
        } catch { }   # sem acesso ao StartTime: aceita o PID vivo
    }
    return $info
}

function Test-DaemonRunning {
    # $true se existe uma instancia VIVA registrada no lock (qualquer PID, inclusive o nosso).
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $LockDir
    )
    return ($null -ne (Get-DaemonLockInfo -Name $Name -LockDir $LockDir))
}

function Enter-DaemonSingleton {
    # Tenta adquirir o singleton. Retorna $true se ESTE processo pode rodar:
    #   - ninguem rodando (lock ausente/stale)  -> adquire e retorna $true
    #   - o lock ja e NOSSO (mesmo PID)          -> refresh e retorna $true (idempotente)
    #   - OUTRA instancia viva detem o lock      -> retorna $false (caller deve sair)
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $LockDir
    )
    if (-not (Test-Path $LockDir)) {
        New-Item -ItemType Directory -Path $LockDir -Force | Out-Null
    }
    $info = Get-DaemonLockInfo -Name $Name -LockDir $LockDir
    if ($null -ne $info -and [int]$info.pid -ne $PID) {
        return $false   # outra instancia viva
    }
    # Adquire/atualiza o lock com nossa identidade.
    $startTicks = $null
    try { $startTicks = (Get-Process -Id $PID).StartTime.Ticks } catch { }
    $payload = [ordered]@{
        name        = $Name
        pid         = $PID
        start_ticks = $startTicks
        ts          = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    } | ConvertTo-Json -Compress
    Set-Content -Path (Get-DaemonLockPath -Name $Name -LockDir $LockDir) -Value $payload -Encoding UTF8
    return $true
}

function Stop-DaemonByLock {
    # Mata o processo registrado no lock (por PID exato, imune ao blindspot de
    # CommandLine) e remove o lock. Usado pelo watchdog ANTES de respawnar pra
    # garantir que (a) processo hung e substituido e (b) o novo consegue o lock.
    # Retorna o PID morto, ou $null se nao havia instancia viva.
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $LockDir
    )
    $info = Get-DaemonLockInfo -Name $Name -LockDir $LockDir
    $killed = $null
    if ($null -ne $info -and [int]$info.pid -ne $PID) {
        try {
            Stop-Process -Id ([int]$info.pid) -Force -ErrorAction SilentlyContinue
            $killed = [int]$info.pid
        } catch { }
    }
    # Remove o lock (stale ou recem-morto) pra liberar a aquisicao do novo processo.
    $lock = Get-DaemonLockPath -Name $Name -LockDir $LockDir
    if (Test-Path $lock) { Remove-Item $lock -Force -ErrorAction SilentlyContinue }
    return $killed
}

function Exit-DaemonSingleton {
    # Libera o lock SOMENTE se for nosso (evita apagar lock de outra instancia).
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $LockDir
    )
    $lock = Get-DaemonLockPath -Name $Name -LockDir $LockDir
    if (-not (Test-Path $lock)) { return }
    try {
        $info = Get-Content $lock -Raw | ConvertFrom-Json
        if ([int]$info.pid -eq $PID) {
            Remove-Item $lock -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Remove-Item $lock -Force -ErrorAction SilentlyContinue
    }
}
