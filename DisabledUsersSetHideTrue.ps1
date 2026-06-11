# Define the distinguished name (DN) of the OU where you want to search for disabled users.
$ouDN = 'OU=Disabled Accounts - Sync with O365,DC=chpc2,DC=org'

# Get a list of all disabled users in the specified OU.
$disabledUsers = Get-ADUser -Filter "*" -SearchBase $ouDN

# Create an empty array to store the results.
$results = @()

# Loop through each disabled user and check if the "HideFromAddressList" attribute is set to false.
# checks if user is disabled then it will set "HideFromAddressList" to true using Set-AdObject
foreach ($user in $disabledUsers) {
    if ($user.Enabled -eq $false) {
        # If the "HideFromAddressList" attribute is set to false, set it to true.
        Set-ADObject $user.DistinguishedName -Replace @{msExchHideFromAddressLists=$true} 
        Write-Host "Updated 'HideFromAddressLists' attribute for user $($user.Name) to $true"
        # Add the user's details to the results array.
        $results += [PSCustomObject]@{
            Name = $user.Name
            DistinguishedName = $user.DistinguishedName
            HideFromAddressLists = $true
        }
    }
}

# Export the results to a CSV file. You can change path to where you want it to go
$results | Export-Csv -Path "C:\Users\istus\Desktop\DisabledUsers.csv" -NoTypeInformation
