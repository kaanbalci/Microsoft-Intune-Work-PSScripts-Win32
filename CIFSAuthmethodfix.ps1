$server = Read-Host -Prompt 'Enter the server name'

$registryPathLsa = "SYSTEM\CurrentControlSet\Control\Lsa"
$registryPathMsv1_0 = "SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0"
$valueNameLsa = "LMCompatibilityLevel"
$valueNameNtlmMinClientSec = "NtlmMinClientSec"
$valueNameNtlmMinServerSec = "NtlmMinServerSec"
$dataLsa = 5
$dataMsv1_0 = 0x20080000

# Check if the server is reachable
if (!(Test-Connection -ComputerName $server -Count 1 -Quiet)) {
    Write-Host "Failed to reach the server: $server"
    exit
}

# Create a registry key object for the LSA path
$regKeyLsa = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $server)
$regKeyLsa = $regKeyLsa.OpenSubKey($registryPathLsa, $true)

# Create a registry key object for the MSV1_0 path
$regKeyMsv1_0 = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $server)
$regKeyMsv1_0 = $regKeyMsv1_0.OpenSubKey($registryPathMsv1_0, $true)

# Update the LMCompatibilityLevel key in LSA
try {
    $regKeyLsa.SetValue($valueNameLsa, $dataLsa, "DWORD")
    Write-Host "LMCompatibilityLevel key updated successfully on $server (LSA)."
} catch {
    Write-Host "Failed to update the LMCompatibilityLevel key on $server (LSA)."
}

# Update the values in MSV1_0
try {
    $regKeyMsv1_0.SetValue($valueNameNtlmMinClientSec, $dataMsv1_0, "DWORD")
    $regKeyMsv1_0.SetValue($valueNameNtlmMinServerSec, $dataMsv1_0, "DWORD")
    Write-Host "Registry keys in MSV1_0 updated successfully on $server."
} catch {
    Write-Host "Failed to update registry keys in MSV1_0 on $server"
}

# Close the registry key objects
$regKeyLsa.Close()
$regKeyMsv1_0.Close()