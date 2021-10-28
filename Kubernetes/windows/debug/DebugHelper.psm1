# Helper functions for Get-SdnLogs and other debug scripts

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


Export-ModuleMember -Function Get-WebFile