[CmdletBinding()]
param
(
    # Path with filename where the ETL file will be saved. Format: <path>\<filename>.etl
    [string]
    $EtlFilename = "$ENV:ComputerName`_HnsTrace.etl",

    # How many bytes of the packet to collect. Default is 256 bytes to collect encapsulated headers.
    [int]
    $snapLen = 256,

    # Maximum file size in megabytes. 0 means that there is no maximum
    [int]
    $maxFileSize = 500,

    # Does not prompt/pause execution and wait on user input.
    [switch]
    $NoPrompt,

    # Does not collect network packets.
    [switch]
    $NoPackets,

    # Collects logs after user presses q to stop tracing. Ignored when -NoPrompt set.
    [switch]
    $NoLogs,

    [switch]
    $NoInternet
)

## CONSTANTS ##
# look for the provider file
$providerFilename = "PROVIDERS_HnsTrace.json"


## FUNCTIONS ##

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

# support files needed to start trace
if ($NoInternet.IsPresent)
{
    if (-NOT $Global:BaseDir)
    {
        $Global:BaseDir = "C:\k\debug"
    }

    # look for the required files in BaseDir
    $traceFnd = Get-Item "$Global:BaseDir\Start-Trace.ps1" -EA SilentlyContinue
    $provFnd = Get-Item "$Global:BaseDir\$providerFilename" -EA SilentlyContinue

    if (-NOT $traceFnd -and -NOT $provFnd)
    {
        # look for the required files in PWD
        $traceFnd = Get-Item .\Start-Trace.ps1 -EA SilentlyContinue
        $provFnd = Get-Item ".\$providerFilename" -EA SilentlyContinue

        if ($traceFnd -and $provFnd)
        {
            $Global:BaseDir = $PWD.Path
        }
        else 
        {
            # look in $PSScriptRoot inb case it's different than $PWD
            if ($PSScriptRoot)
            {
                $traceFnd = Get-Item "$PSScriptRoot\Start-Trace.ps1" -EA SilentlyContinue
                $provFnd = Get-Item "$PSScriptRoot\$providerFilename" -EA SilentlyContinue
                
                if ($traceFnd -and $provFnd)
                {
                    $Global:BaseDir = $PSScriptRoot
                }
                else 
                {
                    return ( Write-Error "Failed to find the requierd trace files while -NoInternet is set." -EA Stop )
                }
            }
            else 
            {
                return ( Write-Error "Failed to find the requierd trace files and -NoInternet is set." -EA Stop )
            }
        }
    }
}
else 
{
    # downloaded the newest copy of the files
    try
    {
        Get-WebFile -Url "https://raw.githubusercontent.com/$GithubSDNRepository/Kubernetes/windows/debug/Start-Trace.ps1" -Destination $BaseDir\Start-Trace.ps1 -Force -EA Stop
        Get-WebFile -Url "https://raw.githubusercontent.com/$GithubSDNRepository/Kubernetes/windows/debug/$providerFilename" -Destination "$BaseDir\$providerFilename" -Force -EA Stop
    }
    catch
    {
        return ( Write-Error "Unable to download or find the required trace files. Please manually download Start-Trace.ps1 and $providerFilename and try again: $_" -EA Stop )
    }    
}



## Execute Trace ##

$paramSplat = @{
    ProviderFile = "$BaseDir\$providerFilename"
    EtlFile      = $EtlFilename
    snapLen      = $snapLen
    maxFileSize  = $maxFileSize
    NoPrompt     = $NoPrompt
    NoPackets    = $NoPackets
    NoLogs       = $NoLogs
}

Push-Location $BaseDir
.\Start-Trace.ps1 @paramSplat
Pop-Location
