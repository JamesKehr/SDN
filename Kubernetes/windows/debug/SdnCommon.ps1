# sets variables needed for SDN/k8s debug scripts.

param(
    [switch]$NoInternet
)

## FUNCTIONS ##
#region
# doownloads files from the Internet
function Script:Get-WebFile
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

function Get-GithubRepoFiles
{
    [CmdletBinding()]
    param(
        [string]$repo,
        [string]$branch = "master",
        [string]$pathFilter
    )

    Write-Verbose "Get-GithubRepoFiles - Begin"

    $baseApiUri = "https://api.github.com/repos/$repo/git/trees/$branch`?recursive=1"


    # get the available releases
    Write-Verbose "Get-GithubRepoFiles - Processing repro: $repo"
    Write-Verbose "Get-GithubRepoFiles - Making Github API call to: $baseApiUrl"
    try 
    {
        $raw = Invoke-RestMethod -Uri $baseApiUri -EA Stop
        $rawFile = $raw.tree | Where-Object type -eq "blob"

    }
    catch 
    {
        return (Write-Error "Could not get GitHub releases. Error: $_" -EA Stop)        
    }

    # filter content
    if (-NOT [string]::IsNullOrEmpty($pathFilter))
    {
        Write-Verbose "Get-GithubRepoFiles - Filtering results by `"$pathFilter`"."
        $rawFile = $rawFile | Where-Object Path -Match $pathFilter
    }

    Write-Verbose "Get-GithubRepoFiles - Returning $($rawFile.Count) results."
    Write-Verbose "Get-GithubRepoFiles - End"
    return $rawFile
}

#endregion



## MAIN ##

# informs other scripts whether SdnCommon has been run
#Write-Debug "SdnCommon - "
#Write-Verbose "SdnCommon - "

Write-Verbose "SdnCommon - Begin"
Write-Debug "SdnCommon - SdnCommonLoaded = false"
$script:SdnCommonLoaded = $false

# repo details
$env:GITHUB_SDN_REPOSITORY = 'JamesKehr/SDN/collectlogs_update'
$script:GithubSDNRepository = 'Microsoft/SDN/master'

if ((Test-Path env:GITHUB_SDN_REPOSITORY) -and ($env:GITHUB_SDN_REPOSITORY -ne ''))
{
    Write-Verbose "SdnCommon - Set repo to env:GITHUB_SDN_REPOSITORY: $env:GITHUB_SDN_REPOSITORY"
    $script:GithubSDNRepository = $env:GITHUB_SDN_REPOSITORY
}
Write-Verbose "SdnCommon - Repo: $script:GithubSDNRepository"

# default file download location
$script:BaseDir = "C:\k\debug"
Write-Debug "SdnCommon - BaseDir: $script:BaseDir"

# make sure BaseDir exists
try 
{
    if (-NOT (Test-Path "$BaseDir" -EA SilentlyContinue))
    {
        Write-Verbose "SdnCommon - Creating BaseDir."
        $null = mkdir $BaseDir -Force -ErrorAction Stop
    }
}
catch 
{
    return ( Write-Error "Failed to create the base directory, $BaseDir. Please verify user permissions to the C: drive. Error: $_" -EA Stop )
}


if (-NOT $NoInternet.IsPresent)
{
    # download all the debug files to BaseDir
    Write-Verbose "SdnCommon - Qurying "
    #$files = Get-GithubRepoFiles -repo $script:GithubSDNRepository -pathFilter "Kubernetes/windows/debug"
    $files = Get-GithubRepoFiles -repo "JamesKehr\SDN" -branch "collectlogs_update" -pathFilter "Kubernetes/windows/debug"

    Write-Verbose "SdnCommon - Downloading supporting files to $BaseDir"
    foreach ($file in $files)
    {    
        $tmpURL = "https://raw.githubusercontent.com/$script:GithubSDNRepository/$($file.path)"
        $tmpName = Split-Path $file.path -Leaf

        Write-Verbose "SdnCommon - Downloading $tmpName from $tmpUrl."

        try
        {
            Get-WebFile -Url $tmpURL -Destination "$script:BaseDir\$tmpName" -Force
        }
        catch
        {
            Write-Warning "Failed to download file ($tmpURL): $_"
        }

        Remove-Variable tmpURL, tmpName -EA SilentlyContinue
    }
}


# import the HNS module if it's not already installed
$hnsModFnd = Get-Command Get-HnsNetwork -EA SilentlyContinue
if (-NOT $hnsModFnd)
{
    Write-Verbose "SdnCommon - Importing HNS module from Github repo"
    try 
    {
        Import-Module $BaseDir\hns.psm1 -EA Stop    
    }
    catch 
    {
        return (Write-Error "Failed to import the HNS module: $_" -EA Stop)
    }
}

try
{
    # this will fail if executing the script directly from github...
    [string]$script:ScriptPath = Split-Path $MyInvocation.MyCommand.Path -EA Stop
}
catch
{
    # ...set scriptpath to present working directory when that happens
    [string]$script:ScriptPath = $PWD.Path
}
Write-Verbose "SdnCommon - ScriptPath: $script:ScriptPath"

#$outDir = [io.Path]::Combine($ScriptPath, [io.Path]::GetRandomFileName())
$script:outDir = "$script:ScriptPath\SdnLogs_$env:COMPUTERNAME_$(Get-Date -Format "yyyyMMdd_HHmmss")"

try
{
    $null = mkdir "$script:outDir" -Force -EA Stop
}
catch
{
    return ( Write-Error "Failed to create the output directory. Please verify user permissions to the $script:ScriptPath directory. Error: $_" -EA Stop )
}


Write-Debug "SdnCommon - Reached the end without ciritcal error. SdnCommonLoaded = true"
$script:SdnCommonLoaded = $true