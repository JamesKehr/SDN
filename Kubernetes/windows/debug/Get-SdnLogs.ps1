#requires -RunAsAdministrator
#requires -Version 5.1

[CmdletBinding()]
param()


##### Setup variables #####

$env:GITHUB_SDN_REPOSITORY = 'JamesKehr/SDN/collectlogs_update'
$GithubSDNRepository = 'Microsoft/SDN/master'

if ((Test-Path env:GITHUB_SDN_REPOSITORY) -and ($env:GITHUB_SDN_REPOSITORY -ne ''))
{
    $GithubSDNRepository = $env:GITHUB_SDN_REPOSITORY
}

$BaseDir = "C:\k\debug"
$helper = "$BaseDir\DebugHelper.psm1"

# pwsh 5 or 7?
$pwshVer = $host.Version.Major


##### Do work #####

try 
{
    if (-NOT (Test-Path "$BaseDir" -EA Stop))
    {
        $null = mkdir $BaseDir -Force -ErrorAction Stop
    }
}
catch 
{
    return ( Write-Error "Failed to create the base directory, $BaseDir. Please verify user permissions to the C: drive. Error: $_" -EA Stop )
}


# newer versions of pwsh support -UseBasicParsing, but leaving this here in case someone hasn't updated in a while
if (-NOT (Test-Path $helper))
{
    switch ($pwshVer)
    {
        5 { Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/$GithubSDNRepository/Kubernetes/windows/debug/DebugHelper.psm1" -OutFile "$BaseDir\DebugHelper.psm1" }
        7 { Invoke-WebRequest "https://raw.githubusercontent.com/$GithubSDNRepository/Kubernetes/windows/helper.psm1" -OutFile "$BaseDir\helper.psm1" }
    }
}

try 
{
    $null = Import-Module -Name "$BaseDir\DebugHelper.psm1" -Verbose -EA Stop
}
catch 
{
    return (Write-Error "Could not load helper file: $_" -EA Stop)
}


# support files that need to be downloaded
Get-WebFile -Url "https://raw.githubusercontent.com/$GithubSDNRepository/Kubernetes/windows/debug/dumpVfpPolicies.ps1" -Destination $BaseDir\dumpVfpPolicies.ps1
Get-WebFile -Url "https://raw.githubusercontent.com/$GithubSDNRepository/Kubernetes/windows/debug/hns.psm1" -Destination $BaseDir\hns.psm1 -Force
Get-WebFile -Url "https://raw.githubusercontent.com/$GithubSDNRepository/Kubernetes/windows/debug/starthnstrace.cmd" -Destination $BaseDir\starthnstrace.cmd
Get-WebFile -Url "https://raw.githubusercontent.com/$GithubSDNRepository/Kubernetes/windows/debug/starthnstrace.ps1" -Destination $BaseDir\starthnstrace.ps1
Get-WebFile -Url "https://raw.githubusercontent.com/$GithubSDNRepository/Kubernetes/windows/debug/startpacketcapture.cmd" -Destination $BaseDir\startpacketcapture.cmd
Get-WebFile -Url "https://raw.githubusercontent.com/$GithubSDNRepository/Kubernetes/windows/debug/startpacketcapture.ps1" -Destination $BaseDir\stoppacketcapture.ps1
Get-WebFile -Url "https://raw.githubusercontent.com/$GithubSDNRepository/Kubernetes/windows/debug/portReservationTest.ps1" -Destination $BaseDir\portReservationTest.ps1

# import the HNS module if it's not already installed
$hnsModFnd = Get-Command Get-HnsNetwork -EA SilentlyContinue
if (-NOT $hnsModFnd)
{
    Import-Module $BaseDir\hns.psm1
}

try
{
    # this will fail if executing the script directly from github...
    [string]$ScriptPath = Split-Path $MyInvocation.MyCommand.Path -EA Stop
}
catch
{
    # ...set scriptpath to present working directory when that happens
    [string]$ScriptPath = $PWD.Path
}


#$outDir = [io.Path]::Combine($ScriptPath, [io.Path]::GetRandomFileName())
$outDir = "$ScriptPath\SdnLogs_$env:COMPUTERNAME_$(Get-Date -Format "yyyyMMdd_HHmmss")"

try
{
    $null = mkdir "$outDir" -Force -EA Stop
}
catch
{
    return ( Write-Error "Failed to create the output directory. Please verify user permissions to the $ScriptPath directory. Error: $_" -EA Stop )
}

Push-Location "$outDir"

# HNS network details
Get-HnsNetwork | Select-Object Name, Type, Id, AddressPrefix > hnsnetwork.txt
Get-HnsNetwork | ConvertTo-Json -Depth 20 > hnsnetwork.json
Get-HnsNetwork | ForEach-Object { Get-HnsNetwork -Id $_.ID -Detailed } | ConvertTo-Json -Depth 20 > hnsnetworkdetailed.json

# HNS endpoint details
Get-HnsEndpoint | Select-Object IpAddress, MacAddress, IsRemoteEndpoint, State > hnsendpoint.txt
Get-HnsEndpoint | ConvertTo-Json -Depth 20 > hnsendpoint.json

# HNS policy details
Get-HnsPolicyList | ConvertTo-Json -Depth 20 > hnspolicy.json

# get vmSwitch port info
$vfpctrlFnd = Get-Command vfpctrl.exe -EA SilentlyContinue
if ($vfpctrlFnd)
{
    vfpctrl.exe /list-vmswitch-port > VMSports.txt
}
else 
{
    Write-Verbose "Get-SdnLogs - vfpctrl.exe was not found. Skipping VMSports.txt."    
}

# dump all VFP policies
Push-Location $BaseDir
[array]$vmSwitches = Get-VMSwitch -EA SilentlyContinue
foreach ($vmSwitch in $vmSwitches)
{
    .\dumpVfpPolicies.ps1 -switchName $vmSwitch -outfile "$outDir\vfpOutput_$($vmSwitch.Name).txt"
}
Pop-Location

# host network configuration
ipconfig /allcompartments /all > ip.txt
Get-NetIPAddress -IncludeAllCompartments | Select-Object IPAddress, InterfaceIndex, InterfaceAlias, AddressFamily, Type, PrefixLength, SkipAsSource >> ip.txt

Get-NetAdapter | Select-Object Name, InterfaceDescription, InterfaceIndex | Format-Table -AutoSize > routes.txt
Get-NetRoute -IncludeAllCompartments | Select-Object ifIndex, DestinationPrefix, NextHop, RouteMetric, @{Name="ifMetric"; Expression={$_.InterfaceMetric}}, @{Name="TotalMetric"; Expression={ ($_.RouteMetric + $_.InterfaceMetric) }} | Sort-Object -Property IfIndex | Format-Table -AutoSize >> routes.txt
route print >> routes.txt

Get-NetIPInterface > mtu.txt
netsh int ipv4 sh int >> mtu.txt

nvspinfo -a -i -h -D -p -d -m -q > nvspinfo.txt
nmscrub -a -n -t > nmscrub.txt

Get-NetAdapter | Select-Object Name, InterfaceDescription, InterfaceIndex | Format-Table -AutoSize > arp.txt
Get-NetNeighbor -IncludeAllCompartments >> arp.txt
arp -a >> arp.txt

#Get-NetAdapter | ForEach-Object {$ifindex=$_.IfIndex; $ifName=$_.Name; netsh int ipv4 sh int $ifindex | Out-File  -FilePath "${ifName}_int.txt" -Encoding ascii}
Get-NetAdapter | ForEach-Object { $_ | Format-List * | Out-File "$($_.Name)_int.txt" -Encoding ascii }


$res = Get-Command hnsdiag.exe -ErrorAction SilentlyContinue
if ($res)
{
    hnsdiag list all -d > hnsdiag.json
    hnsdiag list adapters *> hnsdiag.adapters.txt
    hcsdiag list  > hcsdiag.txt
}

$res = Get-Command docker.exe -ErrorAction SilentlyContinue
if ($res)
{
    docker ps -a > docker.txt
}

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
& "$BaseDir\PortReservationTest.ps1" >> reservedports.txt

netsh int ipv4 sh excludedportrange TCP > excludedportrange.txt
netsh int ipv4 sh excludedportrange UDP >> excludedportrange.txt

# it's possible to set the dynamic port range by TCP profile, so collect dynamic ports by TCP settings profile
Get-NetTCPSetting | Select-Object SettingName, DynamicPort* > dynamicportrange.txt
Get-NetUDPSetting >> dynamicportrange.txt
netsh int ipv4 sh dynamicportrange TCP >> dynamicportrange.txt
netsh int ipv4 sh dynamicportrange UDP >> dynamicportrange.txt


"TCP Connections:`n" > tcpconnections.txt
Get-NetTCPConnection >> tcpconnections.txt
"`nTCP again, but old school:`n" >> tcpconnections.txt
netsh int ipv4 sh tcpconnections >> tcpconnections.txt

"`nUDP Endpoints:`n" >> udpendpoints.txt
Get-NetUDPEndpoint | Select-Object LocalAddress, LocalPort, OwningProcess >> udpendpoints.txt


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
Copy-Item "$env:SystemDrive\Windows\System32\Winevt\Logs\Application.evtx"
Copy-Item "$env:SystemDrive\Windows\System32\Winevt\Logs\System.evtx"
Copy-Item "$env:SystemDrive\Windows\System32\Winevt\Logs\Microsoft-Windows-Hyper-V*.evtx"
Copy-Item "$env:SystemDrive\Windows\System32\Winevt\Logs\Microsoft-Windows-Host-Network-Service*.evtx"

Pop-Location
Write-Host "Logs are available at $outDir"
