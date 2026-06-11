# Prompt for the remote computer name
$remoteComputer = Read-Host "Enter the name or IP address of the remote computer"

# Define the cipher suites to disable (static key cipher suites)
$cipherSuites = @(
    "TLS_RSA_WITH_AES_128_CBC_SHA",
    "TLS_RSA_WITH_AES_256_CBC_SHA",
    "TLS_RSA_WITH_AES_128_CBC_SHA256",
    "TLS_RSA_WITH_AES_256_CBC_SHA256"
)

# Define script block to execute on the remote machine
$scriptBlock = {
    param($cipherSuites)
    
    # Function to create registry key if it doesn't exist
    function New-RegistryKeyIfNotExists {
        param (
            [string]$Path
        )

        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
    }

    # Create registry keys for cipher suites if they don't exist
    foreach ($suite in $cipherSuites) {
        $keyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\$suite"
        New-RegistryKeyIfNotExists -Path $keyPath
    }

    # Disable static key cipher suites for TLS/SSL
    foreach ($suite in $cipherSuites) {
        Write-Host "Disabling $suite"
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\$suite" -Name "Enabled" -Value 0 -Force
    }
}

# Execute the script block on the remote machine
Invoke-Command -ComputerName $remoteComputer -ScriptBlock $scriptBlock -ArgumentList $cipherSuites
