# Data Collection

===================================================

All scripts require an elevated (Run as administrator) PowerShell console. The script has been tested on both Windows PowerShell 5.1 and PowerShell 7.

Data will be saved to a child directory of the working directory (the path of the PowerShell console). The full path will be in the final line of script console output.

Two methods can be used to collect data: Online and Offline. 

## Online

The Online method requires that the system be connected to the Internet and have access to github.com. All of the required files will be automatically downloaded to C:\k\debug, then the script will execute. 

- Open an elevated Powershell console (Run as Administrator).

- Run: 
```PowerShell 
Set-ExecutionPolicy Bypass
```
  
- Execute the requested script:

**HNS Trace**
```PowerShell 
Invoke-WebRequest https://raw.githubusercontent.com/JamesKehr/SDN/collectlogs_update/Kubernetes/windows/debug/Start-HnsTrace.ps1 | Invoke-Expression
```

**HNS Full Trace**
```PowerShell 
Invoke-WebRequest https://raw.githubusercontent.com/JamesKehr/SDN/collectlogs_update/Kubernetes/windows/debug/Start-HnsFullTrace.ps1 | Invoke-Expression
```

**SDN Logs**
```PowerShell 
Invoke-WebRequest https://raw.githubusercontent.com/JamesKehr/SDN/collectlogs_update/Kubernetes/windows/debug/Get-SdnLogs.ps1 | Invoke-Expression
```



## Offline

The Offline method can be used when the system does not have Internet access, or does not have access to github.com. This method will require two systems, one of them with Internet and github.com access, plus a method to copy the files to the offline system.

This method can be used to rerun the scripts on a system after they have already been downloaded, simply skip to the "From the offline Windows system" section. Please note that the script, by default, will always download the newest copies of the debug files. The -NoInternet parameter can be set to prevent this behavior.

#### From an internet connected Windows system:

- Open a Powershell console (Run as Administrator).

- Run: 
```PowerShell 
Set-ExecutionPolicy Bypass
```
  
- Execute this command to download the debug files:
```PowerShell 
Invoke-WebRequest https://raw.githubusercontent.com/JamesKehr/SDN/collectlogs_update/Kubernetes/windows/debug/SdnCommon.ps1 | Invoke-Expression
```

- Copy C:\k\debug from the online system to C:\k\debug on the offline system. Keeping the default folder structure will reduce the chance of running into issues.

#### From the offline Windows system:

- Open an elevated PowerShell console (Run as administrator).
- Navigate to C:\k\debug, where the scripts and files should be located based on the steps above.

```PowerShell
CD C:\k\debug
```

- Execute the requested script.
   - Use the command from support if they request a command with a different set of parameters.
   - The -NoInternet parameter should be used when the system has no Internet connectivity, but is optional on systems with access.

**HNS Trace**
.\Start-HnsTrace.ps1 [-NoInternet]

**HNS Full Trace**
.\Start-HnsFullTrace.ps1 [-NoInternet]

**SDN Logs**
.\Get-SdnLogs.ps1 [-NoInternet]