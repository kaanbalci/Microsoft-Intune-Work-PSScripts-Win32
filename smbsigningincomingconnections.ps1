# Enable or Require SMB Signing Script for Incoming Connections on a Remote Server

# Prompt the user for the target server name or IP address
$targetServer = Read-Host "Enter the name or IP address of the target server:"

# Set the desired SMB signing configuration: "Enable" or "Require"
$signingConfig = Read-Host "Enter the SMB signing configuration ('Enable' or 'Require'):"
$signingConfig = $signingConfig.ToLower()

# Check if the script is running with administrative privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Please run this script with administrative privileges."
    Exit
}

# Configure SMB signing for incoming connections on the specified server
Invoke-Command -ComputerName $targetServer -ScriptBlock {
    param($signingConfig)
    
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" RequireSecuritySignature -Value 1
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" EnableSecuritySignature -Value 1
    
    if ($signingConfig -eq "require") {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" EnableForcedLogoff -Value 1
    }
} -ArgumentList $signingConfig

Write-Host "SMB signing configuration set to '$signingConfig' for incoming connections on server '$targetServer'."