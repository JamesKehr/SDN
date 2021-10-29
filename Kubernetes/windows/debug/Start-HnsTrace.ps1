#[CmdletBinding()]
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
    $CollectLogs
)

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
$helper = "$BaseDir\DebugHelper.psm1"

# pwsh 5 or 7?
$pwshVer = $host.Version.Major



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
    $null = Import-Module $helper -EA Stop    
}
catch 
{
    return (Write-Error "Could not load helper file: $_" -EA Stop)
}


# support files needed to start trace
try
{
    Get-WebFile -Url "https://raw.githubusercontent.com/$GithubSDNRepository/Kubernetes/windows/debug/Start-Trace.ps1" -Destination $BaseDir\Start-Trace.ps1 -EA Stop
    Get-WebFile -Url "https://raw.githubusercontent.com/$GithubSDNRepository/Kubernetes/windows/debug/$providerFilename" -Destination "$BaseDir\$providerFilename" -EA Stop
}
catch
{
    return ( Write-Error "Unable to download or find the required trace files. Please manually download Start-Trace.ps1 and $providerFilename and try again: $_" -EA Stop )
}





## Execute Trace ##

$paramSplat = @{
    ProviderFile = "$BaseDir\$providerFilename"
    EtlFile      = $EtlFile
    snapLen      = $snapLen
    maxFileSize  = $maxFileSize
    NoPrompt     = $NoPrompt
    NoPackets    = $NoPackets
    CollectLogs  = $CollectLogs
}

Push-Location $BaseDir
.\Start-Trace.ps1 @paramSplat
Pop-Location
