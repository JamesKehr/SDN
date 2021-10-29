[CmdletBinding()]
param
(
    # Path with filename where the ETL file will be saved. Format: <path>\<filename>.etl
    [string]
    $EtlFile = "C:\server.etl",

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

## FUNCTIONS ##

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

    #return $Destination
}


## CONSTANTS ##
# look for the provider file
$providerFilename = "PROVIDERS_HnsTrace.json"


$env:GITHUB_SDN_REPOSITORY = 'JamesKehr/SDN/collectlogs_update'
$GithubSDNRepository = 'Microsoft/SDN/master'

if ((Test-Path env:GITHUB_SDN_REPOSITORY) -and ($env:GITHUB_SDN_REPOSITORY -ne ''))
{
    $GithubSDNRepository = $env:GITHUB_SDN_REPOSITORY
}

# default file download location
$BaseDir = "C:\k\debug"


##### Do prep work #####

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

# support files needed to start trace
if ($NoInternet.IsPresent)
{
    # look for the required files in BaseDir
    $traceFnd = Get-Item "$BaseDir\Start-Trace.ps1" -EA SilentlyContinue
    $provFnd = Get-Item "$BaseDir\$providerFilename" -EA SilentlyContinue

    if (-NOT $traceFnd -and -NOT $provFnd)
    {
        # look for the required files in PWD
        $traceFnd = Get-Item .\Start-Trace.ps1 -EA SilentlyContinue
        $provFnd = Get-Item ".\$providerFilename" -EA SilentlyContinue

        if ($traceFnd -and $provFnd)
        {
            $BaseDir = $PWD.Path
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
                    $BaseDir = $PSScriptRoot
                }
                else 
                {
                    return ( Write-Error "Failed to find the requierd trace files when -NoInternet is set." -EA Stop )
                }
            }
            else 
            {
                return ( Write-Error "Failed to find the requierd trace files when -NoInternet is set." -EA Stop )
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
    EtlFile      = $EtlFile
    snapLen      = $snapLen
    maxFileSize  = $maxFileSize
    NoPrompt     = $NoPrompt
    NoPackets    = $NoPackets
    NoLogs       = $NoLogs
}

Push-Location $BaseDir
.\Start-Trace.ps1 @paramSplat
Pop-Location
