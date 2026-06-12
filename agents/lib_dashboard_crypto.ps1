# lib_dashboard_crypto.ps1 - Criptografia dos dados do dashboard publico (2026-06-12)
# GitHub Pages nao tem auth; dados (capital/posicoes) vao cifrados e o browser
# decifra com senha via WebCrypto. Parametros ESPELHADOS com dashboard/unlock.js:
#   PBKDF2-SHA256 100000 iteracoes -> chave AES-256-GCM (nonce 12B, tag 16B)
# GCM = autenticado: senha errada SEMPRE falha (CBC podia retornar lixo).
# Requer pwsh 7 (.NET AesGcm) - publisher e testes rodam em pwsh.
# Formato publicado: { s, iv, ct } base64; ct = ciphertext||tag (padrao WebCrypto).

function Protect-DashboardData {
    param(
        [Parameter(Mandatory)] [string] $Json,
        [Parameter(Mandatory)] [string] $Password
    )
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $salt  = New-Object byte[] 16; $rng.GetBytes($salt)
    $nonce = New-Object byte[] 12; $rng.GetBytes($nonce)

    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        $Password, $salt, 100000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $key = $kdf.GetBytes(32); $kdf.Dispose()

    $pt  = [System.Text.Encoding]::UTF8.GetBytes($Json)
    $ct  = New-Object byte[] $pt.Length
    $tag = New-Object byte[] 16
    $gcm = [System.Security.Cryptography.AesGcm]::new($key, 16)
    $gcm.Encrypt($nonce, $pt, $ct, $tag)
    $gcm.Dispose()

    # WebCrypto espera ciphertext com tag anexada no final
    $ctTag = New-Object byte[] ($ct.Length + 16)
    [Array]::Copy($ct, 0, $ctTag, 0, $ct.Length)
    [Array]::Copy($tag, 0, $ctTag, $ct.Length, 16)

    return [PSCustomObject]@{
        s  = [Convert]::ToBase64String($salt)
        iv = [Convert]::ToBase64String($nonce)
        ct = [Convert]::ToBase64String($ctTag)
    }
}

# Espelho do unlock.js - usado nos testes de round-trip (garante formato correto)
function Unprotect-DashboardData {
    param(
        [Parameter(Mandatory)] [object] $Envelope,  # { s, iv, ct }
        [Parameter(Mandatory)] [string] $Password
    )
    $salt  = [Convert]::FromBase64String($Envelope.s)
    $nonce = [Convert]::FromBase64String($Envelope.iv)
    $ctTag = [Convert]::FromBase64String($Envelope.ct)

    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        $Password, $salt, 100000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $key = $kdf.GetBytes(32); $kdf.Dispose()

    $ct  = $ctTag[0..($ctTag.Length - 17)]
    $tag = $ctTag[($ctTag.Length - 16)..($ctTag.Length - 1)]
    $pt  = New-Object byte[] $ct.Length
    $gcm = [System.Security.Cryptography.AesGcm]::new($key, 16)
    $gcm.Decrypt($nonce, [byte[]]$ct, [byte[]]$tag, $pt)  # senha errada -> AuthenticationTagMismatch
    $gcm.Dispose()

    return [System.Text.Encoding]::UTF8.GetString($pt)
}
