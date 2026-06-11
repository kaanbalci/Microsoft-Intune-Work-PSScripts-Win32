# Function to configure TLS settings on a remote server
function Configure-TLS {
    param (
        [string]$ServerName
    )

    $regKey = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server"
    
    # Check if the server is online
    if (Test-Connection -Cn $ServerName -BufferSize 16 -Count 1 -Quiet) {
        try {
            # Enable TLS 1.2
            $result = Invoke-Command -ComputerName $ServerName -ScriptBlock {
                param ($regKey)
                if (!(Test-Path $regKey)) {
                    New-Item -Path $regKey -Force | Out-Null
                }
                New-ItemProperty -Path $regKey -Name "Enabled" -Value 1 -PropertyType "DWord" -Force | Out-Null
                "Success"
            } -ArgumentList $regKey

            if ($result -eq "Success") {
                Write-Host "TLS 1.2 has been enabled on $ServerName."
            } else {
                Write-Host "Failed to enable TLS 1.2 on $ServerName $result" -ForegroundColor Red
            }
        }
        catch {
            Write-Host "Failed to enable TLS 1.2 on $ServerName $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "Unable to connect to $ServerName. Please check if the server is online and accessible." -ForegroundColor Red
    }
}

# Prompt for the server name
$serverName = Read-Host "Enter the server name:"

# Configure TLS for the specified server
Configure-TLS -ServerName $serverName