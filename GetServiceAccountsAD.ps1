$OUpath= 
"ou=Service Accounts,dc=chpc2,dc=org",
"ou=Sync with O365,ou=Service Accounts,dc=chpc2,dc=org"


$ExportPath = 'C:\TEMP\All-SAs.csv'

$OUPath | foreach { Get-ADUser -Filter * -SearchBase $_} | Select-Object Name,UserPrincipalName,DistinguishedName | Export-Csv -NoType $ExportPath

