# Import the Active Directory module
Import-Module ActiveDirectory

# Define the Source OUs
$SourceOUs = @(
    "OU=Computer Accounts,DC=chpc2,DC=org"
)

# Define the Destination OU
$DestinationOU = "OU=TEST Intune Autopilot,DC=chpc2,DC=org"

# Define the list of specific computer names to move
$ComputerNames = @(
    "CHP-BWS7MS3",
"CHP-J4VP7S3",
"CHP-31DJD14",
"CHP0859",
"CHP-GTLJ314",
"CHP-61DJD14",
"CHP-41DJD14",
"CHP-2BN0KS3",
"CHP0923",
"CHP-D3D25Y3",
"CHP-8YS5ZW3",
"CHP0943",
"CHP-FTLJ314",
"CHP-5PX25Y3",
"CHP-CBBN114",
"CHP-JTLJ314",
"CHP-GQVPHS3",
"CHP0851",
"CHP0881",
"CHP-3PX25Y3",
"CHP-F826CS3",
"CHP0963",
"CHP0965",
"CHP0829",
"CHP-BVBD214",
"CHP0961",
"CHP0899",
"CHP0785",
"CHP-7JGT4Y3",
"CHP0905",
"CHP-B741KS3",
"CHP-4YS5ZW3",
"CHP0845",
"CHP0831",
"CHP-32VP7S3",
"CHP-4PX25Y3",
"CHP0913",
"CHP-B7LCXL3",
"CHP-3R81HX3",
"CHP-9YS5ZW3",
"CHP0771",
"CHP-C1DJD14",
"CHP0929",
"CHP-8FV2HS3",
"CHP0935",
"CHP-DWS7MS3",
"CHP-21DJD14",
"CHP0941",
"CHP-DC673T3",
"CHP0947",
"CHP-FZ2FLY3",
"CHP-81DJD14",
"CHP-1R81HX3",
"CHP-JZ2FLY3",
"CHP0777",
"CHP-CHV2HS3",
"CHP0959",
"CHP-62VP7S3",
"CHP0779",
"CHP-GZ2FLY3",
"CHP-91DJD14",
"CHP-5YS6ZW3",
"CHP-5HV2HS3",
"CHP-8741KS3",
"CHP-DC3FLY3",
"CHP-6PX25Y3",
"CHP-93D25Y3",
"CHP-3MV2HS3",
"CHP-9JGT4Y3",
"CHP0901",
"CHP-9VBD214",
"CHP-71DJD14",
"CHP-8JGT4Y3",
"CHP0897",
"CHP-4R81HX3",
"CHP0855",
"CHP-C741KS3",
"CHP-HWS7MS3",
"CHP0915",
"CHP0955",
"CHP0857",
"CHP-38VP7S3",
"CHP-J526CS3",
"CHP0957",
"CHP-9741KS3",
"CHP-FQSB5X3",
"CHP0925",
"CHP-1BLCXL3",
"CHP-83D25Y3",
"CHP-FC3FLY3",
"CHP-7PX25Y3",
"CHP0847",
"CHP0911",
"CHP0907",
"CHP0917",
"CHP-CWS7MS3",
"CHP-9GQD5Y3",
"CHP0909",
"CHP-2R81HX3",
"CHP0853",
"CHP-GWS7MS3",
"CHP0903",
"CHP-DTLJ314",
"CHP-HTLJ314",
"CHP-C3D25Y3",
"CHP-8GQD5Y3",
"CHP0873",
"CHP-B3D25Y3",
"CHP0867",
"CHP-D626CS3"
)

# Loop through each computer name and attempt to locate and move it
foreach ($ComputerName in $ComputerNames) {
    $Found = $false

    # Search for the computer in each source OU
    foreach ($OU in $SourceOUs) {
        try {
            # Check if the computer exists in the current source OU
            $Computer = Get-ADComputer -Identity $ComputerName -SearchBase $OU -Properties DistinguishedName -ErrorAction SilentlyContinue
            if ($Computer) {
                Write-Host "Found $($ComputerName) in $OU. Moving..." -ForegroundColor Yellow
                
                # Move the computer to the destination OU
                Move-ADObject -Identity $Computer.DistinguishedName -TargetPath $DestinationOU
                Write-Host "Successfully moved $($ComputerName) to $DestinationOU" -ForegroundColor Green
                $Found = $true
                break
            }
        }
        catch {
            Write-Host "Error checking for $($ComputerName) in $OU. $_" -ForegroundColor Red
        }
    }

    # Notify if the computer wasn't found in any of the source OUs
    if (-not $Found) {
        Write-Host "Computer $($ComputerName) not found in any of the source OUs." -ForegroundColor Red
    }
}
