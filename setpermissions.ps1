Connect-ExchangeOnline 

#-UserPrincipalName 

#"$env:username@$($env:userdnsdomain.ToLower())"


Import-Csv -Path C:\Users\Kaan\Desktop\setpermissions2.csv | ForEach-Object {
    Set-MailboxFolderPermission -Identity $($_.Identity) -User Default -AccessRights Reviewer
    Write-Host "$($_.Identity) - Permissions set to Reviewer."
}



Write-Host 
"|-------------------------------------------------------|
|-- Set Permissions Script has completed successfully --|
|-------------------------------------------------------|"

