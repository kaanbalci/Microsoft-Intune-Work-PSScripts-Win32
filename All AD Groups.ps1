# Import the Active Directory module
Import-Module ActiveDirectory

# Define the output file path
$csvFilePath = "C:\Users\Kaan\Desktop\allgroups.csv"

# Get all security, universal, and global groups in Active Directory
$groups = Get-ADGroup -Filter {
    GroupCategory -eq 'Security' -and (GroupScope -eq 'Universal' -or GroupScope -eq 'Global')
} -Properties DistinguishedName

# Export the group names and distinguished names to a CSV file
$groups | Select-Object Name, DistinguishedName | Export-Csv -Path $csvFilePath -NoTypeInformation

# Display a confirmation message
Write-Host "Group information exported to $csvFilePath"