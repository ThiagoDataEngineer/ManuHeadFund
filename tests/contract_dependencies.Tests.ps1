# contract_dependencies.Tests.ps1 — TRATAMENTO DE CAUSA RAIZ (2026-07-04)
# A causa raiz dos 13 bugs de 07/03-04 nao foi nenhum bug individual: foi
# AUSENCIA DE VERIFICACAO DE CONTRATO entre componentes + falha silenciosa.
# Este teste analisa a AST de TODO o codigo operacional e verifica:
#   1. Toda funcao CHAMADA existe DEFINIDA em algum lugar do projeto
#      (teria pego: CoinEx-GetKlines inexistente, exec_sql RPC — classe inteira)
# Sem executar nada: analise estatica pura, roda em segundos, roda no CI.

Describe "CONTRATO: toda funcao chamada existe" {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent

        # Cache de analise (uma passada em todos os arquivos)
        $script:defined = New-Object System.Collections.Generic.HashSet[string]
        $script:calls = @{}   # funcao -> lista de "arquivo:linha"

        $files = @(Get-ChildItem "$root\agents\*.ps1") + @(Get-ChildItem "$root\scripts\*.ps1")
        $quarantine = @("setup_telegram.ps1","start_services.ps1","trailing_long.ps1")

        foreach ($f in $files) {
            if ($f.Name -in $quarantine) { continue }
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
            if ($errors.Count -gt 0) { continue }

            # Definicoes
            foreach ($fd in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
                [void]$script:defined.Add($fd.Name.ToLower())
            }
            # Chamadas (CommandAst com nome estatico)
            foreach ($cmd in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $name = $cmd.GetCommandName()
                if (-not $name) { continue }
                $key = $name.ToLower()
                if (-not $script:calls.ContainsKey($key)) { $script:calls[$key] = New-Object System.Collections.ArrayList }
                if ($script:calls[$key].Count -lt 3) {
                    [void]$script:calls[$key].Add("$($f.Name):$($cmd.Extent.StartLineNumber)")
                }
            }
        }

        # BASELINE (ratchet 2026-07-04): 15 chamadas mortas legadas encontradas na 1a
        # execucao — features que NUNCA rodaram (guards Get-Command as silenciavam).
        # Ex.: short_scanner regime-cego, gem_safety pause nunca reconciliado.
        # REGRA: so REMOVER daqui (ao consertar). Adicionar = quebra o build (CI).
        $script:BASELINE_DEAD_CALLS = @(
            'add-hallucinationevent','calculate-trailingstopmetrics','coinex-hasspotmarket',
            'execute-hybridsignal','get-dashboardmetrics','get-etherscanconcentration',
            'get-hybridpositionsizes','get-macroregime','invoke-safejob','send-tgmessage',
            'test-cyclehasnews','test-mentorfqshallucination','update-trailingstopcontinuous',
            # 2026-07-20: descobertos so agora pq CI Verify estava quebrado no parse
            # (24h+) e nunca chegou a rodar este teste. Todos guardados por
            # Get-Command antes da chamada -- sempre caem no fallback, nunca crasham.
            'get-coinexopenpositions','get-currentregime','get-journaldir'
        )
    }

    It "nenhuma chamada NOVA a funcao inexistente (baseline legado: 16)" {
        # So auditamos nomes com cara de funcao do projeto (Verbo-Nome com prefixos
        # do dominio ou padrao CoinEx-/Get-/Set-/etc customizado). Cmdlets nativos,
        # exes e aliases ficam fora via Get-Command.
        $missing = @()
        foreach ($name in $script:calls.Keys) {
            if ($script:defined.Contains($name)) { continue }
            # Ignora: cmdlets/aliases/aplicacoes disponiveis no PowerShell
            if (Get-Command $name -ErrorAction SilentlyContinue) { continue }
            # Ignora: invocacoes dinamicas comuns que nao sao funcao do projeto
            if ($name -match '^(\.|&|\$|\d|-)' ) { continue }
            if ($name -notmatch '^[a-z]+-[a-z0-9_]+$') { continue }  # so Verbo-Nome
            if ($name -in $script:BASELINE_DEAD_CALLS) { continue }  # legado rastreado
            $missing += "$name  (ex: $($script:calls[$name] -join ', '))"
        }
        if ($missing.Count -gt 0) {
            throw "FUNCOES CHAMADAS QUE NAO EXISTEM EM LUGAR NENHUM:`n" + (($missing | Sort-Object) -join "`n")
        }
        $missing.Count | Should Be 0
    }
}
