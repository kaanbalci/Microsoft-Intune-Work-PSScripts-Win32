# Prompt for credentials
$credentials = Get-Credential

# Prompt for target computer
$targetComputer = Read-Host "Enter the target computer name or IP address"

# Check if the target computer is provided
if (-not $targetComputer) {
    Write-Host "Please provide the target computer name or IP address."
    exit
}

# Display the target computer
Write-Host "Target Computer: $targetComputer"

# Run the script on the remote machine
Invoke-Command -ComputerName $targetComputer -Credential $credentials -ScriptBlock {
    param ()

    function Set-RegistryProperty {
        param (
            [string]$Path,
            [string]$Name,
            [int]$Value
        )

        if (-not (Test-Path $Path -PathType Container)) {
            New-Item -Path $Path -Force | Out-Null
        }

        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force
    }

    # Define registry keys for TLS 1.2
    $tls12ServerKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server'
    $tls12ClientKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'

    # Define registry keys for TLS 1.1
    $tls11ServerKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server'
    $tls11ClientKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client'

    # Enable TLS 1.2 and disable TLS 1.1 using registry modifications
    Set-RegistryProperty -Path $tls12ServerKey -Name 'Enabled' -Value 1
    Set-RegistryProperty -Path $tls12ServerKey -Name 'DisabledByDefault' -Value 0
    Set-RegistryProperty -Path $tls12ClientKey -Name 'Enabled' -Value 1
    Set-RegistryProperty -Path $tls12ClientKey -Name 'DisabledByDefault' -Value 0

    Set-RegistryProperty -Path $tls11ServerKey -Name 'Enabled' -Value 0
    Set-RegistryProperty -Path $tls11ServerKey -Name 'DisabledByDefault' -Value 1
    Set-RegistryProperty -Path $tls11ClientKey -Name 'Enabled' -Value 0
    Set-RegistryProperty -Path $tls11ClientKey -Name 'DisabledByDefault' -Value 1

    Write-Host "TLS 1.2 enabled, TLS 1.1 disabled successfully on $($env:COMPUTERNAME)."
} -ArgumentList @()
