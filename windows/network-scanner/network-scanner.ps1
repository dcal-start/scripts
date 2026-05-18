<#
.SYNOPSIS
    network-scanner - LAN/subnet discovery with MAC/vendor lookup, inventory, comparison and HTML/CSV/JSON export.

.DESCRIPTION
    Standalone PowerShell IPv4 network scanner.
    - Fast ICMP sweep using runspace pool.
    - Optional TCP probe for hosts blocking ICMP.
    - MAC retrieval from local ARP / neighbor cache.
    - Vendor lookup from local OUI CSV database.
    - Optional IEEE OUI database update with -UpdateOui.
    - Optional DNS reverse and optional NetBIOS name lookup.
    - JSON config and persistent state under a data directory.
    - HTML, CSV and JSON export.
    - Scan profiles: Fast, Standard, Deep.
    - Optional comparison with previous scan.
    - Persistent device inventory.

.NOTES
    Designed for Windows PowerShell 5.1+ and PowerShell 7+.
    Real MAC addresses are normally available only for hosts in the same Layer-2 segment.
#>

[CmdletBinding()]
param(
    [string]$Subnet,

    [switch]$TcpProbe,

    [switch]$NoTcpProbe,

    [switch]$ResolveDns,

    [switch]$NoDns,

    [switch]$NetBios,

    [switch]$NoNetBios,

    [switch]$ExportHtml,

    [switch]$NoExportHtml,

    [switch]$ExportCsv,

    [switch]$ExportJson,

    [switch]$UpdateOui,

    [int]$PingTimeoutMs,

    [int]$TcpTimeoutMs,

    [int[]]$TcpPorts,

    [int]$MaxThreads,

    [ValidateSet('Fast', 'Standard', 'Deep')]
    [string]$Profile = 'Standard',

    [switch]$TcpScanAllPorts,

    [switch]$Compare,

    [switch]$NoInventory,

    [switch]$Version,

    [string]$DataPath,

    [string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Script:NetworkScannerVersion = '1.0.0'
$Script:ToolName = 'network-scanner'

if ($Version) {
    Write-Output "$($Script:ToolName) $($Script:NetworkScannerVersion)"
    return
}

# ------------------------------------------------------------
# Local paths
# ------------------------------------------------------------

$ScriptFile = $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ScriptFile)) {
    $ScriptRoot = (Get-Location).Path
}
else {
    $ScriptRoot = Split-Path -Parent $ScriptFile
}

if ([string]::IsNullOrWhiteSpace($DataPath)) {
    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        $localAppData = $ScriptRoot
    }
    $DataPath = Join-Path $localAppData $Script:ToolName
}

$DatabaseDir = Join-Path $DataPath 'database'
$ReportDir = if ([string]::IsNullOrWhiteSpace($OutputPath)) { Join-Path $DataPath 'reports' } else { $OutputPath }
$StateDir = Join-Path $DataPath 'state'
$ConfigPath = Join-Path $DataPath 'network-scanner.config.json'
$OuiPath = Join-Path $DatabaseDir 'oui.csv'
$InventoryPath = Join-Path $StateDir 'inventory.json'
$PreviousScanPath = Join-Path $StateDir 'latest-scan.json'

foreach ($dirPath in @($DataPath, $DatabaseDir, $ReportDir, $StateDir)) {
    if (-not (Test-Path -LiteralPath $dirPath)) {
        New-Item -Path $dirPath -ItemType Directory -Force | Out-Null
    }
}

# ------------------------------------------------------------
# Default configuration
# ------------------------------------------------------------

$DefaultConfig = [ordered]@{
    LastSubnet             = '192.168.1.0/24'
    PingTimeoutMs          = 250
    TcpTimeoutMs           = 180
    MaxThreads             = 256
    TcpProbeEnabledDefault = $false
    TcpProbePorts          = @(80, 443, 445, 3389, 22, 23, 135, 139, 8080, 8443, 5900, 8006)
    DeepTcpProbePorts      = @(21, 22, 23, 25, 53, 80, 110, 135, 139, 143, 161, 389, 443, 445, 515, 631, 993, 995, 1433, 1521, 3306, 3389, 5432, 5900, 5985, 5986, 8006, 8080, 8443, 9100)
    ResolveDnsDefault      = $true
    NetBiosDefault         = $false
    ExportHtmlDefault      = $true
    ExportCsvDefault       = $false
    ExportJsonDefault      = $false
    CreateSampleOuiCsv     = $true
    OuiDownloadUrl         = 'https://standards-oui.ieee.org/oui/oui.csv'
}

function Save-ScannerConfig {
    param([Parameter(Mandatory)][object]$Config)

    $Config |
        ConvertTo-Json -Depth 8 |
        Set-Content -Path $ConfigPath -Encoding UTF8
}

function Load-ScannerConfig {
    if (-not (Test-Path $ConfigPath)) {
        Save-ScannerConfig -Config $DefaultConfig
        return [pscustomobject]$DefaultConfig
    }

    try {
        $cfg = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($key in $DefaultConfig.Keys) {
            if (-not ($cfg.PSObject.Properties.Name -contains $key)) {
                $cfg | Add-Member -MemberType NoteProperty -Name $key -Value $DefaultConfig[$key]
            }
        }
        return $cfg
    }
    catch {
        $backupPath = "$ConfigPath.broken_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item -Path $ConfigPath -Destination $backupPath -Force -ErrorAction SilentlyContinue
        Save-ScannerConfig -Config $DefaultConfig
        return [pscustomobject]$DefaultConfig
    }
}

function Ensure-SampleOuiCsv {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path $Path) {
        return
    }

    $sample = @'
Prefix,Vendor
00-15-5D,Microsoft Corporation / Hyper-V
00-1C-42,Parallels
00-50-56,VMware
00-0C-29,VMware
00-05-69,VMware
08-00-27,Oracle VirtualBox
BC-24-11,Proxmox / QEMU
52-54-00,QEMU / KVM
C0-47-0E,Ubiquiti Inc.
74-BF-C0,CANON INC.
24-5E-BE,QNAP Systems Inc.
00-11-32,Synology Incorporated
90-09-D0,Synology Incorporated
00-08-9B,ICP Electronics / QNAP-related devices
E0-23-FF,Fortinet Inc.
70-4C-A5,Fortinet Inc.
D8-94-03,Hewlett Packard Enterprise
B4-FB-E4,Ubiquiti Inc.
F4-A9-97,Canon Inc.
10-98-36,Dell Inc.
48-3A-02,Dell Inc.
74-AC-B9,Dell Inc.
70-49-A2,Dell Inc.
'@

    $sample | Set-Content -Path $Path -Encoding UTF8
}


function Format-OuiPrefix {
    param([Parameter(Mandatory)][string]$Assignment)

    $hex = ($Assignment -replace '[^0-9A-Fa-f]', '').ToUpper()

    if ($hex.Length -lt 6) {
        return $null
    }

    $hex = $hex.Substring(0, 6)
    return ($hex.Substring(0, 2) + '-' + $hex.Substring(2, 2) + '-' + $hex.Substring(4, 2))
}

function Update-OuiDatabase {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Url
    )

    $tmpPath = Join-Path ([System.IO.Path]::GetTempPath()) ("ieee_oui_{0}.csv" -f ([guid]::NewGuid().ToString('N')))

    try {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        }
        catch {}

        Write-Host "Downloading IEEE OUI CSV..." -ForegroundColor Cyan
        Write-Host "Source         : $Url"

        $headers = @{ 'User-Agent' = 'Mozilla/5.0 network-scanner PowerShell OUI updater' }
        Invoke-WebRequest -Uri $Url -OutFile $tmpPath -UseBasicParsing -Headers $headers -ErrorAction Stop

        $rows = Import-Csv -Path $tmpPath
        $map = @{}

        foreach ($row in $rows) {
            $assignment = $null
            $vendor = $null

            if ($row.PSObject.Properties.Name -contains 'Assignment') {
                $assignment = [string]$row.Assignment
            }

            if ($row.PSObject.Properties.Name -contains 'Organization Name') {
                $vendor = [string]$row.'Organization Name'
            }
            elseif ($row.PSObject.Properties.Name -contains 'OrganizationName') {
                $vendor = [string]$row.OrganizationName
            }

            if ([string]::IsNullOrWhiteSpace($assignment) -or [string]::IsNullOrWhiteSpace($vendor)) {
                continue
            }

            $prefix = Format-OuiPrefix -Assignment $assignment
            if ([string]::IsNullOrWhiteSpace($prefix)) {
                continue
            }

            # If IEEE contains duplicates, keep the first observed mapping.
            if (-not $map.ContainsKey($prefix)) {
                $map[$prefix] = $vendor.Trim() -replace '[\r\n]+', ' '
            }
        }

        if ($map.Count -lt 10000) {
            throw "Downloaded OUI database seems too small or malformed. Parsed entries: $($map.Count)."
        }

        if (Test-Path $Path) {
            $backupPath = "$Path.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Copy-Item -Path $Path -Destination $backupPath -Force
            Write-Host "Backup         : $backupPath"
        }

        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('Prefix,Vendor') | Out-Null

        foreach ($prefix in ($map.Keys | Sort-Object)) {
            $vendor = $map[$prefix]
            # Quote only if needed. Double internal quotes per CSV rules.
            if ($vendor -match '[,\"]') {
                $vendor = '"' + ($vendor -replace '"', '""') + '"'
            }
            $lines.Add("$prefix,$vendor") | Out-Null
        }

        $lines | Set-Content -Path $Path -Encoding UTF8

        Write-Host "Updated        : $Path" -ForegroundColor Green
        Write-Host "Entries        : $($map.Count)"
        return $map.Count
    }
    finally {
        if (Test-Path $tmpPath) {
            Remove-Item -Path $tmpPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# ------------------------------------------------------------
# IPv4 / CIDR helpers - safe for Windows PowerShell 5.1
# ------------------------------------------------------------

function ConvertTo-UInt32Ip {
    param([Parameter(Mandatory)][string]$IpAddress)

    $bytes = [System.Net.IPAddress]::Parse($IpAddress).GetAddressBytes()
    [Array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function ConvertFrom-UInt32Ip {
    param([Parameter(Mandatory)][uint32]$UInt32)

    $bytes = [BitConverter]::GetBytes($UInt32)
    [Array]::Reverse($bytes)
    return ([System.Net.IPAddress]::new($bytes)).ToString()
}

function Get-IpRangeFromCidr {
    param([Parameter(Mandatory)][string]$Cidr)

    if ($Cidr -notmatch '^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$') {
        throw "Invalid subnet format. Use CIDR notation, example: 192.168.1.0/24"
    }

    $parts = $Cidr.Split('/')
    $baseIp = $parts[0]
    $prefix = [int]$parts[1]

    if ($prefix -lt 1 -or $prefix -gt 32) {
        throw "Invalid CIDR prefix: /$prefix"
    }

    $octets = $baseIp.Split('.') | ForEach-Object { [int]$_ }
    foreach ($o in $octets) {
        if ($o -lt 0 -or $o -gt 255) {
            throw "Invalid IPv4 address: $baseIp"
        }
    }

    $base = [uint32](ConvertTo-UInt32Ip $baseIp)

    if ($prefix -eq 32) {
        return ,(ConvertFrom-UInt32Ip $base)
    }

    $addressCount = [uint64]1 -shl (32 - $prefix)
    $mask64 = ([uint64]4294967295) -bxor ($addressCount - 1)
    $network64 = ([uint64]$base) -band $mask64
    $broadcast64 = $network64 + $addressCount - 1

    if ($prefix -eq 31) {
        $first = $network64
        $last = $broadcast64
    }
    else {
        $first = $network64 + 1
        $last = $broadcast64 - 1
    }

    $ips = New-Object System.Collections.Generic.List[string]
    for ($current = $first; $current -le $last; $current++) {
        $ips.Add((ConvertFrom-UInt32Ip ([uint32]$current)))
    }

    return $ips
}

function Sort-ByIpAddress {
    param([Parameter(ValueFromPipeline)][object]$InputObject)
    process {
        $InputObject | Add-Member -NotePropertyName __SortIp -NotePropertyValue (ConvertTo-UInt32Ip $InputObject.IP) -Force
        $InputObject
    }
}

# ------------------------------------------------------------
# Fast ICMP sweep
# ------------------------------------------------------------

function Invoke-PingSweepFast {
    param(
        [Parameter(Mandatory)][string[]]$IpList,
        [int]$TimeoutMs = 250,
        [int]$Threads = 256
    )

    $results = New-Object System.Collections.Generic.List[object]
    $pool = [runspacefactory]::CreateRunspacePool(1, $Threads)
    $pool.Open()

    $jobs = New-Object System.Collections.Generic.List[object]

    foreach ($ip in $IpList) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool

        [void]$ps.AddScript({
            param($TargetIp, $Timeout)

            $ping = New-Object System.Net.NetworkInformation.Ping
            try {
                $reply = $ping.Send($TargetIp, $Timeout)
                if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    [pscustomobject]@{
                        IP          = $TargetIp
                        AliveByPing = $true
                        PingMs      = [int]$reply.RoundtripTime
                    }
                }
            }
            catch {
                $null
            }
            finally {
                $ping.Dispose()
            }
        })

        [void]$ps.AddArgument($ip)
        [void]$ps.AddArgument($TimeoutMs)

        $handle = $ps.BeginInvoke()
        [void]$jobs.Add([pscustomobject]@{
            PowerShell = $ps
            Handle     = $handle
        })
    }

    foreach ($job in $jobs) {
        try {
            $output = $job.PowerShell.EndInvoke($job.Handle)
            foreach ($item in $output) {
                if ($null -ne $item) {
                    [void]$results.Add($item)
                }
            }
        }
        finally {
            $job.PowerShell.Dispose()
        }
    }

    $pool.Close()
    $pool.Dispose()

    return $results.ToArray()
}

# ------------------------------------------------------------
# Optional TCP probe
# ------------------------------------------------------------

function Invoke-TcpProbeSweepFast {
    param(
        [Parameter(Mandatory)][string[]]$IpList,
        [Parameter(Mandatory)][int[]]$Ports,
        [int]$TimeoutMs = 180,
        [int]$Threads = 256,
        [bool]$ScanAllPorts = $false
    )

    $results = New-Object System.Collections.Generic.List[object]
    $pool = [runspacefactory]::CreateRunspacePool(1, $Threads)
    $pool.Open()

    $jobs = New-Object System.Collections.Generic.List[object]

    foreach ($ip in $IpList) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool

        [void]$ps.AddScript({
            param($TargetIp, $TargetPorts, $Timeout, $ScanAllPorts)

            $openPorts = New-Object System.Collections.Generic.List[int]

            foreach ($port in $TargetPorts) {
                $client = New-Object System.Net.Sockets.TcpClient
                try {
                    $iar = $client.BeginConnect($TargetIp, [int]$port, $null, $null)
                    $success = $iar.AsyncWaitHandle.WaitOne($Timeout, $false)
                    if ($success) {
                        try {
                            $client.EndConnect($iar)
                            [void]$openPorts.Add([int]$port)
                        }
                        catch {}
                    }
                }
                catch {}
                finally {
                    $client.Close()
                    $client.Dispose()
                }

                # For speed, default mode stops after the first open port. Deep mode can scan all configured ports.
                if (-not $ScanAllPorts -and $openPorts.Count -gt 0) {
                    break
                }
            }

            if ($openPorts.Count -gt 0) {
                [pscustomobject]@{
                    IP         = $TargetIp
                    AliveByTcp = $true
                    OpenPorts  = ($openPorts -join ',')
                }
            }
        })

        [void]$ps.AddArgument($ip)
        [void]$ps.AddArgument($Ports)
        [void]$ps.AddArgument($TimeoutMs)
        [void]$ps.AddArgument($ScanAllPorts)

        $handle = $ps.BeginInvoke()
        [void]$jobs.Add([pscustomobject]@{
            PowerShell = $ps
            Handle     = $handle
        })
    }

    foreach ($job in $jobs) {
        try {
            $output = $job.PowerShell.EndInvoke($job.Handle)
            foreach ($item in $output) {
                if ($null -ne $item) {
                    [void]$results.Add($item)
                }
            }
        }
        finally {
            $job.PowerShell.Dispose()
        }
    }

    $pool.Close()
    $pool.Dispose()

    return $results.ToArray()
}

# ------------------------------------------------------------
# ARP / neighbor cache
# ------------------------------------------------------------

function Get-MacCache {
    $map = @{}

    try {
        if (Get-Command Get-NetNeighbor -ErrorAction SilentlyContinue) {
            $neighbors = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.IPAddress -and
                    $_.LinkLayerAddress -and
                    $_.LinkLayerAddress -notin @('00-00-00-00-00-00', 'FF-FF-FF-FF-FF-FF', 'ff-ff-ff-ff-ff-ff') -and
                    $_.State -notin @('Unreachable', 'Incomplete')
                }

            foreach ($n in $neighbors) {
                $map[[string]$n.IPAddress] = ([string]$n.LinkLayerAddress).ToUpper().Replace(':', '-')
            }
        }
    }
    catch {}

    try {
        $arpOutput = arp -a 2>$null
        foreach ($line in $arpOutput) {
            if ($line -match '^\s*(\d{1,3}(?:\.\d{1,3}){3})\s+([0-9a-fA-F:-]{17})\s+') {
                $ip = $matches[1]
                $mac = $matches[2].ToUpper().Replace(':', '-')
                if (-not $map.ContainsKey($ip)) {
                    $map[$ip] = $mac
                }
            }
        }
    }
    catch {}

    return $map
}

# ------------------------------------------------------------
# OUI / vendor lookup
# ------------------------------------------------------------

function Load-OuiDatabase {
    param([Parameter(Mandatory)][string]$Path)

    $map = @{}

    if (-not (Test-Path $Path)) {
        return $map
    }

    try {
        $rows = Import-Csv -Path $Path
        foreach ($row in $rows) {
            if ($row.Prefix -and $row.Vendor) {
                $prefix = ([string]$row.Prefix).Trim().ToUpper().Replace(':', '-')
                if ($prefix.Length -ge 8) {
                    $prefix = $prefix.Substring(0, 8)
                    $map[$prefix] = ([string]$row.Vendor).Trim()
                }
            }
        }
    }
    catch {}

    return $map
}

function Get-VendorFromMac {
    param(
        [string]$Mac,
        [hashtable]$OuiMap
    )

    if ([string]::IsNullOrWhiteSpace($Mac)) {
        return $null
    }

    $normalized = $Mac.Trim().ToUpper().Replace(':', '-')
    if ($normalized.Length -lt 8) {
        return $null
    }

    $prefix = $normalized.Substring(0, 8)

    if ($OuiMap.ContainsKey($prefix)) {
        return $OuiMap[$prefix]
    }

    return $null
}

# ------------------------------------------------------------
# Optional name discovery
# ------------------------------------------------------------

function Resolve-HostNameSafe {
    param([Parameter(Mandatory)][string]$Ip)

    try {
        return ([System.Net.Dns]::GetHostEntry($Ip)).HostName
    }
    catch {
        return $null
    }
}

function Resolve-NetBiosNameSafe {
    param([Parameter(Mandatory)][string]$Ip)

    try {
        $output = nbtstat -A $Ip 2>$null
        foreach ($line in $output) {
            # Typical line: NAME            <00>  UNIQUE      Registered
            if ($line -match '^\s*([^\s<]{1,15})\s+<00>\s+UNIQUE\s+Registered') {
                $name = $matches[1].Trim()
                if ($name -and $name -ne '__MSBROWSE__') {
                    return $name
                }
            }
        }
    }
    catch {}

    return $null
}

function Resolve-NetBiosNamesFast {
    param(
        [Parameter(Mandatory)][string[]]$IpList,
        [int]$Threads = 64
    )

    $map = @{}
    if ($IpList.Count -eq 0) {
        return $map
    }

    $pool = [runspacefactory]::CreateRunspacePool(1, $Threads)
    $pool.Open()
    $jobs = New-Object System.Collections.Generic.List[object]

    foreach ($ip in $IpList) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool

        [void]$ps.AddScript({
            param($TargetIp)
            try {
                $output = nbtstat -A $TargetIp 2>$null
                foreach ($line in $output) {
                    if ($line -match '^\s*([^\s<]{1,15})\s+<00>\s+UNIQUE\s+Registered') {
                        $name = $matches[1].Trim()
                        if ($name -and $name -ne '__MSBROWSE__') {
                            return [pscustomobject]@{ IP = $TargetIp; Name = $name }
                        }
                    }
                }
            }
            catch {}
            return $null
        })

        [void]$ps.AddArgument($ip)
        $handle = $ps.BeginInvoke()
        [void]$jobs.Add([pscustomobject]@{ PowerShell = $ps; Handle = $handle })
    }

    foreach ($job in $jobs) {
        try {
            $output = $job.PowerShell.EndInvoke($job.Handle)
            foreach ($item in $output) {
                if ($null -ne $item -and $item.IP -and $item.Name) {
                    $map[[string]$item.IP] = [string]$item.Name
                }
            }
        }
        finally {
            $job.PowerShell.Dispose()
        }
    }

    $pool.Close()
    $pool.Dispose()

    return $map
}

function Resolve-DnsNamesFast {
    param(
        [Parameter(Mandatory)][string[]]$IpList,
        [int]$Threads = 64
    )

    $map = @{}
    if ($IpList.Count -eq 0) {
        return $map
    }

    $pool = [runspacefactory]::CreateRunspacePool(1, $Threads)
    $pool.Open()
    $jobs = New-Object System.Collections.Generic.List[object]

    foreach ($ip in $IpList) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool

        [void]$ps.AddScript({
            param($TargetIp)
            try {
                $name = ([System.Net.Dns]::GetHostEntry($TargetIp)).HostName
                if ($name) {
                    return [pscustomobject]@{ IP = $TargetIp; Name = $name }
                }
            }
            catch {}
            return $null
        })

        [void]$ps.AddArgument($ip)
        $handle = $ps.BeginInvoke()
        [void]$jobs.Add([pscustomobject]@{ PowerShell = $ps; Handle = $handle })
    }

    foreach ($job in $jobs) {
        try {
            $output = $job.PowerShell.EndInvoke($job.Handle)
            foreach ($item in $output) {
                if ($null -ne $item -and $item.IP -and $item.Name) {
                    $map[[string]$item.IP] = [string]$item.Name
                }
            }
        }
        finally {
            $job.PowerShell.Dispose()
        }
    }

    $pool.Close()
    $pool.Dispose()

    return $map
}

# ------------------------------------------------------------
# Export helpers
# ------------------------------------------------------------

function HtmlEncodeSafe {
    param([object]$Value)

    if ($null -eq $Value) {
        return ''
    }

    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Export-ScanHtml {
    param(
        [Parameter(Mandatory)][object[]]$Results,
        [Parameter(Mandatory)][string]$Subnet,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][double]$ElapsedSeconds,
        [object[]]$RemovedResults = @()
    )

    $generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $rows = foreach ($r in $Results) {
        $ipHtml       = HtmlEncodeSafe $r.IP
        $macHtml      = HtmlEncodeSafe $r.MAC
        $vendorHtml   = HtmlEncodeSafe $r.Vendor
        $nameHtml     = HtmlEncodeSafe $r.Name
        $nameSrcHtml  = HtmlEncodeSafe $r.NameSource
        $methodHtml   = HtmlEncodeSafe $r.DetectedBy
        $pingHtml     = HtmlEncodeSafe $r.PingMs
        $portsHtml    = HtmlEncodeSafe $r.OpenPorts
        $statusHtml   = 'online'
        $changeHtml   = HtmlEncodeSafe $r.ChangeStatus

        "<tr class=`"online`"><td>$ipHtml</td><td>$macHtml</td><td>$vendorHtml</td><td>$nameHtml</td><td>$nameSrcHtml</td><td>$methodHtml</td><td>$pingHtml</td><td>$portsHtml</td><td>$statusHtml</td><td>$changeHtml</td></tr>"
    }

    $removedRows = foreach ($r in $RemovedResults) {
        $ipHtml       = HtmlEncodeSafe $r.IP
        $macHtml      = HtmlEncodeSafe $r.MAC
        $vendorHtml   = HtmlEncodeSafe $r.Vendor
        $nameHtml     = HtmlEncodeSafe $r.Name
        $nameSrcHtml  = HtmlEncodeSafe $r.NameSource
        $methodHtml   = HtmlEncodeSafe $r.DetectedBy
        $pingHtml     = HtmlEncodeSafe $r.PingMs
        $portsHtml    = HtmlEncodeSafe $r.OpenPorts
        $statusHtml   = 'offline'
        $changeHtml   = HtmlEncodeSafe $r.ChangeStatus

        "<tr class=`"offline`"><td>$ipHtml</td><td>$macHtml</td><td>$vendorHtml</td><td>$nameHtml</td><td>$nameSrcHtml</td><td>$methodHtml</td><td>$pingHtml</td><td>$portsHtml</td><td>$statusHtml</td><td>$changeHtml</td></tr>"
    }

    $subnetHtml = HtmlEncodeSafe $Subnet
    $generatedHtml = HtmlEncodeSafe $generated
    $elapsedHtml = HtmlEncodeSafe ([math]::Round($ElapsedSeconds, 2))
    $countHtml = HtmlEncodeSafe $Results.Count

    $html = @"
<!DOCTYPE html>
<html lang="it">
<head>
<meta charset="utf-8">
<title>network-scanner - $subnetHtml</title>
<style>
body {
    font-family: Segoe UI, Arial, sans-serif;
    margin: 24px;
    background: #f5f5f5;
    color: #222;
}
h1 { margin-bottom: 4px; }
.meta { color: #555; margin-bottom: 18px; line-height: 1.5; }
.toolbar { display: flex; gap: 16px; align-items: center; margin: 14px 0; flex-wrap: wrap; }
.toolbar input[type="search"] { min-width: 280px; padding: 7px 9px; border: 1px solid #bbb; font-size: 13px; }
.toolbar label { font-size: 13px; color: #333; }
.table-wrap { overflow-x: auto; background: white; border: 1px solid #ddd; }
table { border-collapse: collapse; width: 100%; min-width: 1180px; background: white; table-layout: fixed; }
th, td { border: 1px solid #ddd; padding: 8px 10px; font-size: 13px; overflow-wrap: anywhere; vertical-align: top; }
th { background: #222; color: white; text-align: left; position: sticky; top: 0; user-select: none; }
th.sortable { cursor: pointer; }
th.sortable::after { content: ' ⇅'; color: #aaa; font-size: 11px; }
th.sort-asc::after { content: ' ↑'; color: #fff; }
th.sort-desc::after { content: ' ↓'; color: #fff; }
th .resizer { position: absolute; right: 0; top: 0; width: 6px; height: 100%; cursor: col-resize; user-select: none; }
tr:nth-child(even) { background: #f2f2f2; }
tr.offline { background: #fff1f2; color: #7f1d1d; }
tr.offline:nth-child(even) { background: #ffe4e6; }
tr.offline td { border-color: #fecdd3; }
.summary { margin: 14px 0; font-weight: 600; }
</style>
</head>
<body>
<h1>network-scanner</h1>
<div class="meta">
Subnet: $subnetHtml<br>
Generated: $generatedHtml<br>
Elapsed: $elapsedHtml seconds
</div>
<div class="summary">Hosts detected: $countHtml</div>
<div class="toolbar">
<input id="tableSearch" type="search" placeholder="Search...">
<label><input id="showOffline" type="checkbox" checked> Show offline</label>
</div>
<div class="table-wrap">
<table id="scanTable">
<colgroup>
<col style="width: 120px">
<col style="width: 150px">
<col style="width: 220px">
<col style="width: 240px">
<col style="width: 90px">
<col style="width: 100px">
<col style="width: 80px">
<col style="width: 190px">
<col style="width: 80px">
<col style="width: 130px">
</colgroup>
<thead>
<tr>
<th class="sortable" data-type="ip">IP</th>
<th class="sortable">MAC Address</th>
<th class="sortable">Vendor</th>
<th class="sortable">Name</th>
<th class="sortable">Name Source</th>
<th class="sortable">Detected By</th>
<th class="sortable" data-type="number">Ping ms</th>
<th class="sortable">Open TCP Ports</th>
<th class="sortable">Status</th>
<th class="sortable">Change</th>
</tr>
</thead>
<tbody>
$($rows -join "`r`n")
$($removedRows -join "`r`n")
</tbody>
</table>
</div>
<script>
(function () {
    const table = document.getElementById('scanTable');
    const tbody = table.tBodies[0];
    const search = document.getElementById('tableSearch');
    const showOffline = document.getElementById('showOffline');

    function ipValue(text) {
        const parts = text.trim().split('.').map(Number);
        if (parts.length !== 4 || parts.some(n => Number.isNaN(n))) return text.toLowerCase();
        return (((parts[0] * 256 + parts[1]) * 256 + parts[2]) * 256 + parts[3]);
    }

    function cellValue(row, index, type) {
        const text = row.cells[index].textContent.trim();
        if (type === 'number') return text === '' ? -1 : Number(text);
        if (type === 'ip') return ipValue(text);
        return text.toLowerCase();
    }

    function applyFilters() {
        const term = search.value.trim().toLowerCase();
        const offlineVisible = showOffline.checked;
        Array.from(tbody.rows).forEach(row => {
            const matchesSearch = term === '' || row.textContent.toLowerCase().includes(term);
            const matchesStatus = offlineVisible || !row.classList.contains('offline');
            row.style.display = matchesSearch && matchesStatus ? '' : 'none';
        });
    }

    table.querySelectorAll('th.sortable').forEach((th, index) => {
        th.addEventListener('click', event => {
            if (event.target.classList.contains('resizer')) return;
            const current = th.classList.contains('sort-asc') ? 'asc' : (th.classList.contains('sort-desc') ? 'desc' : '');
            const next = current === 'asc' ? 'desc' : 'asc';
            table.querySelectorAll('th').forEach(header => header.classList.remove('sort-asc', 'sort-desc'));
            th.classList.add(next === 'asc' ? 'sort-asc' : 'sort-desc');
            const type = th.dataset.type || 'text';
            const rows = Array.from(tbody.rows);
            rows.sort((a, b) => {
                const av = cellValue(a, index, type);
                const bv = cellValue(b, index, type);
                if (av < bv) return next === 'asc' ? -1 : 1;
                if (av > bv) return next === 'asc' ? 1 : -1;
                return 0;
            });
            rows.forEach(row => tbody.appendChild(row));
            applyFilters();
        });
    });

    table.querySelectorAll('th').forEach((th, index) => {
        const resizer = document.createElement('span');
        resizer.className = 'resizer';
        th.appendChild(resizer);
        resizer.addEventListener('mousedown', event => {
            event.preventDefault();
            event.stopPropagation();
            const startX = event.clientX;
            const col = table.querySelectorAll('col')[index];
            const startWidth = col.getBoundingClientRect().width;
            function onMove(moveEvent) {
                const width = Math.max(50, startWidth + moveEvent.clientX - startX);
                col.style.width = width + 'px';
            }
            function onUp() {
                document.removeEventListener('mousemove', onMove);
                document.removeEventListener('mouseup', onUp);
            }
            document.addEventListener('mousemove', onMove);
            document.addEventListener('mouseup', onUp);
        });
    });

    search.addEventListener('input', applyFilters);
    showOffline.addEventListener('change', applyFilters);
    applyFilters();
})();
</script>
</body>
</html>
"@

    $html | Set-Content -Path $OutputPath -Encoding UTF8
}

function Load-JsonArrayFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    try {
        $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $data) { return @() }
        return @($data)
    }
    catch {
        return @()
    }
}

function Compare-ScanResults {
    param(
        [Parameter(Mandatory)][object[]]$Current,
        [AllowEmptyCollection()][object[]]$Previous = @()
    )

    $previousByKey = @{}
    foreach ($item in $Previous) {
        $key = if ($item.MAC) { "MAC:$($item.MAC)" } else { "IP:$($item.IP)" }
        if (-not $previousByKey.ContainsKey($key)) {
            $previousByKey[$key] = $item
        }
    }

    $currentKeys = @{}
    foreach ($item in $Current) {
        $key = if ($item.MAC) { "MAC:$($item.MAC)" } else { "IP:$($item.IP)" }
        $currentKeys[$key] = $true

        if (-not $previousByKey.ContainsKey($key)) {
            $item | Add-Member -NotePropertyName ChangeStatus -NotePropertyValue 'Added' -Force
            continue
        }

        $old = $previousByKey[$key]
        $changedFields = New-Object System.Collections.Generic.List[string]
        foreach ($field in @('IP', 'MAC', 'Vendor', 'Name', 'DetectedBy', 'OpenPorts')) {
            if ([string]$item.$field -ne [string]$old.$field) {
                $changedFields.Add($field) | Out-Null
            }
        }

        if ($changedFields.Count -gt 0) {
            $item | Add-Member -NotePropertyName ChangeStatus -NotePropertyValue ('Changed: ' + ($changedFields -join ',')) -Force
        }
        else {
            $item | Add-Member -NotePropertyName ChangeStatus -NotePropertyValue 'Unchanged' -Force
        }
    }

    $removed = New-Object System.Collections.Generic.List[object]
    foreach ($key in $previousByKey.Keys) {
        if (-not $currentKeys.ContainsKey($key)) {
            $old = $previousByKey[$key]
            $old | Add-Member -NotePropertyName ChangeStatus -NotePropertyValue 'Removed' -Force
            $removed.Add($old) | Out-Null
        }
    }

    return [pscustomobject]@{ Current = $Current; Removed = $removed.ToArray() }
}

function Save-DeviceInventory {
    param(
        [Parameter(Mandatory)][object[]]$Results,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$SubnetValue
    )

    $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $inventory = @{}

    foreach ($item in (Load-JsonArrayFile -Path $Path)) {
        $key = if ($item.MAC) { "MAC:$($item.MAC)" } else { "IP:$($item.LastIP)" }
        if (-not [string]::IsNullOrWhiteSpace($key) -and -not $inventory.ContainsKey($key)) {
            $inventory[$key] = $item
        }
    }

    foreach ($item in $Results) {
        $key = if ($item.MAC) { "MAC:$($item.MAC)" } else { "IP:$($item.IP)" }
        if ($inventory.ContainsKey($key)) {
            $record = $inventory[$key]
            $record.LastSeen = $now
            $record.LastIP = $item.IP
            $record.MAC = $item.MAC
            $record.Vendor = $item.Vendor
            $record.Name = $item.Name
            $record.NameSource = $item.NameSource
            $record.LastDetectedBy = $item.DetectedBy
            $record.LastOpenPorts = $item.OpenPorts
            $record.LastSubnet = $SubnetValue
            $record.SeenCount = [int]$record.SeenCount + 1
        }
        else {
            $inventory[$key] = [pscustomobject]@{
                FirstSeen = $now
                LastSeen = $now
                LastIP = $item.IP
                MAC = $item.MAC
                Vendor = $item.Vendor
                Name = $item.Name
                NameSource = $item.NameSource
                LastDetectedBy = $item.DetectedBy
                LastOpenPorts = $item.OpenPorts
                LastSubnet = $SubnetValue
                SeenCount = 1
            }
        }
    }

    $inventory.Values | Sort-Object LastIP | ConvertTo-Json -Depth 8 | Set-Content -Path $Path -Encoding UTF8
}
# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

$config = Load-ScannerConfig

switch ($Profile) {
    'Fast' {
        if (-not $PingTimeoutMs) { $PingTimeoutMs = 180 }
        if (-not $TcpTimeoutMs) { $TcpTimeoutMs = 120 }
        if (-not $MaxThreads) { $MaxThreads = 256 }
        if (-not $TcpPorts) { $TcpPorts = @(80, 443, 445, 3389, 22) }
        if (-not $TcpProbe -and -not $NoTcpProbe) { $NoTcpProbe = $true }
    }
    'Standard' {
        if (-not $PingTimeoutMs) { $PingTimeoutMs = 250 }
        if (-not $TcpTimeoutMs) { $TcpTimeoutMs = 180 }
        if (-not $MaxThreads) { $MaxThreads = 256 }
    }
    'Deep' {
        if (-not $PingTimeoutMs) { $PingTimeoutMs = 350 }
        if (-not $TcpTimeoutMs) { $TcpTimeoutMs = 260 }
        if (-not $MaxThreads) { $MaxThreads = 192 }
        if (-not $TcpPorts) { $TcpPorts = @($config.DeepTcpProbePorts | ForEach-Object { [int]$_ }) }
        if (-not $TcpProbe -and -not $NoTcpProbe) { $TcpProbe = $true }
        $TcpScanAllPorts = $true
    }
}

if ($UpdateOui) {
    [void](Update-OuiDatabase -Path $OuiPath -Url ([string]$config.OuiDownloadUrl))
    return
}

if ([bool]$config.CreateSampleOuiCsv) {
    Ensure-SampleOuiCsv -Path $OuiPath
}

if (-not $Subnet) {
    $Subnet = [string]$config.LastSubnet
    if ([string]::IsNullOrWhiteSpace($Subnet)) {
        $Subnet = '192.168.1.0/24'
    }
}

if (-not $PingTimeoutMs) {
    $PingTimeoutMs = [int]$config.PingTimeoutMs
}

if (-not $TcpTimeoutMs) {
    $TcpTimeoutMs = [int]$config.TcpTimeoutMs
}

if (-not $MaxThreads) {
    $MaxThreads = [int]$config.MaxThreads
}

if (-not $TcpPorts) {
    $TcpPorts = @($config.TcpProbePorts | ForEach-Object { [int]$_ })
}

$doTcpProbe = [bool]$config.TcpProbeEnabledDefault
if ($TcpProbe) { $doTcpProbe = $true }
if ($NoTcpProbe) { $doTcpProbe = $false }

$doResolveDns = [bool]$config.ResolveDnsDefault
if ($ResolveDns) { $doResolveDns = $true }
if ($NoDns) { $doResolveDns = $false }

$doNetBios = [bool]$config.NetBiosDefault
if ($NetBios) { $doNetBios = $true }
if ($NoNetBios) { $doNetBios = $false }

$doExportHtml = [bool]$config.ExportHtmlDefault
if ($ExportHtml) { $doExportHtml = $true }
if ($NoExportHtml) { $doExportHtml = $false }

$doExportCsv = [bool]$config.ExportCsvDefault
if ($ExportCsv) { $doExportCsv = $true }

$doExportJson = [bool]$config.ExportJsonDefault
if ($ExportJson) { $doExportJson = $true }

Write-Host ''
Write-Host "network-scanner $($Script:NetworkScannerVersion)" -ForegroundColor Cyan
Write-Host "Data path      : $DataPath"
Write-Host "Subnet         : $Subnet"
Write-Host "Profile        : $Profile"
Write-Host "Ping timeout   : $PingTimeoutMs ms"
Write-Host "Max threads    : $MaxThreads"
Write-Host "TCP probe      : $doTcpProbe"
if ($doTcpProbe) {
    Write-Host "TCP timeout    : $TcpTimeoutMs ms"
    Write-Host "TCP ports      : $($TcpPorts -join ', ')"
    Write-Host "TCP all ports  : $([bool]$TcpScanAllPorts)"
}
Write-Host "DNS reverse    : $doResolveDns"
Write-Host "NetBIOS names  : $doNetBios"
Write-Host "OUI database   : $OuiPath"
Write-Host ''

$sw = [System.Diagnostics.Stopwatch]::StartNew()

$ipList = @(Get-IpRangeFromCidr -Cidr $Subnet)
Write-Host "IP generated   : $($ipList.Count)"

Write-Host 'Phase 1/5 - Fast ICMP sweep...'
$pingResults = @(Invoke-PingSweepFast -IpList $ipList -TimeoutMs $PingTimeoutMs -Threads $MaxThreads)
Write-Host "ICMP hosts     : $($pingResults.Count)"

$aliveMap = @{}
foreach ($p in $pingResults) {
    $aliveMap[[string]$p.IP] = [ordered]@{
        IP          = [string]$p.IP
        AliveByPing = $true
        AliveByTcp  = $false
        PingMs      = $p.PingMs
        OpenPorts   = $null
    }
}

if ($doTcpProbe) {
    Write-Host 'Phase 2/5 - Fast TCP probe...'
    $tcpResults = @(Invoke-TcpProbeSweepFast -IpList $ipList -Ports $TcpPorts -TimeoutMs $TcpTimeoutMs -Threads $MaxThreads -ScanAllPorts ([bool]$TcpScanAllPorts))

    foreach ($t in $tcpResults) {
        $ip = [string]$t.IP
        if (-not $aliveMap.ContainsKey($ip)) {
            $aliveMap[$ip] = [ordered]@{
                IP          = $ip
                AliveByPing = $false
                AliveByTcp  = $true
                PingMs      = $null
                OpenPorts   = $t.OpenPorts
            }
        }
        else {
            $aliveMap[$ip].AliveByTcp = $true
            $aliveMap[$ip].OpenPorts = $t.OpenPorts
        }
    }

    Write-Host "TCP hosts      : $($tcpResults.Count)"
}
else {
    Write-Host 'Phase 2/5 - TCP probe skipped.'
}

Write-Host 'Phase 3/5 - Reading ARP / neighbor cache...'
Start-Sleep -Milliseconds 150
$macCache = Get-MacCache
$ouiMap = Load-OuiDatabase -Path $OuiPath

$aliveIps = @($aliveMap.Keys)

$dnsNameMap = @{}
if ($doResolveDns) {
    Write-Host 'Phase 4/5 - Reverse DNS name lookup...'
    $dnsNameMap = Resolve-DnsNamesFast -IpList $aliveIps -Threads ([Math]::Min($MaxThreads, 64))
}
elseif ($doNetBios) {
    Write-Host 'Phase 4/5 - DNS lookup skipped.'
}
else {
    Write-Host 'Phase 4/5 - Name lookup skipped.'
}

$netBiosNameMap = @{}
if ($doNetBios) {
    Write-Host 'Phase 4b/5 - NetBIOS name lookup...'
    $netBiosNameMap = Resolve-NetBiosNamesFast -IpList $aliveIps -Threads ([Math]::Min($MaxThreads, 64))
}

Write-Host 'Phase 5/5 - Building results...'

$results = New-Object System.Collections.Generic.List[object]

foreach ($ip in ($aliveMap.Keys | Sort-Object { ConvertTo-UInt32Ip $_ })) {
    $v = $aliveMap[$ip]

    $mac = $null
    if ($macCache.ContainsKey($ip)) {
        $mac = $macCache[$ip]
    }

    $vendor = Get-VendorFromMac -Mac $mac -OuiMap $ouiMap

    $name = $null
    $nameSource = $null

    if ($dnsNameMap.ContainsKey($ip)) {
        $name = $dnsNameMap[$ip]
        $nameSource = 'DNS'
    }

    if (-not $name -and $netBiosNameMap.ContainsKey($ip)) {
        $name = $netBiosNameMap[$ip]
        $nameSource = 'NetBIOS'
    }

    $detectedByParts = New-Object System.Collections.Generic.List[string]
    if ($v.AliveByPing) { [void]$detectedByParts.Add('ICMP') }
    if ($v.AliveByTcp)  { [void]$detectedByParts.Add('TCP') }

    [void]$results.Add([pscustomobject]@{
        IP         = $ip
        MAC        = $mac
        Vendor     = $vendor
        Name       = $name
        NameSource = $nameSource
        DetectedBy = ($detectedByParts -join '+')
        PingMs     = $v.PingMs
        OpenPorts  = $v.OpenPorts
        Status     = 'online'
        ChangeStatus = $null
    })
}

$sw.Stop()

$removedResults = @()
if ($Compare) {
    $previousResults = @(Load-JsonArrayFile -Path $PreviousScanPath)
    $comparison = Compare-ScanResults -Current $results.ToArray() -Previous $previousResults
    $removedResults = @($comparison.Removed)
    foreach ($removedResult in $removedResults) {
        $removedResult | Add-Member -NotePropertyName Status -NotePropertyValue 'offline' -Force
    }
}

$results.ToArray() | ConvertTo-Json -Depth 8 | Set-Content -Path $PreviousScanPath -Encoding UTF8
if (-not $NoInventory) {
    Save-DeviceInventory -Results $results.ToArray() -Path $InventoryPath -SubnetValue $Subnet
}

# Save latest settings.
$config.LastSubnet = $Subnet
$config.PingTimeoutMs = $PingTimeoutMs
$config.TcpTimeoutMs = $TcpTimeoutMs
$config.MaxThreads = $MaxThreads
$config.TcpProbePorts = @($TcpPorts)
Save-ScannerConfig -Config $config

Write-Host ''
Write-Host 'Results:' -ForegroundColor Green
$consoleResults = $results | Select-Object IP, Name, Vendor, DetectedBy, OpenPorts, ChangeStatus
$consoleResults | Format-Table -Property IP, Name, Vendor, DetectedBy, OpenPorts, ChangeStatus -Wrap

Write-Host ''
Write-Host "Hosts detected : $($results.Count)"
if ($Compare) {
    Write-Host "Added          : $(@($results | Where-Object { $_.ChangeStatus -eq 'Added' }).Count)"
    Write-Host "Changed        : $(@($results | Where-Object { $_.ChangeStatus -like 'Changed:*' }).Count)"
    Write-Host "Removed        : $($removedResults.Count)"
}
Write-Host "Elapsed time   : $([math]::Round($sw.Elapsed.TotalSeconds, 2)) sec"
Write-Host "State file     : $PreviousScanPath"
if (-not $NoInventory) {
    Write-Host "Inventory      : $InventoryPath"
}

$safeSubnet = $Subnet.Replace('/', '_').Replace('.', '-')
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

if ($doExportHtml) {
    $htmlPath = Join-Path $ReportDir "network-scanner_$safeSubnet`_$timestamp.html"
    Export-ScanHtml -Results $results.ToArray() -RemovedResults $removedResults -Subnet $Subnet -OutputPath $htmlPath -ElapsedSeconds $sw.Elapsed.TotalSeconds
    Write-Host "HTML report    : $htmlPath" -ForegroundColor Cyan
}

if ($doExportCsv) {
    $csvPath = Join-Path $ReportDir "network-scanner_$safeSubnet`_$timestamp.csv"
    $exportRows = @(
        $results | Select-Object @{Name='RecordState';Expression={'Current'}}, *
        $removedResults | Select-Object @{Name='RecordState';Expression={'Removed'}}, *
    )
    $exportRows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "CSV export     : $csvPath" -ForegroundColor Cyan
}

if ($doExportJson) {
    $jsonPath = Join-Path $ReportDir "network-scanner_$safeSubnet`_$timestamp.json"
    [pscustomobject]@{
        Tool = $Script:ToolName
        Version = $Script:NetworkScannerVersion
        Subnet = $Subnet
        Profile = $Profile
        GeneratedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Current = $results.ToArray()
        Removed = $removedResults
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8
    Write-Host "JSON export    : $jsonPath" -ForegroundColor Cyan
}

Write-Host ''




