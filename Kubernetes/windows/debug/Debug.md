1:[Log Collection]:

===================================================

Usage:

- Open an elevated Powershell console (Run as Administrator).

- Run: ```PowerShell Set-ExecutionPolicy Bypass```
  
- Execute the script using one of these two options.

Execute directly (support files will still be downloaded to C:\k\debug).
```PowerShell
Invoke-WebRequest https://raw.githubusercontent.com/microsoft/SDN/master/Kubernetes/windows/debug/Get-SdnLogs.ps1 -UseBasicParsing | Invoke-Expression
```
> Note: Older versions of PowerShell 7 may not accept -UseBasicParsing. Either upgrade to the latest version of PowerShell 7 or remove the parameter from the command.

Download and execute.
```PowerShell
Start-BitsTransfer https://raw.githubusercontent.com/microsoft/SDN/master/Kubernetes/windows/debug/collectlogs.ps1

.\Get-SdnLogs.ps1 
```

- The script will collect...
   - All the required logs to validate if all policies has been plumbed correctly.
   - The files will be stored in a folder named SdnLogs\_\<COMPUTERNAME\>\_\<TIMESTAMP\>. 
   - Please send use this folder for all support and issue requests.

1. [Packet Capture]:

====================================================

After downloading and running CollectLogs.ps1, packet capture tracing cmd files will be downloaded to the following folder C:\k\debug.

Usage:

	Go to C:\k\debug\

	Start => .\startpacketcapture.cmd

	<Repro the issue>

	Stop  => .\stoppacketcapture.cmd

	After Stopping the trace, use the trace file from c:\server.etl
