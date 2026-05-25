# setup_github_secrets.ps1 - Configura secrets no GitHub via API REST
# Requer: Personal Access Token com scope 'repo'

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "SETUP GITHUB SECRETS" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ============================================================================
# 1. Solicitar Personal Access Token
# ============================================================================

Write-Host "Para configurar os secrets, vocÃª precisa de um Personal Access Token." -ForegroundColor Yellow
Write-Host "Crie um em: https://github.com/settings/tokens" -ForegroundColor Yellow
Write-Host "Scopes necessÃ¡rios: repo, workflow`n" -ForegroundColor Yellow

$token = Read-Host "Cole seu Personal Access Token aqui" -AsSecureString
$tokenPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($token)
)

if (-not $tokenPlain) {
    Write-Host "[ERRO] Token nÃ£o fornecido" -ForegroundColor Red
    exit 1
}

# ============================================================================
# 2. Carregar credenciais locais
# ============================================================================

Write-Host "[1/5] Carregando credenciais locais..." -ForegroundColor Gray

. (Join-Path $PSScriptRoot "..\agents\config.local.ps1")

$secrets = @{
    "COINEX_ACCESS_ID"    = $env:COINEX_ACCESS_ID
    "COINEX_SECRET_KEY"   = $env:COINEX_SECRET_KEY
    "TELEGRAM_BOT_TOKEN"  = $env:TELEGRAM_BOT_TOKEN
    "TELEGRAM_CHAT_ID"    = $env:TELEGRAM_CHAT_ID
}

# Validar
$missing = @()
foreach ($key in $secrets.Keys) {
    if (-not $secrets[$key]) {
        $missing += $key
    }
}

if ($missing.Count -gt 0) {
    Write-Host "[ERRO] Credenciais faltando: $($missing -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Credenciais carregadas" -ForegroundColor Green

# ============================================================================
# 3. Obter Public Key do repositÃ³rio
# ============================================================================

Write-Host "[2/5] Obtendo public key do repositÃ³rio..." -ForegroundColor Gray

$owner = "ThiagoDataEngineer"
$repo = "ManuHeadFund"
$headers = @{
    "Authorization" = "Bearer $tokenPlain"
    "Accept" = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

try {
    $publicKeyUrl = "https://api.github.com/repos/$owner/$repo/actions/secrets/public-key"
    $publicKeyResponse = Invoke-RestMethod -Uri $publicKeyUrl -Headers $headers -Method Get
    
    $publicKey = $publicKeyResponse.key
    $keyId = $publicKeyResponse.key_id
    
    Write-Host "[OK] Public key obtida (ID: $keyId)" -ForegroundColor Green
} catch {
    Write-Host "[ERRO] Falha ao obter public key: $_" -ForegroundColor Red
    Write-Host "Verifique se o token tem permissÃµes corretas" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# 4. FunÃ§Ã£o para criptografar secret
# ============================================================================

function Encrypt-Secret {
    param(
        [string]$PlainText,
        [string]$PublicKey
    )
    
    # Converter public key de Base64
    $publicKeyBytes = [Convert]::FromBase64String($PublicKey)
    
    # Usar libsodium via .NET (requer Sodium.Core NuGet)
    # Alternativa: usar Python ou Node.js para criptografar
    
    # NOTA: PowerShell nÃ£o tem suporte nativo para libsodium
    # Vamos usar uma abordagem alternativa via Python
    
    $pythonScript = @"
import sys
import base64
from nacl import encoding, public

def encrypt(public_key: str, secret_value: str) -> str:
    public_key_bytes = public.PublicKey(public_key.encode('utf-8'), encoding.Base64Encoder())
    sealed_box = public.SealedBox(public_key_bytes)
    encrypted = sealed_box.encrypt(secret_value.encode('utf-8'))
    return base64.b64encode(encrypted).decode('utf-8')

if __name__ == '__main__':
    public_key = sys.argv[1]
    secret_value = sys.argv[2]
    print(encrypt(public_key, secret_value))
"@
    
    # Salvar script temporÃ¡rio
    $tempScript = Join-Path $env:TEMP "encrypt_secret.py"
    $pythonScript | Out-File -FilePath $tempScript -Encoding UTF8
    
    try {
        # Executar Python
        $encrypted = python $tempScript $PublicKey $PlainText 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            throw "Python falhou: $encrypted"
        }
        
        return $encrypted.Trim()
    } finally {
        Remove-Item $tempScript -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# 5. Verificar se Python e PyNaCl estÃ£o instalados
# ============================================================================

Write-Host "[3/5] Verificando dependÃªncias..." -ForegroundColor Gray

try {
    $pythonVersion = python --version 2>&1
    Write-Host "  Python: $pythonVersion" -ForegroundColor Gray
} catch {
    Write-Host "[ERRO] Python nÃ£o encontrado" -ForegroundColor Red
    Write-Host "Instale Python: https://www.python.org/downloads/" -ForegroundColor Yellow
    exit 1
}

try {
    python -c "import nacl" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Instalando PyNaCl..." -ForegroundColor Yellow
        pip install PyNaCl | Out-Null
    }
    Write-Host "  PyNaCl: OK" -ForegroundColor Gray
} catch {
    Write-Host "[ERRO] Falha ao instalar PyNaCl" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] DependÃªncias verificadas" -ForegroundColor Green

# ============================================================================
# 6. Criar secrets no GitHub
# ============================================================================

Write-Host "[4/5] Criando secrets no GitHub..." -ForegroundColor Gray

$successCount = 0
$failCount = 0

foreach ($secretName in $secrets.Keys) {
    $secretValue = $secrets[$secretName]
    
    Write-Host "  Criando $secretName..." -ForegroundColor Gray
    
    try {
        # Criptografar secret
        $encryptedValue = Encrypt-Secret -PlainText $secretValue -PublicKey $publicKey
        
        # Criar/atualizar secret
        $secretUrl = "https://api.github.com/repos/$owner/$repo/actions/secrets/$secretName"
        $body = @{
            encrypted_value = $encryptedValue
            key_id = $keyId
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri $secretUrl -Headers $headers -Method Put -Body $body -ContentType "application/json"
        
        Write-Host "    [OK] $secretName criado" -ForegroundColor Green
        $successCount++
    } catch {
        Write-Host "    [ERRO] Falha ao criar $secretName : $_" -ForegroundColor Red
        $failCount++
    }
}

# ============================================================================
# 7. Resumo
# ============================================================================

Write-Host "`n[5/5] Resumo:" -ForegroundColor Gray
Write-Host "  Sucesso: $successCount secrets" -ForegroundColor Green
Write-Host "  Falhas: $failCount secrets" -ForegroundColor $(if($failCount -gt 0){"Red"}else{"Green"})

if ($successCount -eq 4) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "SECRETS CONFIGURADOS COM SUCESSO!" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
    
    Write-Host "PrÃ³ximos passos:" -ForegroundColor Yellow
    Write-Host "1. Verifique os secrets em: https://github.com/$owner/$repo/settings/secrets/actions" -ForegroundColor Gray
    Write-Host "2. Habilite GitHub Actions em: https://github.com/$owner/$repo/settings/actions" -ForegroundColor Gray
    Write-Host "3. Aguarde a primeira execuÃ§Ã£o do workflow (15 minutos)" -ForegroundColor Gray
    Write-Host "4. Verifique mensagens no Telegram`n" -ForegroundColor Gray
} else {
    Write-Host "`n========================================" -ForegroundColor Yellow
    Write-Host "ALGUNS SECRETS FALHARAM" -ForegroundColor Yellow
    Write-Host "========================================`n" -ForegroundColor Yellow
    
    Write-Host "Configure manualmente em: https://github.com/$owner/$repo/settings/secrets/actions" -ForegroundColor Gray
}
