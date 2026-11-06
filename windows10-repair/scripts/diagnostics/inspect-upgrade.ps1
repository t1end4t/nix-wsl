. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
Get-CimInstance Win32_Processor | Select-Object Name,AddressWidth | Format-List
Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,TotalPhysicalMemory | Format-List
try { Get-CimInstance -Namespace root\cimv2\security\microsofttpm -ClassName Win32_Tpm -ErrorAction Stop | Select-Object SpecVersion,IsEnabled_InitialValue,IsActivated_InitialValue | Format-List } catch { $_.Exception.Message }
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue | Select-Object UEFISecureBootEnabled | Format-List
