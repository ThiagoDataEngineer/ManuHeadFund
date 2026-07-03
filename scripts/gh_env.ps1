# gh_env.ps1 — habilita gh CLI puxando o token do Windows Credential Manager.
# O token do git (usado no push) nao tem escopo read:org, entao `gh auth login`
# recusa — mas via GH_TOKEN todos os comandos de repo/actions funcionam.
# Uso: . .\scripts\gh_env.ps1   (dot-source; seta $env:GH_TOKEN na sessao)
# Zero credenciais em disco: extrai em runtime do credential manager.

$cred = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
$m = $cred | Select-String '^password=(.+)$'
if ($m) {
    $env:GH_TOKEN = $m.Matches.Groups[1].Value
    Write-Host "GH_TOKEN setado (credential manager). gh pronto." -ForegroundColor Green
} else {
    Write-Host "Nenhuma credencial GitHub no credential manager." -ForegroundColor Red
}
