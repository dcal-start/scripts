#requires -version 5.1
<#
.SYNOPSIS
    Verifica se il server richiede un riavvio analizzando tutti gli indicatori di sistema.

.DESCRIPTION
    Controlla tutte le principali fonti di pending reboot:
    - Component Based Servicing (CBS)
    - Windows Update
    - Pending File Rename Operations
    - SCCM / ConfigMgr (via CIM)
    - Computer Rename
    - Domain Join
    - Post Reboot Reporting
    - RunOnce Operations

.PARAMETER ComputerName
    Nome del computer da verificare. Default: computer locale.

.PARAMETER ShowPendingFiles
    Se specificato, mostra il dettaglio dei file in coda nelle Pending File Rename Operations.

.PARAMETER Quiet
    Se specificato, restituisce solo l'oggetto senza output formattato a console.

.EXAMPLE
    .\Get-PendingReboot.ps1
    Verifica standard con output formattato.

.EXAMPLE
    .\Get-PendingReboot.ps1 -ShowPendingFiles
    Verifica con dettaglio dei file in coda di rinomina/eliminazione.

.EXAMPLE
    .\Get-PendingReboot.ps1 -Quiet
    Restituisce solo l'oggetto PSCustomObject per uso in automazioni.

.EXAMPLE
    $result = .\Get-PendingReboot.ps1 -Quiet; if ($result.RebootRequired) { Write-Host "Reboot needed" }
    Uso programmatico in script di automazione.

.NOTES
    Autore: SysAdmin Script
    Richiede: Privilegi amministrativi
    Exit codes: 0 = no reboot, 1 = reboot required, 2 = errore
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter()]
    [switch]$ShowPendingFiles,

    [Parameter()]
    [switch]$Quiet
)

function Get-PendingRebootStatus {
    [CmdletBinding()]
    param(
        [string]$ComputerName = $env:COMPUTERNAME
    )

    $result = [PSCustomObject]@{
        ComputerName                = $ComputerName
        CheckTime                   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        RebootRequired              = $false
        CBSRebootPending            = $false
        WindowsUpdateRebootRequired = $false
        PendingFileRenameOperations = $false
        PendingFileRenameDetails    = @()
        SCCMRebootPending           = $null
        ComputerRenamePending       = $false
        DomainJoinPending           = $false
        PostRebootReporting         = $false
        ServicesRequiringReboot     = @()
        LastBootTime                = $null
        UptimeDays                  = $null
    }

    try {
        # 1. Component Based Servicing (CBS)
        if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
            $result.CBSRebootPending = $true
        }

        # 2. Windows Update - RebootRequired
        if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
            $result.WindowsUpdateRebootRequired = $true
        }

        # 3. Pending File Rename Operations
        $pfroPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
        $pfroValue = Get-ItemProperty -Path $pfroPath -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
        if ($pfroValue.PendingFileRenameOperations) {
            $result.PendingFileRenameOperations = $true
            $result.PendingFileRenameDetails = $pfroValue.PendingFileRenameOperations | Where-Object { $_ -ne "" }
        }

        # 4. SCCM Client (via CIM, con fallback registry)
        try {
            $sccmClient = Invoke-CimMethod -Namespace "root\ccm\ClientSDK" -ClassName "CCM_ClientUtilities" `
                -MethodName "DetermineIfRebootPending" -ErrorAction Stop
            if ($sccmClient) {
                $result.SCCMRebootPending = ($sccmClient.RebootPending -or $sccmClient.IsHardRebootPending)
            }
        }
        catch {
            # Fallback: check registry
            if (Test-Path "HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData") {
                $result.SCCMRebootPending = $true
            }
            # SCCM non presente -> $null
        }

        # 5. Computer Rename Pending
        $activeComputerName = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName" -ErrorAction SilentlyContinue).ComputerName
        $pendingComputerName = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName" -ErrorAction SilentlyContinue).ComputerName
        if ($activeComputerName -ne $pendingComputerName) {
            $result.ComputerRenamePending = $true
        }

        # 6. Domain Join Pending
        $netlogonPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon"
        $joinDomain = Get-ItemProperty -Path $netlogonPath -Name "JoinDomain" -ErrorAction SilentlyContinue
        if ($joinDomain.JoinDomain) {
            $result.DomainJoinPending = $true
        }

        # 7. Post Reboot Reporting (CBS in progress)
        if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress") {
            $result.PostRebootReporting = $true
        }

        # 8. RunOnce operations
        $runOncePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
        if (Test-Path $runOncePath) {
            $runOnceItems = Get-ItemProperty -Path $runOncePath -ErrorAction SilentlyContinue
            if ($runOnceItems) {
                $services = $runOnceItems.PSObject.Properties | 
                    Where-Object { $_.Name -notlike "PS*" } | 
                    Select-Object -ExpandProperty Name
                $result.ServicesRequiringReboot = @($services)
            }
        }

        # 9. Uptime
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $result.LastBootTime = $os.LastBootUpTime
        $result.UptimeDays = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 2)

        # Determinazione finale
        $result.RebootRequired = $result.CBSRebootPending -or 
                                  $result.WindowsUpdateRebootRequired -or 
                                  $result.PendingFileRenameOperations -or 
                                  ($result.SCCMRebootPending -eq $true) -or
                                  $result.ComputerRenamePending -or 
                                  $result.DomainJoinPending -or
                                  $result.PostRebootReporting
    }
    catch {
        throw "Errore durante la verifica: $_"
    }

    return $result
}

function Show-RebootStatus {
    param(
        [PSCustomObject]$Status,
        [switch]$ShowPendingFiles
    )

    Write-Host "`n===============================================================" -ForegroundColor Cyan
    Write-Host "  STATO RIAVVIO SERVER: $($Status.ComputerName)" -ForegroundColor Cyan
    Write-Host "  Verifica eseguita: $($Status.CheckTime)" -ForegroundColor Gray
    Write-Host "===============================================================" -ForegroundColor Cyan

    if ($Status.RebootRequired) {
        Write-Host "`n  [!] RIAVVIO RICHIESTO" -ForegroundColor Red
    } else {
        Write-Host "`n  [OK] NESSUN RIAVVIO RICHIESTO" -ForegroundColor Green
    }

    Write-Host "`n---------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  INDICATORI:" -ForegroundColor Yellow
    Write-Host "---------------------------------------------------------------" -ForegroundColor DarkGray

    $indicators = @(
        @{ Name = "CBS Reboot Pending"; Value = $Status.CBSRebootPending },
        @{ Name = "Windows Update Reboot"; Value = $Status.WindowsUpdateRebootRequired },
        @{ Name = "Pending File Rename Ops"; Value = $Status.PendingFileRenameOperations },
        @{ Name = "SCCM Reboot Pending"; Value = $Status.SCCMRebootPending },
        @{ Name = "Computer Rename Pending"; Value = $Status.ComputerRenamePending },
        @{ Name = "Domain Join Pending"; Value = $Status.DomainJoinPending },
        @{ Name = "Post Reboot Reporting"; Value = $Status.PostRebootReporting }
    )

    foreach ($ind in $indicators) {
        $color = if ($ind.Value -eq $true) { "Red" } elseif ($ind.Value -eq $false) { "Green" } else { "Gray" }
        $symbol = if ($ind.Value -eq $true) { "[!]" } elseif ($ind.Value -eq $false) { "[OK]" } else { "[--]" }
        Write-Host "  $symbol $($ind.Name.PadRight(25)): $($ind.Value)" -ForegroundColor $color
    }

    # Dettaglio PFRO solo se richiesto
    if ($ShowPendingFiles -and $Status.PendingFileRenameOperations -and $Status.PendingFileRenameDetails.Count -gt 0) {
        Write-Host "`n---------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "  FILE IN CODA (Pending File Rename Operations):" -ForegroundColor Yellow
        Write-Host "---------------------------------------------------------------" -ForegroundColor DarkGray
        foreach ($file in $Status.PendingFileRenameDetails) {
            if ($file) { Write-Host "    $file" -ForegroundColor DarkYellow }
        }
    }

    # RunOnce
    if ($Status.ServicesRequiringReboot.Count -gt 0) {
        Write-Host "`n---------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "  RUNONCE PENDENTI:" -ForegroundColor Yellow
        Write-Host "---------------------------------------------------------------" -ForegroundColor DarkGray
        foreach ($svc in $Status.ServicesRequiringReboot) {
            Write-Host "    $svc" -ForegroundColor DarkYellow
        }
    }

    # Uptime
    Write-Host "`n---------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Ultimo avvio: $($Status.LastBootTime)" -ForegroundColor Gray
    Write-Host "  Uptime: $($Status.UptimeDays) giorni" -ForegroundColor Gray
    Write-Host "===============================================================`n" -ForegroundColor Cyan
}

# === MAIN ===
try {
    $status = Get-PendingRebootStatus -ComputerName $ComputerName
}
catch {
    Write-Error $_.Exception.Message
    if (-not $Quiet) {
        Write-Host "`nPremi un tasto per chiudere..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    exit 2
}

if (-not $Quiet) {
    Show-RebootStatus -Status $status -ShowPendingFiles:$ShowPendingFiles
    Write-Host "Premi un tasto per chiudere..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Output oggetto per pipeline
$status

# Exit code per automazione
exit ([int]$status.RebootRequired)
