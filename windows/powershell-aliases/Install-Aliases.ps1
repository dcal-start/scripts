# Install-Aliases.ps1
# Installa tutti gli alias PowerShell nel profilo dell'utente corrente.
# Uso: .\Install-Aliases.ps1

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$aliasFiles = Get-ChildItem -Path $scriptDir -Filter "*.ps1" | Where-Object { $_.Name -ne "Install-Aliases.ps1" }

if ($aliasFiles.Count -eq 0) {
    Write-Host "Nessun alias trovato da installare." -ForegroundColor Yellow
    return
}

# Crea la directory del profilo se non esiste
$profileDir = Split-Path -Parent $PROFILE
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    Write-Host "Creata directory profilo: $profileDir"
}

# Leggi il profilo esistente (se esiste)
$profileContent = ""
if (Test-Path $PROFILE) {
    $profileContent = Get-Content $PROFILE -Raw
}

# Marcatore per identificare la sezione gestita da questo installer
$markerStart = "# >>> powershell-aliases (infra-ops) >>>"
$markerEnd = "# <<< powershell-aliases (infra-ops) <<<"

# Costruisci il blocco con tutti gli alias
$aliasBlock = @()
$aliasBlock += $markerStart
foreach ($file in $aliasFiles) {
    $aliasBlock += ""
    $aliasBlock += (Get-Content $file.FullName -Raw).TrimEnd()
}
$aliasBlock += ""
$aliasBlock += $markerEnd
$newBlock = $aliasBlock -join "`n"

# Sostituisci il blocco esistente o aggiungilo
if ($profileContent -match [regex]::Escape($markerStart)) {
    $pattern = "(?s)" + [regex]::Escape($markerStart) + ".*?" + [regex]::Escape($markerEnd)
    $profileContent = [regex]::Replace($profileContent, $pattern, $newBlock)
    Write-Host "Alias aggiornati nel profilo." -ForegroundColor Green
} else {
    if ($profileContent) {
        $profileContent = $profileContent.TrimEnd() + "`n`n" + $newBlock + "`n"
    } else {
        $profileContent = $newBlock + "`n"
    }
    Write-Host "Alias aggiunti al profilo." -ForegroundColor Green
}

Set-Content -Path $PROFILE -Value $profileContent -NoNewline

Write-Host ""
Write-Host "Alias installati:" -ForegroundColor Cyan
foreach ($file in $aliasFiles) {
    Write-Host "  - $($file.BaseName)" -ForegroundColor Cyan
}
Write-Host ""
Write-Host "Riavvia PowerShell per attivare gli alias." -ForegroundColor Yellow
