# Function to create or update registry keys
function Update-Registry {
    param (
        [string]$ServerName
    )

    $regKeys = @(
        "HKLM:\Software\Microsoft\Cryptography\Wintrust\Config",
        "HKLM:\Software\Wow6432Node\Microsoft\Cryptography\Wintrust\Config"
    )

    $valueName = "EnableCertPaddingCheck"
    $valueData = "1"

    # Check if the server is online
    if (Test-Connection -Cn $ServerName -BufferSize 16 -Count 1 -Quiet) {
        try {
            # Create or update registry keys
            foreach ($regKey in $regKeys) {
                if (Test-Path $regKey) {
                    Set-ItemProperty -Path $regKey -Name $valueName -Value $valueData -Force
                    Write-Host "Registry key updated: $regKey"
                } else {
                    New-Item -Path $regKey -Force | Out-Null
                    New-ItemProperty -Path $regKey -Name $valueName -Value $valueData -PropertyType "String" -Force | Out-Null
                    Write-Host "New registry key created: $regKey"
                }
            }
            Write-Host "Registry update complete on $ServerName."
        }
        catch {
            Write-Host "Failed to update registry on $ServerName $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "Unable to connect to $ServerName. Please check if the server is online and accessible." -ForegroundColor Red
    }
}

# Prompt for the server name
$serverName = Read-Host "Enter the server name:"

# Update the registry on the specified server
Update-Registry -ServerName $serverName