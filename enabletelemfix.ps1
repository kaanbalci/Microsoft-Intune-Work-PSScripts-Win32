# Run PowerShell as Administrator

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Re-enable Telemetry and Data Collection Services
$services = @(
    'DiagTrack',     # Connected User Experiences and Telemetry
    'dmwappushservice'  # dmwappushservice (Windows Push Notifications System Service)
)

foreach ($service in $services) {
    Get-Service -Name $service -ErrorAction SilentlyContinue | Set-Service -StartupType Automatic
    Start-Service -Name $service -ErrorAction SilentlyContinue
    Write-Host "Service $service has been re-enabled."
}

# Re-enable Telemetry in Task Scheduler using Task Names
$tasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
)

foreach ($task in $tasks) {
    Enable-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
    Write-Host "Scheduled task $task has been re-enabled."
}

# Set Registry Keys to Re-enable Telemetry
$regKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
)

foreach ($regKey in $regKeys) {
    # If the registry path exists, set the AllowTelemetry value to its default (1 or 3 based on Windows version)
    if (Test-Path $regKey) {
        Set-ItemProperty -Path $regKey -Name "AllowTelemetry" -Value 1 -Force
        Write-Host "Telemetry re-enabled in registry: $regKey"
    }
}

# Re-enable Feedback Notifications
$feedbackPath = "HKCU:\Software\Microsoft\Siuf\Rules"

if (Test-Path $feedbackPath) {
    Set-ItemProperty -Path $feedbackPath -Name "NumberOfSIUFInPeriod" -Value 1 -Force
    Set-ItemProperty -Path $feedbackPath -Name "PeriodInNanoSeconds" -Value 1 -Force
    Write-Host "Feedback notifications re-enabled."
}

# Re-enable Customer Experience Improvement Program
$ceipPath = "HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows"

if (Test-Path $ceipPath) {
    Set-ItemProperty -Path $ceipPath -Name "CEIPEnable" -Value 1 -Force
    Write-Host "Customer Experience Improvement Program re-enabled."
}

Write-Host "Telemetry services, tasks, and registry settings have been restored to default."
