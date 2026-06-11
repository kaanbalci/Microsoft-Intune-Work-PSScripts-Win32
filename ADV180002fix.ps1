# Prompt for the remote machine name
$remoteMachine = Read-Host "Enter the name of the remote machine"

# Commands to modify registry settings on the remote machine
$regCommands = @(
    'reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v FeatureSettingsOverride /t REG_DWORD /d 1 /f',
    'reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v FeatureSettingsOverrideMask /t REG_DWORD /d 3 /f'
)

# Loop through each command and execute it on the remote machine
foreach ($command in $regCommands) {
    Invoke-Command -ComputerName $remoteMachine -ScriptBlock {
        param($command)
        Invoke-Expression $command
    } -ArgumentList $command
}
