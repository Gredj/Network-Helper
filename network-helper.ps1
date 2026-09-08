# PowerShell network helper for Windows
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\network-helper.ps1
#   powershell -ExecutionPolicy Bypass -Command ". .\network-helper.ps1; Show-WirelessInterfaces"
#
# A polished Windows-side toolkit for wireless inspection, path analysis, and packet-capture workflows.

$script:Title = "Windows Network Lab"
$script:Subtitle = "Wireless inventory, routing, and packet analysis"

function Write-Section {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [string]$Color = 'Cyan'
    )

    Write-Host "" 
    Write-Host ("=" * 88) -ForegroundColor DarkGray
    Write-Host ("   {0}" -f $Title).PadRight(88) -ForegroundColor $Color
    Write-Host ("=" * 88) -ForegroundColor DarkGray
}

function Show-Banner {
    Write-Host "" 
    Write-Host "   .__   __.  __    __       ___      .__   __.  _______ " -ForegroundColor DarkCyan
    Write-Host "   |  \ /  | |  |  |  |     /   \     |  \ |  | |   ____|" -ForegroundColor DarkCyan
    Write-Host "   |  .`'  | |  |  |  |    /  ^  \    |   \|  | |  |__   " -ForegroundColor DarkCyan
    Write-Host "   |  |\   | |  |  |  |   /  /_\  \   |  . `  | |   __|  " -ForegroundColor DarkCyan
    Write-Host "   |  | \  | |  `--'  |  /  _____  \  |  |\   | |  |____ " -ForegroundColor DarkCyan
    Write-Host "   |__|  \__|  \______/  /__/     \__\ |__| \__| |_______|" -ForegroundColor DarkCyan
    Write-Host "" 
    Write-Host ("   {0}" -f $script:Title) -ForegroundColor White
    Write-Host ("   {0}" -f $script:Subtitle) -ForegroundColor DarkGray
    Write-Host "" 
}

function Show-QuickCommands {
    Write-Host "   Quick commands:" -ForegroundColor Yellow
    Write-Host "   • Show-WirelessInterfaces" -ForegroundColor DarkCyan
    Write-Host "   • Show-WifiDetails" -ForegroundColor DarkCyan
    Write-Host "   • Show-WifiProfiles" -ForegroundColor DarkCyan
    Write-Host "   • Show-IpAndRoutingInfo" -ForegroundColor DarkCyan
    Write-Host "   • Start-TsharkCapture -InterfaceName 'Wi-Fi' -DurationSeconds 20" -ForegroundColor DarkCyan
    Write-Host "   • Start-Wireshark" -ForegroundColor DarkCyan
    Write-Host "   • Show-AdvancedActionsMenu" -ForegroundColor DarkCyan
    Write-Host ""
}

function Get-WirelessInterfaces {
    [CmdletBinding()]
    param()

    $wireless = Get-NetAdapter | Where-Object {
        $_.Status -eq 'Up' -and (
            $_.InterfaceDescription -match 'Wi-Fi|Wireless|802\.11' -or
            $_.Name -match 'Wi-Fi|WiFi'
        )
    }

    if (-not $wireless) {
        Write-Host "   No wireless interfaces were detected." -ForegroundColor Yellow
        return $null
    }

    return $wireless | Select-Object Name, InterfaceDescription, Status, MacAddress, LinkSpeed, InterfaceIndex
}

function Show-WirelessInterfaces {
    $wireless = Get-WirelessInterfaces
    if (-not $wireless) { return }

    $wireless | Format-Table -AutoSize
}

function Get-WifiDetails {
    [CmdletBinding()]
    param()

    $wifiInfo = netsh wlan show interfaces 2>$null
    if ($LASTEXITCODE -eq 0 -and $wifiInfo) {
        return $wifiInfo
    }

    Write-Host "   Wi-Fi details are not available from netsh." -ForegroundColor Yellow
    return $null
}

function Show-WifiDetails {
    Write-Section "Wi-Fi state"
    $wifiInfo = Get-WifiDetails
    if ($wifiInfo) {
        $wifiInfo | Select-String -Pattern 'Name|Description|State|Radio type|Signal|SSID|BSSID|Channel|Authentication|Cipher'
    }
}

function Show-IpAndRoutingInfo {
    Write-Section "IP and routing"

    Get-NetIPConfiguration |
        Where-Object { $_.NetAdapter.Status -eq 'Up' } |
        Select-Object InterfaceAlias,
                      @{Name='IPv4Address';Expression={($_.IPv4Address | ForEach-Object { $_.IPAddress }) -join ', '}},
                      @{Name='IPv4DefaultGateway';Expression={($_.IPv4DefaultGateway | ForEach-Object { $_.IPAddress }) -join ', '}},
                      @{Name='DNSServer';Expression={if ($null -ne $_.DNSServer) { ($_.DNSServer | ForEach-Object { $_.ServerAddresses }) -join ', ' } else { '' }}} |
        Format-Table -AutoSize

    Write-Host "" 
    Write-Host "   Route table" -ForegroundColor Yellow
    route print
}

function Show-ArpTable {
    Write-Section "ARP table"
    arp -a
}

function Show-EstablishedConnections {
    Write-Section "Established TCP sessions"
    try {
        Get-NetTCPConnection -State Established |
            Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess |
            Sort-Object RemoteAddress |
            Format-Table -AutoSize
    }
    catch {
        Write-Host "   Unable to query TCP connections: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Show-WifiProfiles {
    Write-Section "Saved Wi-Fi profiles"
    netsh wlan show profiles 2>$null
}

function Show-WifiScan {
    Write-Section "Visible Wi-Fi networks"
    netsh wlan show networks mode=bssid 2>$null
}

function Show-InterfaceStatistics {
    [CmdletBinding()]
    param(
        [string]$InterfaceName
    )

    $adapter = if ($InterfaceName) {
        Get-NetAdapter -Name $InterfaceName -ErrorAction SilentlyContinue
    }
    else {
        Get-WirelessInterfaces | Select-Object -First 1
    }

    if (-not $adapter) {
        Write-Host "   No matching adapter was found." -ForegroundColor Yellow
        return
    }

    Write-Section "Interface statistics for $($adapter.Name)"
    Get-NetAdapterStatistics -Name $adapter.Name |
        Select-Object ReceivedBytes, SentBytes, ReceivedUnicastPackets, SentUnicastPackets, ReceivedErrors, SentErrors, DiscardedPacketsIncoming, DiscardedPacketsOutgoing |
        Format-List
}

function Show-CaptureSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CaptureFile
    )

    $tsharkPath = 'C:\Program Files\Wireshark\tshark.exe'
    if (-not (Test-Path $tsharkPath)) {
        Write-Host "   tshark was not found at $tsharkPath" -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path $CaptureFile)) {
        Write-Host "   Capture file not found: $CaptureFile" -ForegroundColor Yellow
        return
    }

    Write-Section "Protocol hierarchy"
    & $tsharkPath -r $CaptureFile -q -z io,phs

    Write-Host "" 
    Write-Section "TCP conversations"
    & $tsharkPath -r $CaptureFile -q -z conv,tcp

    Write-Host "" 
    Write-Section "UDP conversations"
    & $tsharkPath -r $CaptureFile -q -z conv,udp
}

function Show-NetworkSummary {
    Write-Section "Wireless inventory"
    Show-WirelessInterfaces

    Show-WifiDetails
    Show-WifiProfiles
    Show-WifiScan

    Show-IpAndRoutingInfo
    Show-ArpTable
    Show-EstablishedConnections
}

function Start-Wireshark {
    [CmdletBinding()]
    param(
        [string]$InterfaceName
    )

    Write-Host "   Opening Wireshark for packet inspection..." -ForegroundColor Cyan
    $wiresharkPath = 'C:\Program Files\Wireshark\Wireshark.exe'
    if (-not (Test-Path $wiresharkPath)) {
        Write-Host "   Wireshark was not found at $wiresharkPath" -ForegroundColor Yellow
        Write-Host "   Install Wireshark and Npcap from https://www.wireshark.org/" -ForegroundColor Yellow
        return
    }

    if ($InterfaceName) {
        Start-Process $wiresharkPath -ArgumentList "-i $InterfaceName"
    }
    else {
        Start-Process $wiresharkPath
    }
}

function Start-TsharkCapture {
    [CmdletBinding()]
    param(
        [string]$InterfaceName,
        [string]$OutputFile = 'capture.pcapng',
        [string]$CaptureFilter = '',
        [int]$DurationSeconds = 30
    )

    $tsharkPath = 'C:\Program Files\Wireshark\tshark.exe'
    if (-not (Test-Path $tsharkPath)) {
        Write-Host "   tshark was not found at $tsharkPath" -ForegroundColor Yellow
        Write-Host "   Install Wireshark to use command-line packet capture." -ForegroundColor Yellow
        return
    }

    if (-not $InterfaceName) {
        $InterfaceName = (Get-WirelessInterfaces | Select-Object -First 1 -ExpandProperty Name)
    }

    if (-not $InterfaceName) {
        Write-Host "   No interface was supplied and no wireless interface was detected." -ForegroundColor Yellow
        return
    }

    $args = @('-i', $InterfaceName, '-w', $OutputFile, '-a', "duration:$DurationSeconds")
    if ($CaptureFilter) {
        $args += @('-f', $CaptureFilter)
    }

    Write-Host "   Starting capture on $InterfaceName for $DurationSeconds seconds..." -ForegroundColor Cyan
    Start-Process $tsharkPath -ArgumentList $args -NoNewWindow -Wait
    Write-Host "   Capture saved to $OutputFile" -ForegroundColor Green
}

function Test-PathToHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName
    )

    Test-NetConnection -ComputerName $HostName -InformationLevel Detailed
}

function Show-TraceRoute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName
    )

    Test-NetConnection -ComputerName $HostName -TraceRoute
}

function Initialize-Report {
    $reportsDir = Join-Path $PSScriptRoot 'reports'
    if (-not (Test-Path $reportsDir)) {
        New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:ReportPath = Join-Path $reportsDir ("network-lab-{0}.txt" -f $timestamp)
    New-Item -Path $script:ReportPath -ItemType File -Force | Out-Null

    Write-ReportLine "Windows Network Lab report"
    Write-ReportLine ("Generated: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Write-ReportLine ("Host: {0}" -f $env:COMPUTERNAME)
    Write-ReportLine ""
}

function Write-ReportLine {
    param([string]$Line)

    if ($script:ReportPath) {
        Add-Content -Path $script:ReportPath -Value $Line
    }
}

function Write-ReportBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [string]$Content
    )

    if (-not $script:ReportPath) {
        return
    }

    Write-ReportLine ""
    Write-ReportLine ("=" * 72)
    Write-ReportLine $Title
    Write-ReportLine ("=" * 72)
    if ($Content) {
        $Content -split "`r?`n" | ForEach-Object {
            if ($_.Length -gt 0) {
                Write-ReportLine $_
            }
        }
    }
}

function Get-DefaultGateway {
    $gateway = Get-NetIPConfiguration |
        Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
        Select-Object -First 1

    if ($gateway -and $gateway.IPv4DefaultGateway) {
        return $gateway.IPv4DefaultGateway.IPAddress
    }

    return $null
}

function Export-NetworkReport {
    Write-ReportBlock "Initial network snapshot" ""

    $wireless = Get-WirelessInterfaces
    if ($wireless) {
        Write-ReportBlock "Wireless interfaces" ($wireless | Format-Table -AutoSize | Out-String)
    }
    else {
        Write-ReportBlock "Wireless interfaces" "No wireless interfaces detected."
    }

    $wifiInfo = Get-WifiDetails
    if ($wifiInfo) {
        Write-ReportBlock "Wi-Fi details" ($wifiInfo | Out-String)
    }

    $profiles = netsh wlan show profiles 2>$null
    if ($profiles) {
        Write-ReportBlock "Saved Wi-Fi profiles" ($profiles | Out-String)
    }

    $scan = netsh wlan show networks mode=bssid 2>$null
    if ($scan) {
        Write-ReportBlock "Visible networks" ($scan | Out-String)
    }

    $ipInfo = Get-NetIPConfiguration |
        Where-Object { $_.NetAdapter.Status -eq 'Up' } |
        Select-Object InterfaceAlias,
        @{Name='IPv4Address';Expression={($_.IPv4Address | ForEach-Object { $_.IPAddress }) -join ', '}},
        @{Name='IPv4DefaultGateway';Expression={($_.IPv4DefaultGateway | ForEach-Object { $_.IPAddress }) -join ', '}},
        @{Name='DNSServer';Expression={if ($null -ne $_.DNSServer) { ($_.DNSServer | ForEach-Object { $_.ServerAddresses }) -join ', ' } else { '' }}}

    if ($ipInfo) {
        Write-ReportBlock "IP configuration" ($ipInfo | Format-Table -AutoSize | Out-String)
    }

    $route = route print 2>$null
    if ($route) {
        Write-ReportBlock "Route table" ($route | Out-String)
    }

    $arp = arp -a 2>$null
    if ($arp) {
        Write-ReportBlock "ARP table" ($arp | Out-String)
    }

    try {
        $connections = Get-NetTCPConnection -State Established |
            Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess |
            Sort-Object RemoteAddress
        if ($connections) {
            Write-ReportBlock "Established TCP sessions" ($connections | Format-Table -AutoSize | Out-String)
        }
    }
    catch {
        Write-ReportBlock "Established TCP sessions" ("Unable to query TCP connections: {0}" -f $_.Exception.Message)
    }
}

function Invoke-PortScan {
    [CmdletBinding()]
    param(
        [string]$Target,
        [string[]]$Ports = @('21','22','23','25','53','80','110','135','139','143','443','445','3389','8080','8443')
    )

    if (-not $Target) {
        $Target = Get-DefaultGateway
    }

    if (-not $Target) {
        $Target = '127.0.0.1'
    }

    Write-Section "Port scan"
    Write-Host "   Scanning $Target for common service ports..." -ForegroundColor Cyan

    $results = foreach ($port in $Ports) {
        $client = [System.Net.Sockets.TcpClient]::new()
        try {
            $connectTask = $client.BeginConnect($Target, [int]$port, $null, $null)
            $connected = $connectTask.AsyncWaitHandle.WaitOne(700, $false)
            if ($connected -and $client.Connected) {
                $client.EndConnect($connectTask)
                [pscustomobject]@{Target = $Target; Port = $port; Status = 'Open'}
            }
            else {
                [pscustomobject]@{Target = $Target; Port = $port; Status = 'Closed/Filtered'}
            }
        }
        catch {
            [pscustomobject]@{Target = $Target; Port = $port; Status = 'Closed'}
        }
        finally {
            $client.Dispose()
        }
    }

    $results | Sort-Object Port | Format-Table -AutoSize
    Write-ReportBlock "Port scan" ($results | Sort-Object Port | Format-Table -AutoSize | Out-String)
}

function Show-PostScanMenu {
    while ($true) {
        Write-Section "Compact menu"
        Write-Host "   1) Port scan" -ForegroundColor Cyan
        Write-Host "   2) Short capture" -ForegroundColor Cyan
        Write-Host "   3) Trace route" -ForegroundColor Cyan
        Write-Host "   4) Full lab run" -ForegroundColor Cyan
        Write-Host "   5) Advanced actions" -ForegroundColor Cyan
        Write-Host "   0) Exit" -ForegroundColor Cyan
        Write-Host ""

        $choice = Read-Host "   Select an action"
        switch ($choice) {
            '1' {
                $target = Read-Host "   Target host or IP [default gateway]"
                if (-not $target) { $target = Get-DefaultGateway }
                if (-not $target) { $target = '127.0.0.1' }
                Invoke-PortScan -Target $target
            }
            '2' {
                $iface = (Get-WirelessInterfaces | Select-Object -First 1 -ExpandProperty Name)
                $duration = Read-Host "   Capture duration in seconds [20]"
                if (-not $duration) { $duration = 20 }
                $output = Read-Host "   Output file [capture.pcapng]"
                if (-not $output) { $output = 'capture.pcapng' }
                Start-TsharkCapture -InterfaceName $iface -OutputFile $output -DurationSeconds ([int]$duration)
                Write-ReportBlock "Short capture" ("Interface: {0}`nOutput: {1}`nDuration: {2}s" -f $iface, $output, $duration)
            }
            '3' {
                $target = Read-Host "   Target host [8.8.8.8]"
                if (-not $target) { $target = '8.8.8.8' }
                Write-Section "Connectivity check"
                Test-PathToHost -HostName $target
                Show-TraceRoute -HostName $target
                Write-ReportBlock "Trace route" ("Target: {0}" -f $target)
            }
            '4' {
                Write-Section "Full lab run"
                Write-Host "   Running a compact lab sequence..." -ForegroundColor Cyan
                Export-NetworkReport
                $gateway = Get-DefaultGateway
                if ($gateway) {
                    Invoke-PortScan -Target $gateway
                }
                else {
                    Write-Host "   No default gateway was found." -ForegroundColor Yellow
                }
                $iface = (Get-WirelessInterfaces | Select-Object -First 1 -ExpandProperty Name)
                Start-TsharkCapture -InterfaceName $iface -OutputFile 'lab-capture.pcapng' -DurationSeconds 15
                Write-ReportBlock "Full lab run" ("Completed full lab run. Report saved to {0}" -f $script:ReportPath)
            }
            '5' {
                Show-AdvancedActionsMenu
            }
            '0' {
                break
            }
            default {
                Write-Host "   Invalid selection. Please choose 1, 2, 3, 4, 5, or 0." -ForegroundColor Yellow
            }
        }

        if ($choice -notin @('1','2','3','4','5')) {
            break
        }

        Write-Host ""
        $again = Read-Host "   Run another action? [y/N]"
        if ($again -notmatch '^[Yy]') {
            break
        }
    }
}

function Show-NetworkDashboard {
    Clear-Host
    Show-Banner
    Write-Host "   Loaded with a clean, terminal-first presentation for wireless and packet-analysis work." -ForegroundColor DarkGray
    Write-Host ""
    Show-QuickCommands

    Initialize-Report
    Export-NetworkReport
    Show-NetworkSummary
    Show-PostScanMenu

    Write-Host "" 
    Write-Host ("   Report saved to {0}" -f $script:ReportPath) -ForegroundColor Green
}

. (Join-Path $PSScriptRoot 'network-extensions.ps1')

if ($MyInvocation.InvocationName -ne '.') {
    Show-NetworkDashboard
}
