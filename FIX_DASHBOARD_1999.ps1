# FIX_DASHBOARD_1999.ps1
# Substitui datas de 1999 por "Aguardando" no dashboard HTML

$htmlPath = "$PSScriptRoot\dashboard\index.html"

if (Test-Path $htmlPath) {
    $html = [System.IO.File]::ReadAllText($htmlPath, [System.Text.Encoding]::UTF8)
    
    # Substituir 30/11 00:00 por "Aguardando"
    $html = $html -replace '30/11 00:00', '<span style="color: #9fa8da; font-style: italic;">Aguardando</span>'
    
    # Substituir ERRO por — quando a data é "Aguardando"
    $html = $html -replace '(<td><span style="color: #9fa8da; font-style: italic;">Aguardando</span></td>\s*<td>[^<]+</td>\s*<td><span class=''status-negative''>)ERRO(</span></td>)', '$1—$2'
    
    [System.IO.File]::WriteAllText($htmlPath, $html, [System.Text.Encoding]::UTF8)
    
    Write-Host "Dashboard atualizado! Datas de 1999 substituidas." -ForegroundColor Green
}
