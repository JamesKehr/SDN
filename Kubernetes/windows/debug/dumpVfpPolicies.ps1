param(
   [string]$switchName = $(throw "please specify a switch name"),
   [string]$outfile = "vfprules.txt"
  )

# load SdnCommon
if (-NOT $script:SdnCommonLoaded)
{
  Write-Verbose "dumpVfpPolicies - Loading SdnCommon"
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

$ports = Get-VfpPorts -SwitchName $switchName

# Dump the port info
$ports | Select-Object 'Port name', 'Mac Address', 'PortId' | Out-File $outfile -Encoding ascii -Append

$vfpCtrlExe = "vfpctrl.exe"

foreach ($port in $ports) {
	$portGuid = $port.'Port name'
	Write-Host "Policy for port : " $portGuid  | Out-File $outfile -Encoding ascii -Append
	& $vfpCtrlExe /list-space  /port $portGuid | Out-File $outfile -Encoding ascii -Append
	& $vfpCtrlExe /list-mapping  /port $portGuid | Out-File $outfile -Encoding ascii -Append
	& $vfpCtrlExe /list-rule  /port $portGuid | Out-File $outfile -Encoding ascii -Append
	& $vfpCtrlExe /port $portGuid /get-port-state | Out-File $outfile -Encoding ascii -Append
	& $vfpCtrlExe /port $portGuid /list-nat-range | Out-File $outfile -Encoding ascii -Append
}

& $vfpCtrlExe /switch $ports[0].'Switch Name'  /get-switch-forwarding-settings > vswitchForwarding.txt