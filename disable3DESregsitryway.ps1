# Function to disable TLS/SSL support for 3DES cipher suite on a remote server
function Disable-3DES {
    param (
        [string]$ServerName
    )

    # Registry key for SCHANNEL cipher suites
    $schannelRegKey = "\\$ServerName\HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers"

    try {
        # Check if the registry key exists
        if (Test-Path -Path $schannelRegKey -ErrorAction SilentlyContinue) {
            # Disable 3DES cipher suite
            Invoke-Command -ComputerName $ServerName -ScriptBlock {
                param ($schannelRegKey)
                Set-ItemProperty -Path $schannelRegKey -Name "Triple DES 168" -Value 0 -ErrorAction Stop
            } -ArgumentList $schannelRegKey
            Write-Host "TLS/SSL support for 3DES cipher suite has been disabled on $ServerName."
        } else {
            Write-Host "Registry key $schannelRegKey not found on $ServerName." -ForegroundColor Red
        }
    } catch {
        Write-Host "Failed to disable TLS/SSL support for 3DES cipher suite on $ServerName: $_" -ForegroundColor Red
    }
}

# Prompt for the server name
$serverName = Read-Host "Enter the server name:"

# Call the function to disable 3DES cipher suite on the specified server
Disable-3DES -ServerName $serverName
