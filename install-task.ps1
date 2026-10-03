# registers a scheduled task that runs ribbilator.ps1 at every logon and then hourly.
# the script exits quickly (no network) unless a lit day is missing. run once per machine.
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'ribbilator.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
$logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$hourly = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
Register-ScheduledTask -TaskName 'Ribbilator' -Action $action -Trigger $logon, $hourly -Settings $settings -Description 'keeps the github graph spelling RIBBIT' -Force | Out-Null
Write-Host 'registered task Ribbilator'
