[CmdletBinding()]
param
(
    # The provider list used for ETL collection.
    [Parameter(Mandatory=$true)]
    $ProviderFile,

    # Path with filename where the ETL file will be saved. Format: <path>\<filename>.etl
    [string]
    $EtlFile = "C:\server.etl",

    # How many bytes of the packet to collect. Default is 256 bytes to collect encapsulated headers.
    [int]
    $snapLen = 256,

    # Maximum file size in megabytes. 0 means that there is no maximum
    [int]
    $maxFileSize = 250,

    # Does not prompt/pause execution and wait on user input.
    [switch]
    $NoPrompt,

    # Does not collect network packets.
    [switch]
    $NoPackets,

    # Collects logs after user presses q to stop tracing. Ignored when -NoPrompt set.
    [switch]
    $NoLogs
)

### CLASSES AND FUNCTIONS ###
#region


# Data structure for ETW providers.
# This implementation requires the use of the ETW GUID. 
# Everything else is optional with default values for level and keywords.
class Provider
{
    # [Optional w/ GUID] ETW name
    [string]$Name
    # [Optional w/ Name] ETW GUID - Recommended! ETW name doesn't always resolve properly, GUID always does.
    [guid]$GUID
    # [Optional] Logging level. Default = [byte]::MaxValue (0xff)
    [byte]$Level
    # [Optional] Logging keywords. Default = [UInt64]::MaxValue (0xffffffffffffffff)
    [uint64]$MatchAnyKeyword

    # supported methods of creating a provider object
    #region

    # all properties
    Provider(
        [string]$Name,
        [guid]$GUID,
        [byte]$Level,
        [uint64]$MatchAnyKeyword
    )
    {
        $this.Name              = $Name
        $this.GUID              = $GUID
        $this.Level             = $level
        $this.MatchAnyKeyword   = $MatchAnyKeyword
    }

    # all but the Name property
    Provider(
        [guid]$GUID,
        [byte]$Level,
        [uint64]$MatchAnyKeyword
    )
    {
        $this.Name              = ""
        $this.GUID              = $GUID
        $this.Level             = $level
        $this.MatchAnyKeyword   = $MatchAnyKeyword
    }

    # GUID and level property
    Provider(
        [guid]$GUID,
        [byte]$Level
    )
    {
        $this.Name              = ""
        $this.GUID              = $GUID
        $this.Level             = $level
        $this.MatchAnyKeyword   = [UInt64]::MaxValue
    }

    # GUID, name, and level property
    Provider(
        [string]$Name,
        [guid]$GUID,
        [byte]$Level
    )
    {
        $this.Name              = $Name
        $this.GUID              = $GUID
        $this.Level             = $level
        $this.MatchAnyKeyword   = [UInt64]::MaxValue
    }

    # only GUID
    Provider(
        [guid]$GUID
    )
    {
        $this.Name              = ""
        $this.GUID              = $GUID
        $this.Level             = [byte]::MaxValue
        $this.MatchAnyKeyword   = [UInt64]::MaxValue
    }

    #endregion Provider()
}

function Get-WebFile
{
    param(
        [parameter(Mandatory = $true)] 
        [string]
        $Url,
        
        [parameter(Mandatory = $true)]
        [string]
        $Destination,

        [parameter(Mandatory = $false)]
        [switch]
        $Force
    )

    # Write-Verbose "Get-WebFile - "
    Write-Verbose "Get-WebFile - Start"

    if ((Test-Path $Destination) -and -NOT $Force.IsPresent )
    {
        Write-Verbose "File $Destination already exists."
        return
    }

    # Github and other sites do not allow versions of TLS/SSL older than TLS 1.2.
    # This block forces PowerShell to use TLS 1.2+.
    if ([System.Net.ServicePointManager]::SecurityProtocol -contains 'SystemDefault' -or  [System.Net.ServicePointManager]::SecurityProtocol -contains 'Tls11')
    {
        Write-Verbose "Get-WebFile - Enforcing TLS 1.2+ for the secure download."
        $secureProtocols = @() 

        # Exclude all cipher protocols older than TLS 1.2.
        $insecureProtocols = @( [System.Net.SecurityProtocolType]::SystemDefault, 
                                [System.Net.SecurityProtocolType]::Ssl3, 
                                [System.Net.SecurityProtocolType]::Tls, 
                                [System.Net.SecurityProtocolType]::Tls11)

        foreach ($protocol in [System.Enum]::GetValues([System.Net.SecurityProtocolType])) 
        { 
            if ($insecureProtocols -notcontains $protocol) 
            { 
                $secureProtocols += $protocol 
            } 
        } 

        [System.Net.ServicePointManager]::SecurityProtocol = $secureProtocols
    }
    
    
    try {
        (New-Object System.Net.WebClient).DownloadFile($Url,$Destination)
        Write-Verbose "Get-WebFile - Downloaded $Url => $Destination"
    } catch {
        return ( Write-Error "Failed to download $Url`: $_" -EA Stop )
    }
}

#endregion CLASSES and FUNCTIONS


### CONSTANTS and VARIABLES ###
#region

# load SdnCommon - this is the first step in all debug PowerShell scripts
if (-NOT $SdnCommonLoaded)
{
    Write-Verbose "Get-SdnLogs - Loading SdnCommon"
    # can github be reached?
    $pngGH = Test-NetConnection github.com -Port 443 -InformationLevel Quiet -EA SilentlyContinue

    if ($pngGH)
    {
        #$cmnURL = 'https://raw.githubusercontent.com/microsoft/SDN/master/Kubernetes/windows/debug/SdnCommon.ps1'
        $cmnURL = 'https://raw.githubusercontent.com/JamesKehr/SDN/collectlogs_update/Kubernetes/windows/debug/SdnCommon.ps1'

        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12, [System.Net.SecurityProtocolType]::Tls13
        Invoke-WebRequest $cmnURL -OutFile "$($PWD.Path)\SdnCommon.ps1" -UseBasicParsing
    }
    
    $sdncmnFnd = Get-Item "$($PWD.Path)\SdnCommon.ps1" -EA SilentlyContinue
    if ( -NOT $sdncmnFnd)
    {
        $sdncmnFnd = Get-Item "C:\k\debug\SdnCommon.ps1" -EA SilentlyContinue
        
        if ( -NOT $sdncmnFnd)
        {
            return ( Write-Error "Failed to download or find SdnCommon.ps1." -EA Stop)
        }
    }

    Push-Location $sdncmnFnd.Directory
    if ($pngGH)
    {
        & ".\SdnCommon.ps1"
    }
    else
    {
        & ".\SdnCommon.ps1 -NoInternet"
    }
    Pop-Location
}
                        
# capture name
$sessionName = 'HnsCapture'

#endregion CONSTANTS and VARIABLES


### MAIN ###

# collect providers from file
$Providers = New-Object System.Collections.ArrayList
[System.Collections.ArrayList]$rawProviders = Get-Content $ProviderFile -Force | ConvertFrom-Json -Depth 10

# process the file
foreach ($p in $rawProviders)
{
    if ( [string]::IsNullOrEmpty($p.Keywords) )
    {
        $tmpP = [Provider]::New($p.Name, [guid]$p.GUID, $p.Level)
        
    }
    else 
    {
        $tmpP = [Provider]::New($p.Name, [guid]$p.GUID, $p.Level, $p.Keywords)
    }

    if ($tmpP -is [Provider])
    {
        $null = $Providers.Add( $tmpP )
    }
    else
    {
        Write-Warning "Failed to create Provider from file: $tmpP"
    }  
}

# make sure there is at least one provider in the list
if ($Providers.Count -eq 0)
{
    return ( Write-Error "Failed to process $ProviderFile`. Providers count is zero." -EA Stop ) 
}

#
# Stop any existing session and create a new session
#
Write-Debug "Cleaning up any failed $sessionName sessions."
Stop-NetEventSession $sessionName -ErrorAction Ignore | Out-Null
Remove-NetEventSession $sessionName -ErrorAction Ignore | Out-Null

#
# create capture session
#
try
{
    Write-Verbose "Creating the $sessionName capture session."
    New-NetEventSession $sessionName -CaptureMode SaveToFile -MaxFileSize $maxFileSize -LocalFilePath $EtlFile -EA Stop | Out-Null
}
catch
{
    return (Write-Error "Failed to create the NetEventSession: $_" -EA Stop)
}

#
# add packet capture only when -GetPackets used
#
if (-NOT $NoPackets.IsPresent)
{
    Write-Verbose "Adding packet capture."
    Add-NetEventPacketCaptureProvider -SessionName $sessionName -TruncationLength $snapLen | Out-Null
}

#
# add ETW providers
#
foreach ($provider in $Providers)
{
    try 
    {
        Write-Verbose "Adding $($provider.GUID) $(if ($provider.Name) {"($($provider.Name))"})"
        Add-NetEventProvider -SessionName $sessionName -Name "{$($provider.GUID)}" -Level $provider.Level -MatchAnyKeyword $provider.MatchAnyKeyword -EA Stop | Out-Null
    } 
    catch 
    {
        Write-Warning "Could not add provider $($provider.GUID) $(if ($provider.Name) {"($($provider.Name))"})`: $_"
    }
}

#
# Start the session and optionally wait for the user to stop the session
#
Write-Verbose "Starting capture session."
try
{
    Start-NetEventSession $sessionName -EA Stop
    Write-Debug "Capture session successfully started."
}
catch
{
    return (Write-Error "Failed to start the NetEventSession: $_" -EA Stop)
}


# Prompt if -NoPrompt is not present
# Two negatives make a positive, it's the Microsoft way!
if (-NOT $NoPrompt.IsPresent)
{
    # repro the issue then press q to stop the trace
    Write-Host -ForegroundColor Green "`n`The data collection has started.`n`nReproduce the issue now and then press 'q' to stop tracing.`n`n"

    do 
    {
        $x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } until ($x.Character -eq 'q')

    # stop tracing
    Write-Verbose "Stopping $sessionName."
    Stop-NetEventSession $sessionName | Out-Null
    Remove-NetEventSession $sessionName | Out-Null

    # run Get-SdnLogs.ps1 when -CollectLogs set
    if (-NOT $NoLogs.IsPresent)
    {
        Write-Verbose "Trying to run Get-SdnLogs.ps1"

        # is Get-SdnLogs.ps1 in $BaseDir?
        $isCLFnd = Get-Item "$BaseDir\Get-SdnLogs.ps1" -EA SilentlyContinue

        if (-NOT $isCLFnd)
        {
            Write-Verbose "Get-SdnLogs.ps1 not found. Attempting to download."
            # try to download Get-SdnLogs.ps1
            try 
            {
                #$URLSdnLogs = 'https://raw.githubusercontent.com/microsoft/SDN/master/Kubernetes/windows/debug/Get-SdnLogs.ps1'
                $URLSdnLogs = 'https://raw.githubusercontent.com/JamesKehr/SDN/collectlogs_update/Kubernetes/windows/debug/Get-SdnLogs.ps1'
                Get-WebFile -Url $URLSdnLogs -Destination "$BaseDir\Get-SdnLogs.ps1" -Force -EA Stop
            }
            catch 
            {
                Write-Warning "The trace was successful but Get-SdnLogs failed to download: $_"
            }
        }

        # execute Get-SdnLogs.ps1
        Write-Host "Running Get-SdnLogs.ps1."
        # redirecting as much of the collectlog output to the success stream for collection
        Push-Location $BaseDir
        .\Get-SdnLogs.ps1
        Pop-Location
    }

    Write-Host -ForegroundColor Green "`n`nAll done! The data is located at:`n`t- $EtlFile $(if ($clResults) {"`n`t- $($clResults[-1].Substring(22))"})"
}
else
{
    Write-Host -ForegroundColor Yellow "Use this command to stop capture: Stop-NetEventSession $sessionName"
    Write-Host -ForegroundColor Yellow "Use this command to remove capture: Remove-NetEventSession $sessionName"
    Write-Host -ForegroundColor Yellow "The data file will be located at $EtlFile."
}