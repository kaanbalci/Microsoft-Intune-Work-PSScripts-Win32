#Gets the serial number and name of the device
$serialNumber = (Get-CIMInstance -ClassName win32_bios).SerialNumber
$deviceName = (Get-CimInstance -ClassName Win32_ComputerSystem).Name


#Takes the serial number and evaluates if it is longer than 8. If so, the last 8 characters are passed to $serialNumberConfirmed
if($serialNumber.Length -gt 8) {
    $serialNumberConfirmed = $serialNumber.SubString($serialNumber.Length - 8)
}
#Takes the serial number and evaluates if it is less than 8. If so, the value is passed to $serialNumberConfirmed
elseif ($serialNumber.Length -le 8) {
    $serialNumberConfirmed = $serialNumber
}


#Adds the company name and the new serial number together to form the new computer name
$newComputerName="CHP-" + $serialNumberConfirmed  

#Determines if the device name is already correctly set. If so, script ends. If not, the device is renamed.
if($newComputerName = $deviceName){
    exit
}
else{
Rename-Computer -NewName $newComputerName -Force
}