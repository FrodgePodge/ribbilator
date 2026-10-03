# registers a scheduled task that runs ribbilator.ps1:
#   - at every logon (the "i just booted" check)
#   - whenever the machine wakes from sleep
#   - once a day around midday, with a random delay of up to 3 hours (covers a machine left on)
# the script exits quickly, without using the network, unless a lit day is missing. run once per machine.
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'ribbilator.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""

$logon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$daily = New-ScheduledTaskTrigger -Daily -At '12:00' -RandomDelay (New-TimeSpan -Hours 3)

$wake = New-CimInstance -ClientOnly -CimClass (Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler)
$wake.Enabled = $true
$wake.Subscription = '<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name=''Microsoft-Windows-Power-Troubleshooter''] and EventID=1]]</Select></Query></QueryList>'

# StartWhenAvailable catches a missed run; RunOnlyIfNetworkAvailable waits for internet
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
Register-ScheduledTask -TaskName 'Ribbilator' -Action $action -Trigger $logon, $wake, $daily -Settings $settings -Description 'keeps the github graph spelling RIBBIT' -Force | Out-Null
Write-Host 'registered task Ribbilator (logon, wake, daily)'
