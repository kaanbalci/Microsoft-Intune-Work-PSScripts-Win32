# Uninstall-DellEndpointConfigure.ps1
# Silently uninstalls Dell Command | Endpoint Configure for Microsoft Intune
# without hardcoding the MSI product code.

$ErrorActionPreference = "Stop"

$AppName = "Dell Command | Endpoint Configure for Microsoft Intune"

$UninstallRegistryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$App = Get-ItemProperty -Path $UninstallRegistryPaths -ErrorAction SilentlyContinue |
    Where-Object {
        $_.DisplayName -eq $AppName -or
        $_.DisplayName -like "Dell Command*Endpoint Configure*Microsoft Intune*"
    } |
    Select-Object -First 1

if (-not $App) {
    Write-Output "Dell Command Endpoint Configure for Microsoft Intune is not installed."
    exit 0
}

Write-Output "Found: $($App.DisplayName)"
Write-Output "Version: $($App.DisplayVersion)"

$ProductCode = $null

# MSI apps commonly use the product code as the uninstall registry key name.
if ($App.PSChildName -match "^\{[A-Fa-f0-9-]+\}$") {
    $ProductCode = $App.PSChildName
}
elseif ($App.UninstallString -match "\{[A-Fa-f0-9-]+\}") {
    $ProductCode = $Matches[0]
}

if (-not $ProductCode) {
    Write-Output "Unable to find MSI product code from registry."
    Write-Output "UninstallString: $($App.UninstallString)"
    exit 1
}

Write-Output "Uninstalling product code: $ProductCode"

$Process = Start-Process -FilePath "msiexec.exe" `
    -ArgumentList "/x $ProductCode /qn /norestart" `
    -Wait `
    -PassThru

Write-Output "msiexec exit code: $($Process.ExitCode)"

switch ($Process.ExitCode) {
    0     { exit 0 }
    3010  { exit 0 } # Success, reboot required
    1605  { exit 0 } # Product not installed
    default { exit $Process.ExitCode }
}