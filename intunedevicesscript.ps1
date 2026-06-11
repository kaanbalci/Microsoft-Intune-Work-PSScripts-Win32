# Authenticate with Azure AD
Connect-AzureAD

# Get the list of iPhones in Intune
$devices = Invoke-MSGraphRequest  -Url "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices " -HttpMethod GET
$devices.value | Where-Object operatingSystem -Contains 'iOS'

# Create an empty array to store the device information
$deviceInfo = @()

# Loop through each device
foreach ($device in $devices) {
    # Get the device's compliance status
    $complianceStatus = (Invoke-MSGraphRequest -HttpMethod GET -Url "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$($device.id)/complianceInformation").complianceState

    # Get the device's name and details
    $deviceName = $device.deviceName
    $deviceDetails = $device.operatingSystem

    # Determine if the device is active or inactive
    $isActive = $device.isActive

    # Create a new object to store the device's information
    $deviceObject = [PSCustomObject]@{
        DeviceName = $deviceName
        DeviceDetails = $deviceDetails
        ComplianceStatus = $complianceStatus
        IsActive = $isActive
    }

    # Add the device information to the array
    $deviceInfo += $deviceObject
}

# Output the device information to a CSV file
$deviceInfo | Export-Csv -Path "C:\output.csv" -NoTypeInformation