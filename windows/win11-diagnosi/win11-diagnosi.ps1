#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnostica completa Windows 11 - Script portabile
.DESCRIPTION
    Analizza un sistema Windows 11 e produce un report Markdown dettagliato
    pronto per essere sottoposto a un'AI (Claude, ChatGPT, ecc.) per valutazioni.
    Eseguire come Amministratore per risultati completi.
.NOTES
    Versione: 1.3
    Autore: Generato con Claude Code
    Compatibilita': Windows 10/11, PowerShell 5.1+
.EXAMPLE
    .\win11-diagnosi.ps1
    .\win11-diagnosi.ps1 -OutputPath "C:\Reports"
    .\win11-diagnosi.ps1 -TestLabel A
    .\win11-diagnosi.ps1 -TestLabel B -OutputPath "C:\Reports"
    .\win11-diagnosi.ps1 -DeepDiskScan
#>

param(
    [string]$OutputPath = $PSScriptRoot,
    [string]$TestLabel = "",
    [switch]$DeepDiskScan
)

$ErrorActionPreference = 'Continue'

# Validate TestLabel: only alphanumeric, dash, underscore allowed
if ($TestLabel -and $TestLabel -notmatch '^[A-Za-z0-9_-]+$') {
    Write-Host "  [ERRORE] -TestLabel accetta solo lettere, numeri, trattino e underscore." -ForegroundColor Red
    Write-Host "  Esempio: -TestLabel A, -TestLabel pre-reboot, -TestLabel test_1" -ForegroundColor Yellow
    exit 1
}

$script:warningsCount = 0
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$hostname = $env:COMPUTERNAME
$labelTag = if ($TestLabel) { "_Test${TestLabel}" } else { "" }
$reportFile = Join-Path $OutputPath "diagnosi_${hostname}${labelTag}_${timestamp}.md"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Helper: format size
function Format-Size($bytes) {
    if ($bytes -ge 1GB) { return "{0:N1} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N0} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:N0} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

# Helper: safe folder size (recursive, no depth limit)
function Get-FolderSize($path) {
    if (-not (Test-Path $path)) { return 0 }
    try {
        (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum -ErrorAction SilentlyContinue).Sum
    } catch { 0 }
}

# Progress tracking
$sections = @(
    "Informazioni Sistema",
    "Hardware",
    "Memoria",
    "Dischi",
    "Processi Top RAM",
    "Processi Top CPU",
    "Handle Count",
    "Servizi in svchost",
    "Analisi Spazio Disco",
    "Overlay Handlers",
    "Shell Extensions in Explorer",
    "Startup Programs",
    "Scheduled Tasks",
    "Servizi Auto non Running",
    "Windows Defender",
    "Event Log Errori",
    "Power Plan",
    "Rete",
    "Note Finali"
)
$currentSection = 0

function Write-Progress-Section($name) {
    $script:currentSection++
    $pct = [math]::Round($script:currentSection / $sections.Count * 100)
    Write-Progress -Activity "Diagnosi Sistema" -Status "$name ($script:currentSection/$($sections.Count))" -PercentComplete $pct
    Write-Host "  [$script:currentSection/$($sections.Count)] $name..."
}

# ===== BUILD REPORT =====
$report = [System.Text.StringBuilder]::new()

function Add-Line($text = "") { [void]$report.AppendLine($text) }
function Escape-TableCell($text) { if ($text) { $text -replace '\|', '\|' } else { "" } }

Write-Host ""
Write-Host "============================================="
Write-Host "  DIAGNOSI SISTEMA WINDOWS 11 - PORTABILE"
if ($TestLabel) { Write-Host "  TEST: $TestLabel" }
Write-Host "============================================="
Write-Host "  $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
Write-Host "  Computer: $hostname"
Write-Host "  Admin: $isAdmin"
Write-Host "  Output: $reportFile"
Write-Host "============================================="
Write-Host ""

# --- HEADER ---
$labelHeader = if ($TestLabel) { " - Test $TestLabel" } else { "" }
Add-Line "# Diagnosi Sistema Windows - $hostname$labelHeader"
Add-Line "Data: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
if ($TestLabel) { Add-Line "Test: **$TestLabel**" }
Add-Line "Eseguito come amministratore: $isAdmin"
Add-Line ""

# --- 1. SYSTEM INFO ---
Write-Progress-Section "Informazioni Sistema"
$os = $null; $cs = $null; $bios = $null
try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { $script:warningsCount++ }
try { $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop } catch { $script:warningsCount++ }
try { $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop } catch { $script:warningsCount++ }

Add-Line "## 1. Informazioni Sistema"
Add-Line "| Proprieta' | Valore |"
Add-Line "|-----------|--------|"
Add-Line "| Computer | $(if ($cs) { $cs.Name } else { $env:COMPUTERNAME }) |"
Add-Line "| Produttore | $(if ($cs) { $cs.Manufacturer } else { 'N/A' }) |"
Add-Line "| Modello | $(if ($cs) { $cs.Model } else { 'N/A' }) |"
Add-Line "| OS | $(if ($os) { "$($os.Caption) $($os.Version) Build $($os.BuildNumber)" } else { 'N/A (accesso negato)' }) |"
Add-Line "| Architettura | $(if ($os) { $os.OSArchitecture } else { 'N/A' }) |"
Add-Line "| BIOS | $(if ($bios) { $bios.SMBIOSBIOSVersion } else { 'N/A' }) |"
Add-Line "| Ultimo Boot | $(if ($os) { $os.LastBootUpTime } else { 'N/A' }) |"
Add-Line "| Uptime | $(if ($os -and $os.LastBootUpTime) { (Get-Date) - $os.LastBootUpTime } else { 'N/A' }) |"
Add-Line "| Utente | $($env:USERNAME) |"
Add-Line ""

# --- 2. HARDWARE ---
Write-Progress-Section "Hardware"
$cpu = $null; $gpu = $null; $battery = $null
try { $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop } catch { $script:warningsCount++ }
try { $gpu = Get-CimInstance Win32_VideoController -ErrorAction Stop } catch { $script:warningsCount++ }
try { $battery = Get-CimInstance Win32_Battery -ErrorAction Stop } catch {}

Add-Line "## 2. Hardware"
Add-Line "### CPU"
Add-Line "| Proprieta' | Valore |"
Add-Line "|-----------|--------|"
if ($cpu) {
    Add-Line "| Modello | $($cpu.Name) |"
    Add-Line "| Core | $($cpu.NumberOfCores) |"
    Add-Line "| Logical Processors | $($cpu.NumberOfLogicalProcessors) |"
    Add-Line "| Max Clock | $($cpu.MaxClockSpeed) MHz |"
    Add-Line "| Carico attuale | $($cpu.LoadPercentage)% |"
} else {
    Add-Line "| (dati non disponibili - accesso negato) | |"
}
Add-Line ""

if ($gpu) {
    Add-Line "### GPU"
    foreach ($g in $gpu) {
        $vramMB = if ($g.AdapterRAM) { [math]::Round($g.AdapterRAM / 1MB, 0) } else { 0 }
        Add-Line "- $($g.Name) (VRAM: ${vramMB} MB, Driver: $($g.DriverVersion))"
    }
    Add-Line ""
}

if ($battery) {
    Add-Line "### Batteria"
    Add-Line "- Stato: $($battery.Status) | Carica: $($battery.EstimatedChargeRemaining)% | BatteryStatus: $($battery.BatteryStatus)"
    Add-Line ""
}

# --- 3. MEMORIA ---
Write-Progress-Section "Memoria"
if ($os -and $os.TotalVisibleMemorySize -gt 0) {
    $totalRAM = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeRAM = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $usedRAM = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
    $pctRAM = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 1)
} else {
    $totalRAM = "N/A"; $freeRAM = "N/A"; $usedRAM = "N/A"; $pctRAM = "N/A"
    $script:warningsCount++
}

$perf = $null
try { $perf = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop } catch { $script:warningsCount++ }
$commitGB = if ($perf) { [math]::Round($perf.CommittedBytes / 1GB, 1) } else { "N/A" }
$commitLimitGB = if ($perf) { [math]::Round($perf.CommitLimit / 1GB, 1) } else { "N/A" }
$availMB = if ($perf) { $perf.AvailableMBytes } else { "N/A" }
$poolPaged = if ($perf) { [math]::Round($perf.PoolPagedBytes / 1MB, 0) } else { "N/A" }
$poolNonPaged = if ($perf) { [math]::Round($perf.PoolNonpagedBytes / 1MB, 0) } else { "N/A" }

Add-Line "## 3. Memoria RAM"
Add-Line "| Metrica | Valore |"
Add-Line "|---------|--------|"
Add-Line "| RAM Totale | $totalRAM GB |"
Add-Line "| RAM Usata | $usedRAM GB |"
Add-Line "| RAM Libera | $freeRAM GB |"
Add-Line "| Utilizzo | **$pctRAM%** |"
Add-Line "| Committed | $commitGB / $commitLimitGB GB |"
Add-Line "| Available | $availMB MB |"
Add-Line "| Pool Paged | $poolPaged MB |"
Add-Line "| Pool Non-Paged | $poolNonPaged MB |"
Add-Line ""

$pf = $null
try { $pf = Get-CimInstance Win32_PageFileUsage -ErrorAction Stop } catch {}
if ($pf) {
    Add-Line "### Paging File"
    foreach ($p in $pf) {
        Add-Line "- $($p.Name) | Allocato: $($p.AllocatedBaseSize) MB | In uso: $($p.CurrentUsage) MB | Picco: $($p.PeakUsage) MB"
    }
    Add-Line ""
}

# --- 4. DISCHI ---
Write-Progress-Section "Dischi"
Add-Line "## 4. Dischi"
Add-Line "| Drive | Dimensione | Libero | Usato % |"
Add-Line "|-------|-----------|--------|---------|"
try {
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop | ForEach-Object {
        if ($_.Size -and $_.Size -gt 0) {
            $sizeGB = [math]::Round($_.Size / 1GB, 1)
            $freeGB = [math]::Round($_.FreeSpace / 1GB, 1)
            $usedPct = [math]::Round(($_.Size - $_.FreeSpace) / $_.Size * 100, 1)
            $flag = if ($usedPct -gt 90) { " **CRITICO**" } elseif ($usedPct -gt 80) { " *ATTENZIONE*" } else { "" }
            Add-Line "| $($_.DeviceID) | $sizeGB GB | $freeGB GB | **$usedPct%**$flag |"
        }
    }
} catch {
    Add-Line "| (dati non disponibili - accesso negato) | | | |"
    $script:warningsCount++
}
Add-Line ""

# --- 5. TOP PROCESSI RAM ---
Write-Progress-Section "Processi Top RAM"
Add-Line "## 5. Top 25 Processi per RAM"
Add-Line "| # | Processo | PID | RAM | CPU (s) | Handles |"
Add-Line "|---|---------|-----|-----|---------|---------|"
$rank = 0
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 25 | ForEach-Object {
    $rank++
    $cpuSec = if ($_.CPU) { [math]::Round($_.CPU, 1) } else { 0 }
    $ramMB = [math]::Round($_.WorkingSet64 / 1MB, 0)
    Add-Line "| $rank | $($_.Name) | $($_.Id) | $ramMB MB | $cpuSec | $($_.HandleCount) |"
}
Add-Line ""

# Process groups summary
Add-Line "### Raggruppamento processi per nome (top RAM)"
Add-Line "| Processo | Istanze | RAM Totale |"
Add-Line "|---------|---------|-----------|"
Get-Process | Group-Object Name | ForEach-Object {
    $totalMB = [math]::Round(($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 0)
    [PSCustomObject]@{ Name = $_.Name; Count = $_.Count; TotalMB = $totalMB }
} | Sort-Object TotalMB -Descending | Select-Object -First 20 | ForEach-Object {
    Add-Line "| $($_.Name) | $($_.Count) | $($_.TotalMB) MB |"
}
Add-Line ""

# --- 6. TOP PROCESSI CPU ---
Write-Progress-Section "Processi Top CPU"
Add-Line "## 6. Top 25 Processi per Tempo CPU"
Add-Line "| # | Processo | PID | CPU (s) | RAM | Handles |"
Add-Line "|---|---------|-----|---------|-----|---------|"
$rank = 0
Get-Process | Where-Object { $_.CPU -gt 0 } | Sort-Object CPU -Descending | Select-Object -First 25 | ForEach-Object {
    $rank++
    $cpuSec = [math]::Round($_.CPU, 1)
    $ramMB = [math]::Round($_.WorkingSet64 / 1MB, 0)
    $flag = ""
    # Flag explorer.exe if CPU > 1 hour
    if ($_.Name -eq "explorer" -and $_.CPU -gt 3600) { $flag = " **ANOMALO**" }
    Add-Line "| $rank | $($_.Name)$flag | $($_.Id) | $cpuSec | $ramMB MB | $($_.HandleCount) |"
}
Add-Line ""

# --- 7. HANDLE COUNT ---
Write-Progress-Section "Handle Count"
$totalHandles = (Get-Process | Measure-Object HandleCount -Sum).Sum
Add-Line "## 7. Handle Count"
Add-Line "**Handle totali di sistema: $totalHandles**"
Add-Line ""
Add-Line "| # | Processo | PID | Handles | RAM | Note |"
Add-Line "|---|---------|-----|---------|-----|------|"
$rank = 0
Get-Process | Sort-Object HandleCount -Descending | Select-Object -First 15 | ForEach-Object {
    $rank++
    $ramMB = [math]::Round($_.WorkingSet64 / 1MB, 0)
    $note = ""
    if ($_.HandleCount -gt 50000) { $note = "**POSSIBILE HANDLE LEAK**" }
    elseif ($_.HandleCount -gt 10000) { $note = "*Elevato*" }
    Add-Line "| $rank | $($_.Name) | $($_.Id) | $($_.HandleCount) | $ramMB MB | $note |"
}
Add-Line ""

# --- 8. SVCHOST SERVICES ---
Write-Progress-Section "Servizi in svchost"
Add-Line "## 8. Servizi in svchost con handle elevati (>2000)"
$allServices = $null
try { $allServices = Get-CimInstance Win32_Service -ErrorAction Stop } catch { $script:warningsCount++ }
if ($allServices) {
    Get-Process svchost -ErrorAction SilentlyContinue | Where-Object { $_.HandleCount -gt 2000 } | Sort-Object HandleCount -Descending | Select-Object -First 10 | ForEach-Object {
        $procId = $_.Id
        $handles = $_.HandleCount
        $ramMB = [math]::Round($_.WorkingSet64 / 1MB, 0)
        $svcNames = ($allServices | Where-Object { $_.ProcessId -eq $procId }).DisplayName -join ", "
        if (-not $svcNames) { $svcNames = "(non identificato)" }
        $flag = if ($handles -gt 50000) { " **HANDLE LEAK**" } else { "" }
        Add-Line "- **PID $procId** ($handles handles, $ramMB MB)$flag : $svcNames"
    }
    # Also flag non-svchost processes with very high handles
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "svchost" -and $_.HandleCount -gt 10000 } | Sort-Object HandleCount -Descending | ForEach-Object {
        $proc = $_
        $svcName = ($allServices | Where-Object { $_.ProcessId -eq $proc.Id }).DisplayName -join ", "
        if (-not $svcName) { $svcName = "(nessun servizio associato)" }
        Add-Line "- **$($proc.Name) PID $($proc.Id)** ($($proc.HandleCount) handles, $([math]::Round($proc.WorkingSet64/1MB,0)) MB) **ANOMALO** : Servizio: $svcName"
    }
} else {
    Add-Line "- (dati servizi non disponibili - accesso negato)"
}
Add-Line ""

# --- 9. DISK SPACE ANALYSIS ---
Write-Progress-Section "Analisi Spazio Disco"
Add-Line "## 9. Analisi Spazio Disco (drive sistema)"

$sysDrive = $env:SystemDrive
if ($DeepDiskScan) {
    Add-Line "### Cartelle root $sysDrive\"
    Add-Line "| Cartella | Dimensione |"
    Add-Line "|---------|-----------|"
    Get-ChildItem "${sysDrive}\" -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 } |
        ForEach-Object {
        $size = Get-FolderSize $_.FullName
        [PSCustomObject]@{ Folder = $_.FullName; Size = $size }
    } | Sort-Object Size -Descending | Select-Object -First 15 | Where-Object { $_.Size -gt 100MB } | ForEach-Object {
        Add-Line "| $($_.Folder) | $(Format-Size $_.Size) |"
    }
    Add-Line ""

    # User profile breakdown
    $userProfile = $env:USERPROFILE
    Add-Line "### Cartelle profilo utente ($userProfile)"
    Add-Line "| Cartella | Dimensione |"
    Add-Line "|---------|-----------|"
    Get-ChildItem $userProfile -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 } |
        ForEach-Object {
        $size = Get-FolderSize $_.FullName
        [PSCustomObject]@{ Folder = $_.Name; Size = $size }
    } | Sort-Object Size -Descending | Select-Object -First 15 | Where-Object { $_.Size -gt 50MB } | ForEach-Object {
        Add-Line "| $($_.Folder) | $(Format-Size $_.Size) |"
    }
    Add-Line ""
} else {
    Add-Line "*Scansione cartelle disabilitata (default). Usare -DeepDiskScan per analisi completa.*"
    Add-Line ""
}

# Temp, caches, reclaimable space (always run — fast, paths noti)
Add-Line "### Spazio potenzialmente recuperabile"
Add-Line "| Elemento | Dimensione |"
Add-Line "|---------|-----------|"

$reclaimable = @(
    @("Temp utente", "$env:TEMP"),
    @("Windows Temp", "$env:SystemRoot\Temp"),
    @("Windows Update Cache", "$env:SystemRoot\SoftwareDistribution\Download"),
    @("Chrome Cache", "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"),
    @("Chrome Code Cache", "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache"),
    @("Edge Cache", "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"),
    @("Firefox/TB Cache", "$env:LOCALAPPDATA\Thunderbird"),
    @("npm cache", "$env:LOCALAPPDATA\npm-cache"),
    @("pip cache", "$env:LOCALAPPDATA\pip\cache"),
    @("NuGet cache", "$env:LOCALAPPDATA\NuGet"),
    @("CrashDumps", "$env:LOCALAPPDATA\CrashDumps")
)
foreach ($item in $reclaimable) {
    $name = $item[0]
    $path = $item[1]
    if (Test-Path $path) {
        $size = Get-FolderSize $path
        if ($size -gt 10MB) {
            Add-Line "| $name | $(Format-Size $size) |"
        }
    }
}

# Recycle bin
try {
    $shell = New-Object -ComObject Shell.Application
    $rb = $shell.NameSpace(0x0a)
    $rbCount = $rb.Items().Count
    Add-Line "| Cestino | $rbCount elementi |"
} catch {}
Add-Line ""

# Large files
if ($DeepDiskScan) {
    Add-Line "### File grandi sul disco sistema (>500 MB)"
    Add-Line "| File | Dimensione |"
    Add-Line "|------|-----------|"
    Get-ChildItem "${sysDrive}\" -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt 500MB } |
        Sort-Object Length -Descending |
        Select-Object -First 15 |
        ForEach-Object {
            $shortPath = $_.FullName
            if ($shortPath.Length -gt 90) { $shortPath = $shortPath.Substring(0, 87) + "..." }
            Add-Line "| ``$shortPath`` | $(Format-Size $_.Length) |"
        }
    Add-Line ""
}


# --- 10. ICON OVERLAY HANDLERS ---
Write-Progress-Section "Overlay Handlers"
Add-Line "## 10. Shell Icon Overlay Handlers"
Add-Line "Windows supporta massimo ~11 overlay effettivi. Troppi overlay causano rallentamento di explorer.exe."
Add-Line ""
$overlayPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers"
$overlayCount = 0
if (Test-Path $overlayPath) {
    Add-Line "| Nome | CLSID |"
    Add-Line "|------|-------|"
    Get-ChildItem $overlayPath -ErrorAction SilentlyContinue | ForEach-Object {
        $overlayCount++
        $val = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).'(Default)'
        Add-Line "| $($_.PSChildName.Trim()) | $val |"
    }
}
$flag = if ($overlayCount -gt 11) { " **TROPPI - causa rallentamento explorer**" } else { "" }
Add-Line ""
Add-Line "**Totale overlay: $overlayCount**$flag"
Add-Line ""

# --- 11. EXPLORER NON-MS DLLS ---
Write-Progress-Section "Shell Extensions in Explorer"
Add-Line "## 11. DLL non-Microsoft caricate in explorer.exe"
$expProc = Get-Process explorer -ErrorAction SilentlyContinue | Select-Object -First 1
if ($expProc) {
    $cpuExp = if ($expProc.CPU) { [math]::Round($expProc.CPU, 1) } else { 0 }
    Add-Line "Explorer PID: $($expProc.Id) | CPU: $cpuExp s | RAM: $([math]::Round($expProc.WorkingSet64/1MB,0)) MB | Handles: $($expProc.HandleCount) | Threads: $($expProc.Threads.Count)"
    Add-Line ""
    $nonMsModules = $expProc.Modules | Where-Object {
        $_.FileName -notlike "C:\Windows\*" -and
        $_.FileName -notlike "C:\Windows\WinSxS\*"
    } | Sort-Object ModuleMemorySize -Descending | Select-Object -First 20
    if ($nonMsModules) {
        Add-Line "| DLL | Dimensione |"
        Add-Line "|-----|-----------|"
        foreach ($m in $nonMsModules) {
            Add-Line "| ``$($m.FileName)`` | $([math]::Round($m.ModuleMemorySize/1KB,0)) KB |"
        }
    } else {
        Add-Line "(nessuna DLL non-Microsoft trovata)"
    }
}
Add-Line ""

# --- 12. STARTUP PROGRAMS ---
Write-Progress-Section "Startup Programs"
Add-Line "## 12. Programmi in Avvio Automatico"

Add-Line "### HKCU\Run"
Add-Line "| Nome | Comando | Stato |"
Add-Line "|------|---------|-------|"
$hkcuRun = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$hkcuApproved = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
if (Test-Path $hkcuRun) {
    $props = Get-ItemProperty $hkcuRun
    $props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
        $name = $_.Name
        $cmd = $_.Value
        $status = "Enabled"
        if (Test-Path $hkcuApproved) {
            $approvedBytes = (Get-ItemProperty $hkcuApproved -Name $name -ErrorAction SilentlyContinue).$name
            if ($approvedBytes -is [byte[]] -and $approvedBytes[0] -ne 2) { $status = "**Disabled**" }
        }
        Add-Line "| $(Escape-TableCell $name) | ``$(Escape-TableCell $cmd)`` | $status |"
    }
}

Add-Line ""
Add-Line "### HKLM\Run"
Add-Line "| Nome | Comando | Stato |"
Add-Line "|------|---------|-------|"
$hklmRun = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$hklmApproved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
if (Test-Path $hklmRun) {
    $props = Get-ItemProperty $hklmRun
    $props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' -and $_.Name -ne '(default)' } | ForEach-Object {
        $name = $_.Name
        $cmd = $_.Value
        $status = "Enabled"
        if (Test-Path $hklmApproved) {
            $approvedBytes = (Get-ItemProperty $hklmApproved -Name $name -ErrorAction SilentlyContinue).$name
            if ($approvedBytes -is [byte[]] -and $approvedBytes[0] -ne 2) { $status = "**Disabled**" }
        }
        Add-Line "| $(Escape-TableCell $name) | ``$(Escape-TableCell $cmd)`` | $status |"
    }
}

Add-Line ""
Add-Line "### Cartella Startup"
$startupFolder = [Environment]::GetFolderPath('Startup')
Get-ChildItem $startupFolder -ErrorAction SilentlyContinue | ForEach-Object {
    Add-Line "- $($_.Name)"
}
Add-Line ""

# --- 13. SCHEDULED TASKS ---
Write-Progress-Section "Scheduled Tasks"
Add-Line "## 13. Scheduled Tasks (non-Microsoft, attivi)"
Add-Line "| Task | Percorso | Stato |"
Add-Line "|------|---------|-------|"
try {
    Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.State -eq 'Ready' -and $_.TaskPath -notlike '\Microsoft\*' } | ForEach-Object {
        Add-Line "| $($_.TaskName) | $($_.TaskPath) | $($_.State) |"
    }
} catch {
    Add-Line "| (dati non disponibili - accesso negato) | | |"
    $script:warningsCount++
}
Add-Line ""

# --- 14. SERVICES ---
Write-Progress-Section "Servizi Auto non Running"
Add-Line "## 14. Servizi Automatic non in esecuzione"
Add-Line "| Nome | Display Name | Stato |"
Add-Line "|------|-------------|-------|"
try {
    Get-Service -ErrorAction Stop | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' } | ForEach-Object {
        Add-Line "| $($_.Name) | $($_.DisplayName) | $($_.Status) |"
    }
} catch {
    Add-Line "| (dati non disponibili - accesso negato) | | |"
    $script:warningsCount++
}
Add-Line ""

# --- 15. DEFENDER ---
Write-Progress-Section "Windows Defender"
Add-Line "## 15. Windows Defender / Antivirus"
try {
    $defender = Get-MpComputerStatus -ErrorAction Stop
    Add-Line "| Proprieta' | Valore |"
    Add-Line "|-----------|--------|"
    Add-Line "| RealTime Protection | $($defender.RealTimeProtectionEnabled) |"
    Add-Line "| Antivirus Enabled | $($defender.AntivirusEnabled) |"
    Add-Line "| Antivirus Signature Age (giorni) | $($defender.AntivirusSignatureAge) |"
    Add-Line "| Last Quick Scan | $($defender.QuickScanEndTime) |"
    Add-Line "| Last Full Scan | $($defender.FullScanEndTime) |"
    Add-Line "| Tamper Protection | $($defender.IsTamperProtected) |"
} catch {
    Add-Line "(Impossibile leggere stato Defender - potrebbe richiedere elevazione)"
}
Add-Line ""

# --- 16. EVENT LOG ERRORS ---
Write-Progress-Section "Event Log Errori"
$since = (Get-Date).AddHours(-24)
Add-Line "## 16. Errori Event Log (ultime 24 ore)"

Add-Line "### Application Errors"
$appErrors = Get-WinEvent -FilterHashtable @{LogName='Application'; Level=2; StartTime=$since} -MaxEvents 15 -ErrorAction SilentlyContinue
if ($appErrors) {
    Add-Line "| Orario | Provider | Messaggio (estratto) |"
    Add-Line "|--------|----------|---------------------|"
    foreach ($evt in $appErrors) {
        $msg = $evt.Message
        if ($msg.Length -gt 120) { $msg = $msg.Substring(0, 117) + "..." }
        $msg = $msg -replace "`r`n", " " -replace "`n", " " -replace "\|", "/"
        Add-Line "| $($evt.TimeCreated) | $($evt.ProviderName) | $msg |"
    }
} else {
    Add-Line "(nessun errore applicativo nelle ultime 24 ore)"
}
Add-Line ""

Add-Line "### System Errors"
$sysErrors = Get-WinEvent -FilterHashtable @{LogName='System'; Level=2; StartTime=$since} -MaxEvents 15 -ErrorAction SilentlyContinue
if ($sysErrors) {
    Add-Line "| Orario | Provider | Messaggio (estratto) |"
    Add-Line "|--------|----------|---------------------|"
    foreach ($evt in $sysErrors) {
        $msg = $evt.Message
        if ($msg.Length -gt 120) { $msg = $msg.Substring(0, 117) + "..." }
        $msg = $msg -replace "`r`n", " " -replace "`n", " " -replace "\|", "/"
        Add-Line "| $($evt.TimeCreated) | $($evt.ProviderName) | $msg |"
    }
} else {
    Add-Line "(nessun errore di sistema nelle ultime 24 ore)"
}
Add-Line ""

# Warnings count
$appWarnings = (Get-WinEvent -FilterHashtable @{LogName='Application'; Level=3; StartTime=$since} -ErrorAction SilentlyContinue | Measure-Object).Count
$sysWarnings = (Get-WinEvent -FilterHashtable @{LogName='System'; Level=3; StartTime=$since} -ErrorAction SilentlyContinue | Measure-Object).Count
Add-Line "### Conteggio Warning (24h)"
Add-Line "- Application Warnings: $appWarnings"
Add-Line "- System Warnings: $sysWarnings"
Add-Line ""

# --- 17. POWER PLAN ---
Write-Progress-Section "Power Plan"
Add-Line "## 17. Piano Energetico"
$powerPlan = powercfg /getactivescheme 2>&1
Add-Line "``````"
Add-Line $powerPlan
Add-Line "``````"
Add-Line ""

# --- 18. NETWORK ---
Write-Progress-Section "Rete"
Add-Line "## 18. Rete"
Add-Line "### Interfacce attive"
try {
    Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
        Add-Line "- **$($_.Name)** ($($_.InterfaceDescription)) - Speed: $($_.LinkSpeed) - MAC: $($_.MacAddress)"
    }
} catch {
    Add-Line "- (dati non disponibili - accesso negato)"
    $script:warningsCount++
}
Add-Line ""

Add-Line "### DNS configurato"
try {
    Get-DnsClientServerAddress -ErrorAction Stop | Where-Object { $_.ServerAddresses -and $_.AddressFamily -eq 2 } | ForEach-Object {
        Add-Line "- $($_.InterfaceAlias): $($_.ServerAddresses -join ', ')"
    }
} catch {
    Add-Line "- (dati non disponibili - accesso negato)"
    $script:warningsCount++
}
Add-Line ""

# --- 19. NOTE ---
Write-Progress-Section "Note Finali"
Add-Line "## 19. Note e Raccomandazioni Automatiche"
Add-Line ""

# Auto-generated recommendations
$recommendations = @()

if ($pctRAM -ne "N/A" -and $pctRAM -gt 85) {
    $recommendations += "- **RAM al $pctRAM%**: il sistema e' sotto pressione di memoria. Valutare chiusura processi o upgrade RAM."
}
if ($commitGB -ne "N/A" -and $commitLimitGB -ne "N/A") {
    $commitPct = [math]::Round([double]$commitGB / [double]$commitLimitGB * 100, 0)
    if ($commitPct -gt 80) {
        $recommendations += "- **Commit charge al $commitPct%** ($commitGB / $commitLimitGB GB): vicino al limite. Rischio di out-of-memory."
    }
}

try {
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop | Where-Object { $_.Size -and $_.Size -gt 0 } | ForEach-Object {
        $usedPct = [math]::Round(($_.Size - $_.FreeSpace) / $_.Size * 100, 1)
        $freeGB = [math]::Round($_.FreeSpace / 1GB, 1)
        if ($usedPct -gt 90) {
            $recommendations += "- **Disco $($_.DeviceID) al $usedPct%** (solo $freeGB GB liberi): spazio critico. Liberare spazio urgentemente."
        }
    }
} catch {}

if ($overlayCount -gt 11) {
    $recommendations += "- **$overlayCount icon overlay handlers**: troppi (max 11 effettivi). Rallenta explorer.exe."
}

if ($totalHandles -gt 300000) {
    $recommendations += "- **Handle totali: $totalHandles** - valore elevato, possibili handle leak."
}

if ($os -and $os.LastBootUpTime) {
    $uptime = (Get-Date) - $os.LastBootUpTime
    if ($uptime.TotalDays -gt 7) {
        $recommendations += "- **Uptime > 7 giorni** ($([math]::Round($uptime.TotalDays,1)) giorni): consigliato un riavvio."
    }
}

$expCPU = (Get-Process explorer -ErrorAction SilentlyContinue).CPU
if ($expCPU -and $expCPU -gt 3600) {
    $recommendations += "- **Explorer.exe ha consumato $([math]::Round($expCPU/3600,1)) ore CPU**: anomalo. Controllare shell extensions e overlay handlers."
}

if ($recommendations.Count -gt 0) {
    $recommendations | ForEach-Object { Add-Line $_ }
} else {
    Add-Line "Nessuna anomalia critica rilevata automaticamente."
}

Add-Line ""
Add-Line "---"
Add-Line "*Report generato automaticamente. Sottoporre a Claude Code o altra AI per analisi dettagliata.*"

# --- SAVE ---
Write-Progress -Activity "Diagnosi Sistema" -Completed
try {
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    $report.ToString() | Out-File -FilePath $reportFile -Encoding UTF8 -ErrorAction Stop

    Write-Host ""
    Write-Host "============================================="
    if ($script:warningsCount -gt 0) {
        Write-Host "  DIAGNOSI COMPLETATA (con $($script:warningsCount) warning)" -ForegroundColor Yellow
        Write-Host "  Alcuni dati non disponibili (accesso negato)."
        Write-Host "  Per risultati completi, eseguire come Amministratore."
    } else {
        Write-Host "  DIAGNOSI COMPLETATA"
    }
    Write-Host "============================================="
    Write-Host "  Report salvato in: $reportFile"
    Write-Host "  Dimensione: $([math]::Round((Get-Item $reportFile).Length/1KB,0)) KB"
    Write-Host "============================================="
    Write-Host ""
    if ($script:warningsCount -gt 0) { exit 2 }
} catch {
    Write-Host ""
    Write-Host "  [ERRORE] Impossibile scrivere il report: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Path tentato: $reportFile" -ForegroundColor Red
    exit 1
}
