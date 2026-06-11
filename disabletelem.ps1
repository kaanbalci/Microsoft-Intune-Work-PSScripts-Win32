# Run PowerShell as Administrator

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Disable Telemetry and Data Collection Services
$services = @(
    'DiagTrack',     # Connected User Experiences and Telemetry
    'dmwappushservice'  # dmwappushservice (Windows Push Notifications System Service)
)

foreach ($service in $services) {
    Get-Service -Name $service -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled
    Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
}

# Disable Telemetry in Task Scheduler using Task Names
$tasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
)

foreach ($task in $tasks) {
    Disable-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
}

# Set Registry Keys to Disable Telemetry
$regKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
)

foreach ($regKey in $regKeys) {
    # Check if the registry path exists, create it if it doesn't
    if (-not (Test-Path $regKey)) {
        Write-Host "Creating missing registry path: $regKey"
        New-Item -Path $regKey -Force | Out-Null
    }
    
    # Set the AllowTelemetry value to 0 (disable telemetry)
    Set-ItemProperty -Path $regKey -Name "AllowTelemetry" -Value 0 -Force
    Write-Host "Telemetry disabled in registry: $regKey"
}

# Disable Feedback Notifications
$feedbackPath = "HKCU:\Software\Microsoft\Siuf\Rules"

if (-not (Test-Path $feedbackPath)) {
    Write-Host "Creating missing feedback registry path: $feedbackPath"
    New-Item -Path $feedbackPath -Force | Out-Null
}

Set-ItemProperty -Path $feedbackPath -Name "NumberOfSIUFInPeriod" -Value 0 -Force
Set-ItemProperty -Path $feedbackPath -Name "PeriodInNanoSeconds" -Value 0 -Force
Write-Host "Feedback notifications disabled."

# Disable Feedback Experience Improvement Program
$ceipPath = "HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows"

if (-not (Test-Path $ceipPath)) {
    Write-Host "Creating missing CEIP registry path: $ceipPath"
    New-Item -Path $ceipPath -Force | Out-Null
}

Set-ItemProperty -Path $ceipPath -Name "CEIPEnable" -Value 0 -Force
Write-Host "Customer Experience Improvement Program disabled."

Write-Host "Telemetry services, tasks, and registry settings have been disabled."
