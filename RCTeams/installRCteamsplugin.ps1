$Installer = Join-Path $PSScriptRoot 'RingCentralForTeamsDesktopPlugin.exe'
$ExpectedPath = Join-Path $env:LOCALAPPDATA 'Programs\ringcentral-desktop-plugin'
$LogPath = Join-Path $env:LOCALAPPDATA 'RingCentralTeamsPlugin-Install.log'

"Starting install as user: $env:USERNAME" | Out-File $LogPath -Append
"Installer path: $Installer" | Out-File $LogPath -Append
"Expected path: $ExpectedPath" | Out-File $LogPath -Append

if (-not (Test-Path $Installer)) {
    "Installer not found." | Out-File $LogPath -Append
    exit 1
}

$Process = Start-Process -FilePath $Installer -ArgumentList '/S' -Wait -PassThru
"Installer exit code: $($Process.ExitCode)" | Out-File $LogPath -Append

$Timeout = 300
$Elapsed = 0

while ($Elapsed -lt $Timeout) {
    if (Test-Path $ExpectedPath) {
        "Install folder found." | Out-File $LogPath -Append
        exit 0
    }

    Start-Sleep -Seconds 5
    $Elapsed += 5
}

"Install folder was not found after waiting $Timeout seconds." | Out-File $LogPath -Append
exit 1