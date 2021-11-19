#requires -RunAsAdministrator
#requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$NoInternet
)


##### Setup variables #####

# load SdnCommon - this is the first step in all debug PowerShell scripts
if (-NOT $SdnCommonLoaded)
{
    Write-Verbose "Get-SdnLogs - Loading SdnCommon"
    if (-NOT $NoInternet.IsPresent)
    {
        # can github be reached?
        $pngGH = Test-NetConnection github.com -Port 443 -InformationLevel Quiet -EA SilentlyContinue

        if ($pngGH)
        {
            #$cmnURL = 'https://raw.githubusercontent.com/microsoft/SDN/master/Kubernetes/windows/debug/SdnCommon.ps1'
            $cmnURL = 'https://raw.githubusercontent.com/JamesKehr/SDN/collectlogs_update/Kubernetes/windows/debug/SdnCommon.ps1'

            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12, [System.Net.SecurityProtocolType]::Tls13
            Invoke-WebRequest $cmnURL -OutFile "$($PWD.Path)\SdnCommon.ps1" -UseBasicParsing
        }
    }
    
    $sdncmnFnd = Get-Item "$($PWD.Path)\SdnCommon.ps1" -EA SilentlyContinue
    if ( -NOT $sdncmnFnd)
    {
        # check default script location
        $sdncmnFnd = Get-Item "C:\k\debug\SdnCommon.ps1" -EA SilentlyContinue
        
        if ( -NOT $sdncmnFnd)
        {
            return ( Write-Error "Failed to download or find SdnCommon.ps1." -EA Stop)
        }
    }

    Push-Location $sdncmnFnd.Directory
    if ($pngGH -or -NOT $NoInternet.IsPresent)
    {
        .\SdnCommon.ps1
    }
    else
    {
        .\SdnCommon.ps1 -NoInternet
    }
    Pop-Location
}


Write-Verbose "Get-SdnLogs - Setting output directory to $outDir"


## MAIN ##
Push-Location "$outDir"

# HNS network details
Write-Verbose "Get-SdnLogs - Collecting HNS network details"
Get-HnsNetwork | Select-Object Name, Type, Id, AddressPrefix > hnsnetwork.txt
Get-HnsNetwork | ConvertTo-Json -Depth 20 > hnsnetwork.json
Get-HnsNetwork | ForEach-Object { Get-HnsNetwork -Id $_.ID -Detailed } | ConvertTo-Json -Depth 20 > hnsnetworkdetailed.json

# HNS endpoint details
Write-Verbose "Get-SdnLogs - Collecting HNS endpoint details"
Get-HnsEndpoint | Select-Object IpAddress, MacAddress, IsRemoteEndpoint, State > hnsendpoint.txt
Get-HnsEndpoint | ConvertTo-Json -Depth 20 > hnsendpoint.json

# HNS policy details
Write-Verbose "Get-SdnLogs - Getting HNS policy list"
Get-HnsPolicyList | ConvertTo-Json -Depth 20 > hnspolicy.json

# get vmSwitch port info
$vfpctrlFnd = Get-Command vfpctrl.exe -EA SilentlyContinue
if ($vfpctrlFnd)
{
    Write-Verbose "Get-SdnLogs - Getting vmSwitch ports"
    vfpctrl.exe /list-vmswitch-port > VMSports.txt
}
else 
{
    Write-Verbose "Get-SdnLogs - vfpctrl.exe was not found. Skipping VMSports.txt."    
}

# dump all VFP policies
Write-Verbose "BaseDir: $BaseDir"
Push-Location $BaseDir
[array]$vmSwitches = Get-VMSwitch -EA SilentlyContinue
foreach ($vmSwitch in $vmSwitches)
{
    Write-Verbose "Get-SdnLogs - Getting policies for vmSwitch $vmSwitch"
    .\dumpVfpPolicies.ps1 -switchName $vmSwitch -outfile "$outDir\vfpOutput_$($vmSwitch.Name).txt"
}
Pop-Location

# host network configuration
Write-Verbose "Get-SdnLogs - Collecting host network details"
ipconfig /allcompartments /all > ip.txt
Get-NetIPAddress -IncludeAllCompartments | Select-Object IPAddress, InterfaceIndex, InterfaceAlias, AddressFamily, Type, PrefixLength, SkipAsSource >> ip.txt

Get-NetAdapter | Select-Object Name, InterfaceDescription, InterfaceIndex | Format-Table -AutoSize > routes.txt
Get-NetRoute -IncludeAllCompartments | Select-Object ifIndex, DestinationPrefix, NextHop, RouteMetric, @{Name="ifMetric"; Expression={$_.InterfaceMetric}}, @{Name="TotalMetric"; Expression={ ($_.RouteMetric + $_.InterfaceMetric) }} | Sort-Object -Property IfIndex | Format-Table -AutoSize >> routes.txt
route print >> routes.txt

Get-NetFirewallRule -PolicyStore ActiveStore >> firewall.txt

Get-NetIPInterface > mtu.txt
netsh int ipv4 sh int >> mtu.txt

nvspinfo -a -i -h -D -p -d -m -q > nvspinfo.txt
nmscrub -a -n -t > nmscrub.txt

Get-NetAdapter | Select-Object Name, InterfaceDescription, InterfaceIndex | Format-Table -AutoSize > arp.txt
Get-NetNeighbor -IncludeAllCompartments >> arp.txt
arp -a >> arp.txt

# export services
sc.exe queryex > scqueryex.txt
sc.exe qc hns >> scqueryex.txt
sc.exe qc vfpext >> scqueryex.txt

#Get-NetAdapter | ForEach-Object {$ifindex=$_.IfIndex; $ifName=$_.Name; netsh int ipv4 sh int $ifindex | Out-File  -FilePath "${ifName}_int.txt" -Encoding ascii}
#Get-NetAdapter | ForEach-Object { $_ | Format-List * | Out-File "$($_.Name)_int.txt" -Encoding ascii }
Get-NetAdapter -IncludeHidden >> netadapter.txt

New-Item -Path adapters -ItemType Directory
$arrInvalidChars = [System.IO.Path]::GetInvalidFileNameChars()
$invalidChars = [RegEx]::Escape(-join $arrInvalidChars)

Get-NetAdapter -IncludeHidden  | & { process {
        $ifindex = $_.IfIndex
        $ifName = $_.Name
        $fileName = "${ifName}_int.txt"
        $fileName = [RegEx]::Replace($fileName, "[$invalidChars]", '_')
        Get-NetIPInterface -InterfaceIndex 1 $ifindex | Format-List * | Out-File -FilePath "adapters\$fileName" -Encoding ascii
        $_ | Format-List * | Out-File -Append -FilePath "adapters\$fileName" -Encoding ascii
    }
}

$res = Get-Command hnsdiag.exe -ErrorAction SilentlyContinue
if ($res)
{
    Write-Verbose "Get-SdnLogs - HNS diag details"
    hnsdiag list all -d > hnsdiag.json
    hnsdiag list adapters *> hnsdiag.adapters.txt
    hcsdiag list  > hcsdiag.txt
}

$res = Get-Command docker.exe -ErrorAction SilentlyContinue
if ($res)
{
    Write-Verbose "Get-SdnLogs - Docker details"
    docker ps -a > docker.txt
}

Write-Verbose "Get-SdnLogs - Getting ephemeral port details"
function CountAvailableEphemeralPorts 
{
    param(
        [string]$protocol = "TCP", 
        [uint32]$portRangeSize = 64
    )

    # First, remove all the text bells and whistle (plain text, table headers, dashes, empty lines, ...) from netsh output 
    $tcpRanges = (netsh int ipv4 sh excludedportrange $protocol) -replace "[^0-9,\ ]",'' | Where-Object {$_.trim() -ne "" }
 
    # Then, remove any extra space characters. Only capture the numbers representing the beginning and end of range
    $tcpRangesArray = $tcpRanges -replace "\s+(\d+)\s+(\d+)\s+",'$1,$2' | ConvertFrom-String -Delimiter ","

    # Extract the ephemeral ports ranges
    $EphemeralPortRange = (netsh int ipv4 sh dynamicportrange $protocol) -replace "[^0-9]",'' | Where-Object {$_.trim() -ne "" }
    $EphemeralPortStart = [Convert]::ToUInt32($EphemeralPortRange[0])
    $EphemeralPortEnd = $EphemeralPortStart + [Convert]::ToUInt32($EphemeralPortRange[1]) - 1

    # Find the external interface
    $externalInterfaceIdx = (Get-NetRoute -DestinationPrefix "0.0.0.0/0")[0].InterfaceIndex
    $hostIP = (Get-NetIPConfiguration -ifIndex $externalInterfaceIdx).IPv4Address.IPAddress

    # Extract the used TCP ports from the external interface
    $usedTcpPorts  = (Get-NetTCPConnection -LocalAddress $hostIP -ErrorAction Ignore).LocalPort
    $usedTcpPorts | ForEach-Object { $tcpRangesArray += [pscustomobject]@{P1 = $_; P2 = $_} }

    # Extract the used TCP ports from the 0.0.0.0 interface
    $usedTcpGlobalPorts = (Get-NetTCPConnection -LocalAddress "0.0.0.0" -ErrorAction Ignore).LocalPort
    $usedTcpGlobalPorts | ForEach-Object { $tcpRangesArray += [pscustomobject]@{P1 = $_; P2 = $_} }
    # Sort the list and remove duplicates
    $tcpRangesArray = ($tcpRangesArray | Sort-Object { $_.P1 } -Unique)

    $tcpRangesList = New-Object System.Collections.ArrayList($null)
    $tcpRangesList.AddRange($tcpRangesArray)

    # Remove overlapping ranges
    for ($i = $tcpRangesList.P1.Length - 2; $i -gt 0 ; $i--) { 
        if ($tcpRangesList[$i].P2 -gt $tcpRangesList[$i+1].P1 ) { 
            Write-Host "Removing $($tcpRangesList[$i+1])"
            $tcpRangesList.Remove($tcpRangesList[$i+1])
            $i++
        } 
    }

    # Remove the non-ephemeral port reservations from the list
    $filteredTcpRangeArray = $tcpRangesList | Where-Object { $_.P1 -ge $EphemeralPortStart }
    $filteredTcpRangeArray = $filteredTcpRangeArray | Where-Object { $_.P2 -le $EphemeralPortEnd }
    
    if ($null -eq $filteredTcpRangeArray) {
        $freeRanges = @($EphemeralPortRange[1])
    } else {
        $freeRanges = @()
        # The first free range goes from $EphemeralPortStart to the beginning of the first reserved range
        $freeRanges += ([Convert]::ToUInt32($filteredTcpRangeArray[0].P1) - $EphemeralPortStart)

        for ($i = 1; $i -lt $filteredTcpRangeArray.length; $i++) {
            # Subsequent free ranges go from the end of the previous reserved range to the beginning of the current reserved range
            $freeRanges += ([Convert]::ToUInt32($filteredTcpRangeArray[$i].P1) - [Convert]::ToUInt32($filteredTcpRangeArray[$i-1].P2) - 1)
        }

        # The last free range goes from the end of the last reserved range to $EphemeralPortEnd
        $freeRanges += ($EphemeralPortEnd - [Convert]::ToUInt32($filteredTcpRangeArray[$filteredTcpRangeArray.length - 1].P2))
    }
    
    # Count the number of available free ranges
    [uint32]$freeRangesCount = 0
    ($freeRanges | ForEach-Object { $freeRangesCount += [Math]::Floor($_ / $portRangeSize) } )

    return $freeRangesCount
}

$availableRangesFor64PortChunks = CountAvailableEphemeralPorts

if ($availableRangesFor64PortChunks -le 0) {
    "ERROR: Running out of ephemeral ports. The ephemeral ports range doesn't have enough resources to allow allocating 64 contiguous TCP ports.`n" > reservedports.txt
} else {
    # There is unfortunately no exact way to calculate the ephemeral port ranges availability. 
    # The calculation done in this script gives a very coarse estimate that may yield overly optimistic reasults on some systems.
    # Use this data with caution.
    "Rough estimation of the ephemeral port availability: up to $availableRangesFor64PortChunks allocations of 64 contiguous TCP ports may be possible.`n" > reservedports.txt
}

# The following scripts attempts to reserve a few ranges of 64 ephemeral ports. 
# Results produced by this test can accurately tell whether a system has room for reserving 64 contiguous port pools or not.
Write-Verbose "BaseDir: $BaseDir"
& "$BaseDir\PortReservationTest.ps1" >> reservedports.txt

netsh int ipv4 sh excludedportrange TCP > excludedportrange.txt
netsh int ipv4 sh excludedportrange UDP >> excludedportrange.txt

# it's possible to set the dynamic port range by TCP profile, so collect dynamic ports by TCP settings profile
Get-NetTCPSetting | Select-Object SettingName, DynamicPort* > dynamicportrange.txt
Get-NetUDPSetting >> dynamicportrange.txt
netsh int ipv4 sh dynamicportrange TCP >> dynamicportrange.txt
netsh int ipv4 sh dynamicportrange UDP >> dynamicportrange.txt

Write-Verbose "Get-SdnLogs - Connection details"
"TCP Connections:`n" > tcpconnections.txt
#Get-NetTCPConnection >> tcpconnections.txt

# Gets the TCP connections and attach the process name
$processes = Get-Process | Select-Object Id, ProcessName, Name
$serviceList = Get-WmiObject -Class Win32_Service | Select-Object ProcessId, Name
$netConn = Get-NetTCPConnection | Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,State,AppliedSetting,OwningProcess
$netConn | Add-Member -MemberType NoteProperty -Name ProcessName -Value "Not found"

foreach ($conn in $netConn)
{

    # get the process details
    $tmpProcess = $processes | & { process {if ($_.Id -eq $conn.OwningProcess) { $_ }}}

    # resolve the services if this is a svchost
    if ($tmpProcess.Name -eq 'svchost')
    {
        $svchost = ($serviceList | & { process {if ($_.ProcessId -eq $conn.OwningProcess) { $_ } }} | & {process {$_.Name}}) -join ','
        $conn.ProcessName = "$($tmpProcess.ProcessName) `($svchost`)"
    }else
    {            
        $conn.ProcessName = $tmpProcess.ProcessName
    }

    $tmpProcess = $null
    $svchost = $null
}

$netConn | Format-List -Property LocalAddress,LocalPort,RemoteAddress,RemotePort,State,AppliedSetting,OwningProcess,ProcessName >> tcpconnections.txt

"`nTCP again, but old school:`n" >> tcpconnections.txt
netsh int ipv4 sh tcpconnections >> tcpconnections.txt

"`nUDP Endpoints:`n" >> udpendpoints.txt
Get-NetUDPEndpoint | Select-Object LocalAddress, LocalPort, OwningProcess >> udpendpoints.txt

Write-Verbose "Get-SdnLogs - System details"
$ver = [System.Environment]::OSVersion
$hotFix = Get-HotFix

$ver.ToString() > winver.txt
"`n`n" >> winver.txt

if ($null -ne $hotFix)
{
    $hotFix >> winver.txt
} else {
    "<No hotfix>" >> winver.txt
}

# Copy the Windows event logs
Write-Verbose "Get-SdnLogs - Collecting logs"
New-Item -Path winevt -ItemType Directory
Copy-Item "$env:SystemDrive\Windows\System32\Winevt\Logs\Application.evtx" -Destination winevt
Copy-Item "$env:SystemDrive\Windows\System32\Winevt\Logs\System.evtx" -Destination winevt
Copy-Item "$env:SystemDrive\Windows\System32\Winevt\Logs\\Microsoft-Windows-Hyper-V*.evtx" -Destination winevt
Copy-Item "$env:SystemDrive\Windows\System32\Winevt\Logs\Microsoft-Windows-Host-Network-Service*.evtx" -Destination winevt

# get logs
New-Item -Path logs -ItemType Directory
Copy-Item "$env:SystemDrive\Windows\logs\NetSetup" -Destination logs -Recurse
Copy-Item "$env:SystemDrive\Windows\logs\dism" -Destination logs -Recurse
Copy-Item "$env:SystemDrive\Windows\logs\cbs" -Destination logs -Recurse

Pop-Location
Write-Host "Logs are available at $outDir"
