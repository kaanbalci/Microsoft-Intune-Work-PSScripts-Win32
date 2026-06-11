# Function to configure TLS settings on a remote server
function Configure-TLS {
    param (
        [string]$ServerName
    )

    $tls12RegKey = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server"
    $enabledHashAlgorithms = @(
        "SHA256"     # Stronger HMAC variant of SHA-1
    )

    $disabledHashAlgorithms = @(
        "MD5",       # Weak HMAC algorithm
        "SHA"        # Weaker HMAC variant of SHA-1
    )

    # Check if the server is online
    if (Test-Connection -Cn $ServerName -BufferSize 16 -Count 1 -Quiet) {
        try {
            # Enable/Disable hash algorithms for TLS 1.2
            Invoke-Command -ComputerName $ServerName -ScriptBlock {
                param ($tls12RegKey, $enabledHashAlgorithms, $disabledHashAlgorithms)
                if (Test-Path $tls12RegKey) {
                    $hashAlgorithmsKey = Join-Path $tls12RegKey "Hashes"
                    if (!(Test-Path $hashAlgorithmsKey)) {
                        New-Item -Path $hashAlgorithmsKey -Force | Out-Null
                    }

                    foreach ($hashAlgorithm in $enabledHashAlgorithms) {
                        $algorithmKey = Join-Path $hashAlgorithmsKey $hashAlgorithm
                        if (!(Test-Path $algorithmKey)) {
                            New-Item -Path $algorithmKey -Force | Out-Null
                        }
                        New-ItemProperty -Path $algorithmKey -Name "Enabled" -Value 1 -PropertyType "DWord" -Force | Out-Null
                    }

                    foreach ($hashAlgorithm in $disabledHashAlgorithms) {
                        $algorithmKey = Join-Path $hashAlgorithmsKey $hashAlgorithm
                        if (Test-Path $algorithmKey) {
                            New-ItemProperty -Path $algorithmKey -Name "Enabled" -Value 0 -PropertyType "DWord" -Force | Out-Null
                        }
                    }
                }
            } -ArgumentList $tls12RegKey, $enabledHashAlgorithms, $disabledHashAlgorithms

            Write-Host "TLS 1.2 has been configured on $ServerName."
        }
        catch {
            Write-Host "Failed to configure TLS 1.2 on $ServerName $($_.Exception.Message)" -ForegroundColor Red
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