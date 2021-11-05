param(
   [string]$switchName = $(throw "please specify a switch name"),
   [string]$outfile = "vfprules.txt"
  )

  $env:GITHUB_SDN_REPOSITORY = 'JamesKehr/SDN/collectlogs_update'
  $GithubSDNRepository = 'Microsoft/SDN/master'
  
  if ((Test-Path env:GITHUB_SDN_REPOSITORY) -and ($env:GITHUB_SDN_REPOSITORY -ne ''))
  {
	  $GithubSDNRepository = $env:GITHUB_SDN_REPOSITORY
  }

$BaseDir = "c:\k\debug"
mkdir $BaseDir -ErrorAction Ignore

$helper = "$BaseDir\DebugHelper.psm1"
if (!(Test-Path $helper))
{
    Start-BitsTransfer "https://raw.githubusercontent.com/$GithubSDNRepository/Kubernetes/windows/debug/DegubHelper.psm1" -Destination $BaseDir\DebugHelper.psm1
}
Import-Module $helper

Get-WebFile -Url "https://raw.githubusercontent.com/$GithubSDNRepository/Kubernetes/windows/debug/VFP.psm1" -Destination $BaseDir\VFP.psm1
Import-Module $BaseDir\VFP.psm1

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