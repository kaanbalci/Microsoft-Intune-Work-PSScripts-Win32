
<#Bitlocker Escrow Report with GUI
Built by Kaan Balci - 3-19-26
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$script:GraphConnected = $false
$script:AllResults = @()
$script:VisibleResults = @()
$script:Summary = [ordered]@{
    TotalLaptops = 0
    Protected = 0
    Missing = 0
    Coverage = 0
    LastRun = $null
}

function Write-UiLog {
    param(
        [string]$Message,
        [ValidateSet('Info','Success','Warning','Error')]
        [string]$Level = 'Info'
    )

    $time = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$time] [$Level] $Message"
    $txtLog.AppendText($entry + [Environment]::NewLine)
    $txtLog.ScrollToEnd()
}

function Show-UiError {
    param(
        [string]$Title,
        [string]$Message
    )

    [System.Windows.MessageBox]::Show($Message, $Title, 'OK', 'Error') | Out-Null
}

function Ensure-GraphModule {
    $requiredModules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.DeviceManagement',
        'Microsoft.Graph.Identity.SignIns'
    )

    try {
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
        }

        foreach ($module in $requiredModules) {
            if (-not (Get-Module -ListAvailable -Name $module)) {
                Write-UiLog "Installing $module for current user..." 'Info'
                Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction Stop
            }
            Import-Module $module -Force -ErrorAction Stop
        }

        return $true
    }
    catch {
        Write-UiLog "Module setup failed: $($_.Exception.Message)" 'Error'
        Show-UiError -Title 'Module Setup Error' -Message "Unable to install or import Microsoft Graph modules.`n`n$($_.Exception.Message)"
        return $false
    }
}

function Connect-GraphForReport {
    if (-not (Ensure-GraphModule)) {
        return
    }

    try {
        Write-UiLog 'Connecting to Microsoft Graph...' 'Info'
        $scopes = @(
            'DeviceManagementManagedDevices.Read.All',
            'BitlockerKey.ReadBasic.All'
        )

        try {
            Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop | Out-Null
        }
        catch {
            if ($_.Exception.Message -match 'window handle' -or $_.Exception.Message -match 'InteractiveBrowserCredential') {
                Write-UiLog 'Interactive sign-in hit a window-handle issue. Falling back to device code sign-in...' 'Warning'
                Connect-MgGraph -Scopes $scopes -UseDeviceAuthentication -ContextScope Process -NoWelcome -ErrorAction Stop | Out-Null
            }
            else {
                throw
            }
        }

        $context = Get-MgContext
        if ($null -ne $context) {
            $script:GraphConnected = $true
            $lblConnectionStatus.Text = "Connected as: $($context.Account)"
            $lblConnectionStatus.Foreground = [System.Windows.Media.Brushes]::LightGreen
            Write-UiLog "Connected to tenant $($context.TenantId) as $($context.Account)." 'Success'
        }
    }
    catch {
        $script:GraphConnected = $false
        $lblConnectionStatus.Text = 'Not connected'
        $lblConnectionStatus.Foreground = [System.Windows.Media.Brushes]::OrangeRed
        Write-UiLog "Graph connection failed: $($_.Exception.Message)" 'Error'
        Show-UiError -Title 'Connection Error' -Message "Microsoft Graph sign-in failed.`n`n$($_.Exception.Message)"
    }
}

function Get-StatusBrush {
    param([string]$Status)

    switch ($Status) {
        'Protected / Key Escrowed' { return [System.Windows.Media.Brushes]::LightGreen }
        'Missing Recovery Key - Action Required' { return [System.Windows.Media.Brushes]::OrangeRed }
        default { return [System.Windows.Media.Brushes]::Gold }
    }
}

function Update-SummaryCards {
    $lblTotalValue.Text = [string]$script:Summary.TotalLaptops
    $lblProtectedValue.Text = [string]$script:Summary.Protected
    $lblMissingValue.Text = [string]$script:Summary.Missing
    $lblCoverageValue.Text = if ($script:Summary.TotalLaptops -gt 0) { '{0:N1}%' -f $script:Summary.Coverage } else { '0.0%' }
    $lblLastRun.Text = if ($script:Summary.LastRun) { "Last refresh: $($script:Summary.LastRun.ToString('yyyy-MM-dd HH:mm:ss'))" } else { 'Last refresh: not yet run' }
}

function Apply-ResultFilter {
    $search = $txtSearch.Text.Trim()
    $missingOnly = [bool]$chkMissingOnly.IsChecked

    $filtered = $script:AllResults

    if ($missingOnly) {
        $filtered = $filtered | Where-Object { $_.Status -eq 'Missing Recovery Key - Action Required' }
    }

    if (-not [string]::IsNullOrWhiteSpace($search)) {
        $needle = $search.ToLowerInvariant()
        $filtered = $filtered | Where-Object {
            ($_.DeviceName -and $_.DeviceName.ToLowerInvariant().Contains($needle)) -or
            ($_.UserPrincipalName -and $_.UserPrincipalName.ToLowerInvariant().Contains($needle)) -or
            ($_.SerialNumber -and $_.SerialNumber.ToLowerInvariant().Contains($needle)) -or
            ($_.Model -and $_.Model.ToLowerInvariant().Contains($needle)) -or
            ($_.Manufacturer -and $_.Manufacturer.ToLowerInvariant().Contains($needle)) -or
            ($_.AzureADDeviceId -and $_.AzureADDeviceId.ToLowerInvariant().Contains($needle))
        }
    }

    $script:VisibleResults = @($filtered)
    $gridResults.ItemsSource = $null
    $gridResults.ItemsSource = $script:VisibleResults
    $lblVisibleCount.Text = "Visible devices: $($script:VisibleResults.Count)"
}

function Get-BitLockerData {
    try {
        Write-UiLog 'Pulling Intune managed devices from Microsoft Graph...' 'Info'
        $devices = @(Get-MgDeviceManagementManagedDevice -All -Property "id,deviceName,userPrincipalName,serialNumber,manufacturer,model,operatingSystem,azureADDeviceId,lastSyncDateTime" -ErrorAction Stop)
        Write-UiLog "Loaded $($devices.Count) managed device records." 'Success'

        Write-UiLog 'Pulling BitLocker recovery key metadata from Microsoft Graph...' 'Info'
        $keys = @(Get-MgInformationProtectionBitlockerRecoveryKey -All -Property "id,deviceId,createdDateTime" -ErrorAction Stop)
        Write-UiLog "Loaded $($keys.Count) BitLocker recovery key record(s)." 'Success'

        $keyLookup = @{}
        foreach ($entry in ($keys | Group-Object deviceId)) {
            $latest = $null
            if ($entry.Group.createdDateTime) {
                $latest = $entry.Group.createdDateTime | Sort-Object -Descending | Select-Object -First 1
            }
            $keyLookup[$entry.Name] = [pscustomobject]@{
                RecoveryKeyCount        = $entry.Count
                LatestRecoveryKeyBackup = $latest
            }
        }

        $laptops = $devices | Where-Object {
            $_.OperatingSystem -eq 'Windows' -and
            -not [string]::IsNullOrWhiteSpace($_.SerialNumber) -and
            -not [string]::IsNullOrWhiteSpace($_.Model) -and
            $_.Model -notmatch 'Virtual Machine'
        }

        Write-UiLog "Filtered to $($laptops.Count) Windows laptop record(s) using your Power BI logic equivalent." 'Info'

        $results = foreach ($device in $laptops) {
            $deviceId = $device.AzureADDeviceId
            $keyData = $null
            if (-not [string]::IsNullOrWhiteSpace($deviceId) -and $keyLookup.ContainsKey($deviceId)) {
                $keyData = $keyLookup[$deviceId]
            }

            $status = if ($null -ne $keyData -and $keyData.RecoveryKeyCount -gt 0) {
                'Protected / Key Escrowed'
            }
            else {
                'Missing Recovery Key - Action Required'
            }

            [pscustomobject]@{
                DeviceName               = $device.DeviceName
                UserPrincipalName        = $device.UserPrincipalName
                SerialNumber             = $device.SerialNumber
                Manufacturer             = $device.Manufacturer
                Model                    = $device.Model
                OperatingSystem          = $device.OperatingSystem
                AzureADDeviceId          = $device.AzureADDeviceId
                LastSyncDateTime         = $device.LastSyncDateTime
                RecoveryKeyCount         = if ($keyData) { $keyData.RecoveryKeyCount } else { 0 }
                LatestRecoveryKeyBackup  = if ($keyData) { $keyData.LatestRecoveryKeyBackup } else { $null }
                Status                   = $status
                StatusColor              = if ($status -eq 'Protected / Key Escrowed') { 'Green' } else { 'Red' }
            }
        }

        return @($results)
    }
    catch {
        throw $_
    }
}

function Run-Report {
    if (-not $script:GraphConnected) {
        [System.Windows.MessageBox]::Show('Please connect to Microsoft Graph first.', 'Not Connected', 'OK', 'Warning') | Out-Null
        return
    }

    try {
        $window.Cursor = [System.Windows.Input.Cursors]::Wait
        $results = @(Get-BitLockerData)
        $protected = @($results | Where-Object { $_.Status -eq 'Protected / Key Escrowed' }).Count
        $missing = @($results | Where-Object { $_.Status -eq 'Missing Recovery Key - Action Required' }).Count
        $total = @($results).Count
        $coverage = if ($total -gt 0) { [math]::Round(($protected / $total) * 100, 1) } else { 0 }

        $script:AllResults = $results | Sort-Object Status, DeviceName
        $script:Summary.TotalLaptops = $total
        $script:Summary.Protected = $protected
        $script:Summary.Missing = $missing
        $script:Summary.Coverage = $coverage
        $script:Summary.LastRun = Get-Date

        Update-SummaryCards
        Apply-ResultFilter

        Write-UiLog "Report completed. Total laptops: $total. Protected: $protected. Missing: $missing. Coverage: $coverage%." 'Success'
    }
    catch {
        Write-UiLog "Report failed: $($_.Exception.Message)" 'Error'
        Show-UiError -Title 'Report Error' -Message "Failed to build the BitLocker escrow report.`n`n$($_.Exception.Message)"
    }
    finally {
        $window.Cursor = [System.Windows.Input.Cursors]::Arrow
    }
}

function Export-VisibleResults {
    if (-not $script:VisibleResults -or $script:VisibleResults.Count -eq 0) {
        [System.Windows.MessageBox]::Show('There are no visible results to export.', 'Nothing to Export', 'OK', 'Information') | Out-Null
        return
    }

    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Title = 'Export visible results'
    $dialog.Filter = 'CSV Files (*.csv)|*.csv'
    $dialog.FileName = "BitLocker-Escrow-Visible-Results-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"

    if ($dialog.ShowDialog()) {
        try {
            $script:VisibleResults | Export-Csv -Path $dialog.FileName -NoTypeInformation -Encoding UTF8
            Write-UiLog "Exported visible results to $($dialog.FileName)." 'Success'
        }
        catch {
            Write-UiLog "Failed to export visible results: $($_.Exception.Message)" 'Error'
        }
    }
}

function Export-MissingOnly {
    $missing = @($script:AllResults | Where-Object { $_.Status -eq 'Missing Recovery Key - Action Required' })
    if (-not $missing -or $missing.Count -eq 0) {
        [System.Windows.MessageBox]::Show('There are no missing-key devices to export.', 'Nothing to Export', 'OK', 'Information') | Out-Null
        return
    }

    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Title = 'Export missing-key devices'
    $dialog.Filter = 'CSV Files (*.csv)|*.csv'
    $dialog.FileName = "BitLocker-Escrow-Missing-Only-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"

    if ($dialog.ShowDialog()) {
        try {
            $missing | Export-Csv -Path $dialog.FileName -NoTypeInformation -Encoding UTF8
            Write-UiLog "Exported missing-key devices to $($dialog.FileName)." 'Success'
        }
        catch {
            Write-UiLog "Failed to export missing-key devices: $($_.Exception.Message)" 'Error'
        }
    }
}


function Configure-ResultsGrid {
    $gridResults.AutoGenerateColumns = $false
    $gridResults.Columns.Clear()

    $columns = @(
        @{ Header = 'Device Name'; Binding = 'DeviceName'; Width = 170 },
        @{ Header = 'User'; Binding = 'UserPrincipalName'; Width = 190 },
        @{ Header = 'Serial Number'; Binding = 'SerialNumber'; Width = 120 },
        @{ Header = 'Manufacturer'; Binding = 'Manufacturer'; Width = 110 },
        @{ Header = 'Model'; Binding = 'Model'; Width = 220 },
        @{ Header = 'OS'; Binding = 'OperatingSystem'; Width = 80 },
        @{ Header = 'Azure AD Device ID'; Binding = 'AzureADDeviceId'; Width = 260 },
        @{ Header = 'Last Sync'; Binding = 'LastSyncDateTime'; Width = 150 },
        @{ Header = 'Recovery Key Count'; Binding = 'RecoveryKeyCount'; Width = 120 },
        @{ Header = 'Latest Key Backup'; Binding = 'LatestRecoveryKeyBackup'; Width = 160 },
        @{ Header = 'Status'; Binding = 'Status'; Width = 220 }
    )

    foreach ($def in $columns) {
        $col = New-Object System.Windows.Controls.DataGridTextColumn
        $col.Header = $def.Header
        $col.Binding = New-Object System.Windows.Data.Binding($def.Binding)
        $col.Width = $def.Width
        $gridResults.Columns.Add($col) | Out-Null
    }

    $style = New-Object System.Windows.Style([System.Windows.Controls.DataGridRow])
    $style.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::ForegroundProperty, [System.Windows.Media.Brushes]::White)))

    $greenTrigger = New-Object System.Windows.DataTrigger
    $greenTrigger.Binding = New-Object System.Windows.Data.Binding('Status')
    $greenTrigger.Value = 'Protected / Key Escrowed'
    $greenTrigger.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::ForegroundProperty, [System.Windows.Media.Brushes]::LightGreen)))
    $style.Triggers.Add($greenTrigger)

    $redTrigger = New-Object System.Windows.DataTrigger
    $redTrigger.Binding = New-Object System.Windows.Data.Binding('Status')
    $redTrigger.Value = 'Missing Recovery Key - Action Required'
    $redTrigger.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::ForegroundProperty, [System.Windows.Media.Brushes]::Tomato)))
    $style.Triggers.Add($redTrigger)

    $gridResults.RowStyle = $style
}

function Save-HtmlReport {
    if (-not $script:AllResults -or $script:AllResults.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Run the report first before creating an HTML report.', 'No Report Data', 'OK', 'Information') | Out-Null
        return
    }

    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Title = 'Save HTML report'
    $dialog.Filter = 'HTML Files (*.html)|*.html'
    $dialog.FileName = "BitLocker-Escrow-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

    if ($dialog.ShowDialog()) {
        try {
            $rows = foreach ($item in $script:AllResults) {
                $rowClass = if ($item.Status -eq 'Protected / Key Escrowed') { 'status-green' } else { 'status-red' }
                $lastSync = if ($item.LastSyncDateTime) { [datetime]$item.LastSyncDateTime } else { $null }
                $latestBackup = if ($item.LatestRecoveryKeyBackup) { [datetime]$item.LatestRecoveryKeyBackup } else { $null }
                @"
<tr class="$rowClass">
<td>$([System.Net.WebUtility]::HtmlEncode($item.DeviceName))</td>
<td>$([System.Net.WebUtility]::HtmlEncode($item.UserPrincipalName))</td>
<td>$([System.Net.WebUtility]::HtmlEncode($item.SerialNumber))</td>
<td>$([System.Net.WebUtility]::HtmlEncode($item.Manufacturer))</td>
<td>$([System.Net.WebUtility]::HtmlEncode($item.Model))</td>
<td>$([System.Net.WebUtility]::HtmlEncode($item.AzureADDeviceId))</td>
<td>$([System.Net.WebUtility]::HtmlEncode([string]$item.RecoveryKeyCount))</td>
<td>$([System.Net.WebUtility]::HtmlEncode($(if ($latestBackup) { $latestBackup.ToString('yyyy-MM-dd HH:mm:ss') } else { '' })))</td>
<td>$([System.Net.WebUtility]::HtmlEncode($(if ($lastSync) { $lastSync.ToString('yyyy-MM-dd HH:mm:ss') } else { '' })))</td>
<td>$([System.Net.WebUtility]::HtmlEncode($item.Status))</td>
</tr>
"@
            }

            $coverageText = if ($script:Summary.TotalLaptops -gt 0) { '{0:N1}%' -f $script:Summary.Coverage } else { '0.0%' }
            $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title>CHP BitLocker Escrow Report</title>
<style>
body { font-family: Segoe UI, Arial, sans-serif; background: #0f172a; color: #e5e7eb; margin: 0; padding: 24px; }
.header { background: #111827; border: 1px solid #1f2937; border-radius: 18px; padding: 24px; margin-bottom: 20px; }
.brand { font-size: 30px; font-weight: 700; color: #ffffff; }
.subtitle { color: #93c5fd; margin-top: 6px; }
.meta { color: #9ca3af; margin-top: 8px; }
.cards { display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 18px; }
.card { background: #111827; border: 1px solid #1f2937; border-radius: 18px; padding: 18px; min-width: 210px; }
.card-title { color: #9ca3af; font-size: 13px; text-transform: uppercase; letter-spacing: .06em; }
.card-value { font-size: 34px; font-weight: 700; margin-top: 8px; }
.legend { background: #111827; border: 1px solid #1f2937; border-radius: 18px; padding: 16px; margin-bottom: 18px; }
.legend-item { display: inline-block; margin-right: 24px; font-size: 14px; }
.badge { display: inline-block; width: 14px; height: 14px; border-radius: 50%; margin-right: 8px; vertical-align: middle; }
.green { background: #10b981; }
.yellow { background: #f59e0b; }
.red { background: #ef4444; }
.table-wrap { background: #111827; border: 1px solid #1f2937; border-radius: 18px; padding: 16px; overflow-x: auto; }
table { width: 100%; border-collapse: collapse; font-size: 13px; }
th, td { padding: 10px 12px; border-bottom: 1px solid #243041; text-align: left; }
th { color: #93c5fd; position: sticky; top: 0; background: #111827; }
.status-green td:last-child { color: #10b981; font-weight: 700; }
.status-red td:last-child { color: #ef4444; font-weight: 700; }
.footer { color: #94a3b8; font-size: 12px; margin-top: 16px; }
</style>
</head>
<body>
<div class="header">
  <div class="brand">Community Housing Partners - BitLocker Escrow Report</div>
  <div class="subtitle">Generated from Microsoft Graph managed devices and BitLocker recovery key metadata</div>
  <div class="meta">Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
</div>
<div class="cards">
  <div class="card"><div class="card-title">Total Laptops</div><div class="card-value">$($script:Summary.TotalLaptops)</div></div>
  <div class="card"><div class="card-title">Protected / Key Escrowed</div><div class="card-value" style="color:#10b981;">$($script:Summary.Protected)</div></div>
  <div class="card"><div class="card-title">Missing Recovery Key</div><div class="card-value" style="color:#ef4444;">$($script:Summary.Missing)</div></div>
  <div class="card"><div class="card-title">Coverage</div><div class="card-value" style="color:#93c5fd;">$coverageText</div></div>
</div>
<div class="legend">
  <strong>Status legend:</strong><br /><br />
  <span class="legend-item"><span class="badge green"></span>Protected / Key Escrowed</span>
  <span class="legend-item"><span class="badge yellow"></span>Coverage metric / informational summary</span>
  <span class="legend-item"><span class="badge red"></span>Missing Recovery Key - Action Required</span>
</div>
<div class="table-wrap">
<table>
<thead>
<tr>
<th>Device Name</th>
<th>User</th>
<th>Serial Number</th>
<th>Manufacturer</th>
<th>Model</th>
<th>Azure AD Device ID</th>
<th>Recovery Key Count</th>
<th>Latest Recovery Key Backup</th>
<th>Last Sync</th>
<th>Status</th>
</tr>
</thead>
<tbody>
$($rows -join "`n")
</tbody>
</table>
</div>
<div class="footer">Filter logic used for total laptops: Windows devices, serial number present, model present, model does not contain 'Virtual Machine'.</div>
</body>
</html>
"@
            Set-Content -Path $dialog.FileName -Value $html -Encoding UTF8
            Write-UiLog "Saved HTML report to $($dialog.FileName)." 'Success'
        }
        catch {
            Write-UiLog "Failed to save HTML report: $($_.Exception.Message)" 'Error'
            Show-UiError -Title 'HTML Export Error' -Message "Failed to save the HTML report.`n`n$($_.Exception.Message)"
        }
    }
}

[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="CHP BitLocker Escrow Report"
    Height="980"
    Width="1480"
    MinHeight="820"
    MinWidth="1240"
    WindowStartupLocation="CenterScreen"
    Background="#0F172A"
    Foreground="White"
    FontFamily="Segoe UI">
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="14"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="14"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="14"/>
            <RowDefinition Height="2*" MinHeight="260"/>
            <RowDefinition Height="8"/>
            <RowDefinition Height="*" MinHeight="180"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="#111827" CornerRadius="18" Padding="24" BorderBrush="#1F2937" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel>
                    <TextBlock Text="Community Housing Partners" FontSize="16" Foreground="#93C5FD" FontWeight="SemiBold"/>
                    <TextBlock Text="BitLocker Escrow Coverage Report" FontSize="30" FontWeight="SemiBold"/>
                    <TextBlock Margin="0,8,0,0" Foreground="#9CA3AF" FontSize="14" Text="Review Windows laptops, identify devices missing escrowed BitLocker recovery keys, and export remediation-ready results."/>
                    <TextBlock x:Name="lblLastRun" Margin="0,10,0,0" Foreground="#94A3B8" Text="Last refresh: not yet run"/>
                </StackPanel>
                <Border Grid.Column="1" Background="#0B5ED7" CornerRadius="12" Padding="18,12" VerticalAlignment="Center">
                    <StackPanel>
                        <TextBlock Text="Microsoft Graph" FontWeight="SemiBold" HorizontalAlignment="Center"/>
                        <TextBlock x:Name="lblConnectionStatus" Text="Not connected" Foreground="Orange" Margin="0,5,0,0" HorizontalAlignment="Center"/>
                    </StackPanel>
                </Border>
            </Grid>
        </Border>

        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="2.3*"/>
                <ColumnDefinition Width="14"/>
                <ColumnDefinition Width="1.2*"/>
            </Grid.ColumnDefinitions>

            <Border Grid.Column="0" Background="#111827" CornerRadius="18" Padding="22" BorderBrush="#1F2937" BorderThickness="1">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="12"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="12"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <StackPanel Grid.Row="0">
                        <TextBlock Text="Actions" FontSize="20" FontWeight="SemiBold"/>
                        <TextBlock Margin="0,6,0,0" Foreground="#9CA3AF" Text="Connect to Graph, run the report, filter the results, and export CSV or HTML outputs."/>
                    </StackPanel>
                    <WrapPanel Grid.Row="2">
                        <Button x:Name="btnConnect" Content="Connect to Graph" Width="160" Height="42" Margin="0,0,10,10" Background="#2563EB" Foreground="White" BorderBrush="#2563EB" FontWeight="SemiBold"/>
                        <Button x:Name="btnRun" Content="Run Report" Width="130" Height="42" Margin="0,0,10,10" Background="#10B981" Foreground="White" BorderBrush="#10B981" FontWeight="SemiBold"/>
                        <Button x:Name="btnExportVisible" Content="Export Visible CSV" Width="155" Height="42" Margin="0,0,10,10" Background="#334155" Foreground="White" BorderBrush="#334155" FontWeight="SemiBold"/>
                        <Button x:Name="btnExportMissing" Content="Export Missing Only" Width="160" Height="42" Margin="0,0,10,10" Background="#7C3AED" Foreground="White" BorderBrush="#7C3AED" FontWeight="SemiBold"/>
                        <Button x:Name="btnSaveHtml" Content="Save HTML Report" Width="150" Height="42" Margin="0,0,10,10" Background="#F59E0B" Foreground="Black" BorderBrush="#F59E0B" FontWeight="SemiBold"/>
                    </WrapPanel>
                    <WrapPanel Grid.Row="4" VerticalAlignment="Center">
                        <TextBlock Text="Search:" VerticalAlignment="Center" Margin="0,0,10,0" FontWeight="SemiBold"/>
                        <TextBox x:Name="txtSearch" Width="280" Height="36" Margin="0,0,12,0" Background="White" Foreground="Black" BorderBrush="#243041" Padding="8"/>
                        <CheckBox x:Name="chkMissingOnly" Content="Show missing only" VerticalAlignment="Center" Margin="0,0,12,0" Foreground="White" FontWeight="SemiBold"/>
                        <TextBlock x:Name="lblVisibleCount" Text="Visible devices: 0" VerticalAlignment="Center" Foreground="#9CA3AF" FontWeight="SemiBold"/>
                    </WrapPanel>
                </Grid>
            </Border>

            <Border Grid.Column="2" Background="#111827" CornerRadius="18" Padding="22" BorderBrush="#1F2937" BorderThickness="1">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="12"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="14"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <StackPanel Grid.Row="0">
                        <TextBlock Text="Status Legend" FontSize="20" FontWeight="SemiBold"/>
                        <TextBlock Margin="0,6,0,0" Foreground="#9CA3AF" Text="Use this guide when reviewing the dashboard or exported HTML report."/>
                    </StackPanel>
                    <StackPanel Grid.Row="2" Margin="0,4,0,0">
                        <WrapPanel Margin="0,0,0,8"><Ellipse Width="14" Height="14" Fill="#10B981" Margin="0,3,10,0"/><TextBlock Text="Protected / Key Escrowed" FontWeight="SemiBold"/></WrapPanel>
                        <WrapPanel Margin="0,0,0,8"><Ellipse Width="14" Height="14" Fill="#F59E0B" Margin="0,3,10,0"/><TextBlock Text="Coverage / informational summary" FontWeight="SemiBold"/></WrapPanel>
                        <WrapPanel><Ellipse Width="14" Height="14" Fill="#EF4444" Margin="0,3,10,0"/><TextBlock Text="Missing Recovery Key - Action Required" FontWeight="SemiBold"/></WrapPanel>
                    </StackPanel>
                    <TextBlock Grid.Row="4" Foreground="#94A3B8" TextWrapping="Wrap" Text="Reporting logic for Total Laptops: Windows devices only, serial number present, model present, and model does not contain 'Virtual Machine'."/>
                </Grid>
            </Border>
        </Grid>

        <Grid Grid.Row="4">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="14"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="14"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="14"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <Border Grid.Column="0" Background="#111827" CornerRadius="18" Padding="18" BorderBrush="#1F2937" BorderThickness="1">
                <StackPanel>
                    <TextBlock Text="Total Laptops" Foreground="#9CA3AF" FontWeight="SemiBold"/>
                    <TextBlock x:Name="lblTotalValue" Text="0" FontSize="34" FontWeight="Bold" Margin="0,8,0,0"/>
                </StackPanel>
            </Border>
            <Border Grid.Column="2" Background="#111827" CornerRadius="18" Padding="18" BorderBrush="#1F2937" BorderThickness="1">
                <StackPanel>
                    <TextBlock Text="Protected / Key Escrowed" Foreground="#9CA3AF" FontWeight="SemiBold"/>
                    <TextBlock x:Name="lblProtectedValue" Text="0" FontSize="34" FontWeight="Bold" Foreground="#10B981" Margin="0,8,0,0"/>
                </StackPanel>
            </Border>
            <Border Grid.Column="4" Background="#111827" CornerRadius="18" Padding="18" BorderBrush="#1F2937" BorderThickness="1">
                <StackPanel>
                    <TextBlock Text="Missing Recovery Key" Foreground="#9CA3AF" FontWeight="SemiBold"/>
                    <TextBlock x:Name="lblMissingValue" Text="0" FontSize="34" FontWeight="Bold" Foreground="#EF4444" Margin="0,8,0,0"/>
                </StackPanel>
            </Border>
            <Border Grid.Column="6" Background="#111827" CornerRadius="18" Padding="18" BorderBrush="#1F2937" BorderThickness="1">
                <StackPanel>
                    <TextBlock Text="Coverage" Foreground="#9CA3AF" FontWeight="SemiBold"/>
                    <TextBlock x:Name="lblCoverageValue" Text="0.0%" FontSize="34" FontWeight="Bold" Foreground="#93C5FD" Margin="0,8,0,0"/>
                </StackPanel>
            </Border>
        </Grid>

        <Border Grid.Row="6" Background="#111827" CornerRadius="18" Padding="18" BorderBrush="#1F2937" BorderThickness="1">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="12"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <StackPanel Grid.Row="0" Orientation="Horizontal">
                    <TextBlock Text="Device Results" FontSize="20" FontWeight="SemiBold"/>
                    <TextBlock Margin="14,4,0,0" Foreground="#9CA3AF" Text="Devices missing recovery keys can be exported directly for remediation. Drag the splitter below to resize this section."/>
                </StackPanel>
                <DataGrid x:Name="gridResults" Grid.Row="2" AutoGenerateColumns="False" CanUserAddRows="False" IsReadOnly="True" HeadersVisibility="Column" GridLinesVisibility="Horizontal" RowBackground="#0F172A" AlternatingRowBackground="#111B2F" Background="#0B1220" Foreground="White" BorderBrush="#243041" BorderThickness="1" CanUserResizeColumns="True" CanUserReorderColumns="True" ColumnWidth="SizeToHeader" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"/>
            </Grid>
        </Border>

        <GridSplitter Grid.Row="7" Height="8" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Background="#1F2937" ResizeDirection="Rows" ResizeBehavior="PreviousAndNext" ShowsPreview="True"/>

        <Border Grid.Row="8" Background="#111827" CornerRadius="18" Padding="18" BorderBrush="#1F2937" BorderThickness="1">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="12"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <TextBlock Grid.Row="0" Text="Activity Log" FontSize="20" FontWeight="SemiBold"/>
                <TextBox x:Name="txtLog" Grid.Row="2" IsReadOnly="True" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="Wrap" Background="#0B1220" Foreground="#D1FAE5" BorderBrush="#243041" BorderThickness="1" Padding="12" FontFamily="Consolas" FontSize="13"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$lblConnectionStatus = $window.FindName('lblConnectionStatus')
$lblLastRun          = $window.FindName('lblLastRun')
$lblTotalValue       = $window.FindName('lblTotalValue')
$lblProtectedValue   = $window.FindName('lblProtectedValue')
$lblMissingValue     = $window.FindName('lblMissingValue')
$lblCoverageValue    = $window.FindName('lblCoverageValue')
$lblVisibleCount     = $window.FindName('lblVisibleCount')
$txtSearch           = $window.FindName('txtSearch')
$chkMissingOnly      = $window.FindName('chkMissingOnly')
$gridResults         = $window.FindName('gridResults')
$txtLog              = $window.FindName('txtLog')
$btnConnect          = $window.FindName('btnConnect')
$btnRun              = $window.FindName('btnRun')
$btnExportVisible    = $window.FindName('btnExportVisible')
$btnExportMissing    = $window.FindName('btnExportMissing')
$btnSaveHtml         = $window.FindName('btnSaveHtml')

$txtSearch.Add_TextChanged({ Apply-ResultFilter })
$chkMissingOnly.Add_Click({ Apply-ResultFilter })
$btnConnect.Add_Click({ Connect-GraphForReport })
$btnRun.Add_Click({ Run-Report })
$btnExportVisible.Add_Click({ Export-VisibleResults })
$btnExportMissing.Add_Click({ Export-MissingOnly })
$btnSaveHtml.Add_Click({ Save-HtmlReport })

Configure-ResultsGrid
Update-SummaryCards
Write-UiLog 'Ready. Connect to Microsoft Graph to build the BitLocker escrow report.' 'Info'
$null = $window.ShowDialog()
