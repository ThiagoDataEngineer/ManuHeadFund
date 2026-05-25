# CONSERTAR_DNS_LLM.ps1
# Adiciona entradas no hosts para bypassar bloqueio DNS (Cisco Umbrella)
# RODAR COMO ADMINISTRADOR
#
# Problema diagnosticado em 2026-05-25:
#   - DNS local (172.16.255.254 + Cisco Umbrella) esta bloqueando api.anthropic.com
#   - Resolve para 146.112.61.106 (block page) em vez do IP real
#   - Causa: certificado SSL invalido -> "A conexao subjacente estava fechada"
#   - Resultado: Mentor indisponivel -> VETO automatico de TODOS os trades

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host "=== CONSERTANDO DNS PARA APIs LLM ===" -ForegroundColor Cyan
Write-Host ""

# Verificar admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERRO: Precisa rodar como ADMINISTRADOR" -ForegroundColor Red
    Write-Host "Clique direito no PowerShell -> 'Executar como administrador'" -ForegroundColor Yellow
    exit 1
}

# Resolver IPs reais via DoH (DNS over HTTPS via Cloudflare)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "[1/4] Resolvendo IPs reais via Cloudflare DoH..." -ForegroundColor Yellow
$hosts = @{
    "api.anthropic.com" = $null
    "api.groq.com" = $null
    "generativelanguage.googleapis.com" = $null
}

foreach ($domain in @($hosts.Keys)) {
    try {
        $r = Invoke-RestMethod -Uri "https://cloudflare-dns.com/dns-query?name=$domain&type=A" -Headers @{"Accept"="application/dns-json"}
        $ip = ($r.Answer | Where-Object { $_.type -eq 1 } | Select-Object -First 1).data
        $hosts[$domain] = $ip
        Write-Host "  $domain -> $ip" -ForegroundColor Green
    } catch {
        Write-Host "  $domain -> FALHA: $_" -ForegroundColor Red
    }
}

# Backup do hosts atual
$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
$backupFile = "$env:USERPROFILE\hosts_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
Copy-Item $hostsFile $backupFile -Force
Write-Host "`n[2/4] Backup criado: $backupFile" -ForegroundColor Yellow

# Limpar entradas antigas e adicionar novas
Write-Host "`n[3/4] Atualizando hosts file..." -ForegroundColor Yellow
$current = Get-Content $hostsFile

# Remover entradas antigas das nossas APIs
$cleaned = $current | Where-Object { 
    $_ -notmatch "api\.anthropic\.com" -and 
    $_ -notmatch "api\.groq\.com" -and 
    $_ -notmatch "generativelanguage\.googleapis\.com" -and
    $_ -notmatch "=== LLM APIs"
}

# Adicionar marcador
$newLines = @()
$newLines += ""
$newLines += "# === LLM APIs - bypass Cisco Umbrella DNS block ==="
$newLines += "# Adicionado em $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
foreach ($domain in $hosts.Keys) {
    if ($hosts[$domain]) {
        $newLines += "$($hosts[$domain])`t$domain"
    }
}
$newLines += "# === fim LLM APIs ==="

$final = @($cleaned) + $newLines
$final | Set-Content $hostsFile -Encoding ASCII -Force
Write-Host "  Hosts atualizado com $($hosts.Keys.Count) entradas" -ForegroundColor Green

# Limpar cache DNS
Write-Host "`n[4/4] Limpando cache DNS..." -ForegroundColor Yellow
ipconfig /flushdns | Out-Null
Write-Host "  Cache DNS limpo" -ForegroundColor Green

# Verificar
Write-Host "`n=== VERIFICACAO ===" -ForegroundColor Cyan
foreach ($domain in $hosts.Keys) {
    $resolved = (Resolve-DnsName $domain -Type A -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
    $expected = $hosts[$domain]
    $match = if ($resolved -eq $expected) { "OK" } else { "MISMATCH" }
    Write-Host "  $domain -> $resolved (esperado: $expected) $match" -ForegroundColor $(if ($match -eq "OK") { "Green" } else { "Red" })
}

Write-Host "`nPRONTO! Agora teste com:" -ForegroundColor Cyan
Write-Host "  .\scripts\test_llm_providers.ps1" -ForegroundColor White
Write-Host ""
Write-Host "Para reverter, restaure: $backupFile" -ForegroundColor DarkGray
