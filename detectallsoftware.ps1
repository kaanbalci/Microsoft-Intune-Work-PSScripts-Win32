<# 
.SYNOPSIS
  Intune app inventory summary across Windows, iOS/iPadOS, Android:
  AppName | Version | OS | DeviceCount

.REQUIREMENTS
  PowerShell 7+
  Microsoft.Graph PowerShell SDK
  Graph delegated scopes: DeviceManagementManagedDevices.Read.All, DeviceManagementApps.Read.All
#>

param(
  [string]$Csv = ""   # e.g. "C:\Temp\Intune-AppInventory.csv"
)

# -----------------------------
# Quiet module import
# -----------------------------
$prev = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
if (-not (Get-Module -ListAvailable Microsoft.Graph)) {
  Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
}
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.DeviceManagement
$ErrorActionPreference = $prev

Write-Host "[INFO] Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes @(
  'DeviceManagementManagedDevices.Read.All',
  'DeviceManagementApps.Read.All'
)

# -----------------------------
# Helpers
# -----------------------------
function Invoke-GraphJson {
  param(
    [Parameter(Mandatory)] [string]$Method,
    [Parameter(Mandatory)] [string]$Uri
  )
  try {
    return Invoke-MgGraphRequest -Method $Method -Uri $Uri -OutputType Json -ErrorAction Stop
  } catch {
    $msg = $_.Exception.Message
    Write-Host "[WARN] $Method $Uri failed: $msg" -ForegroundColor Yellow
    return $null
  }
}

# Aggregate structure: key = "{OS}|{Name}|{Version}"  -> HashSet of DeviceIds
$byApp = @{}
function Add-AppSeen {
  param(
    [string]$Os, [string]$Name, [string]$Version, [string]$DeviceId
  )
  if ([string]::IsNullOrWhiteSpace($Name)) { return }
  $os = ($Os -as [string]); if ([string]::IsNullOrWhiteSpace($os)) { $os = "Unknown" }
  $ver = ($Version -as [string]); if ($null -eq $ver) { $ver = "" }

  $key = "{0}|{1}|{2}" -f $os.ToUpper(), $Name.Trim(), $ver.Trim()
  if (-not $byApp.ContainsKey($key)) {
    $byApp[$key] = [System.Collections.Generic.HashSet[string]]::new()
  }
  if ($DeviceId) { [void]$byApp[$key].Add($DeviceId) }
}

# -----------------------------
# WINDOWS: detectedApps (v1.0)
# -----------------------------
Write-Host "[INFO] Gathering Windows detected apps..." -ForegroundColor Cyan
$winDetected = @()
try {
  $winDetected = Get-MgDeviceManagementDetectedApp -All `
                -Property displayName,version,deviceCount,platform
} catch {
  Write-Host "[WARN] Get-MgDeviceManagementDetectedApp failed; falling back to REST." -ForegroundColor Yellow
  $url = "https://graph.microsoft.com/v1.0/deviceManagement/detectedApps`?$select=displayName,version,deviceCount,platform"
  $resp = Invoke-GraphJson -Method GET -Uri $url
  if ($resp -and $resp.value) { $winDetected = $resp.value }
}

foreach ($app in $winDetected) {
  # deviceCount is already aggregated across Windows endpoints
  $name = $app.displayName
  $ver  = $app.version
  $cnt  = [int]($app.deviceCount)
  if ([string]::IsNullOrWhiteSpace($name) -or $cnt -le 0) { continue }

  # Represent Windows entries by adding a synthetic set of N placeholders to reach the count.
  # (We keep counting behavior consistent with mobile, where we count distinct devices.)
  $key = "WINDOWS|{0}|{1}" -f $name.Trim(), ($ver -as [string]).Trim()
  if (-not $byApp.ContainsKey($key)) {
    $byApp[$key] = [System.Collections.Generic.HashSet[string]]::new()
  }
  # Add N placeholders (deterministic)
  for ($i=1; $i -le $cnt; $i++) { [void]$byApp[$key].Add("win-$($name.GetHashCode())-$($ver.GetHashCode())-$i") }
}

# -----------------------------
# ALL DEVICES (for mobile inventory)
# -----------------------------
Write-Host "[INFO] Retrieving managed devices list..." -ForegroundColor Cyan
$devices = Get-MgDeviceManagementManagedDevice -All -Property id,deviceName,operatingSystem,managementAgent
if (-not $devices) {
  Write-Host "[ERROR] No managed devices returned; stopping." -ForegroundColor Red
  return
}

$mobile = $devices | Where-Object { $_.operatingSystem -match 'Android|iOS|iPadOS' }
if (-not $mobile -or $mobile.Count -eq 0) {
  Write-Host "[INFO] No Android/iOS/iPadOS devices found (or not returned by RBAC scope)." -ForegroundColor Yellow
} else {
  Write-Host ("[INFO] Collecting installed apps from {0} mobile devices (beta)..." -f $mobile.Count) -ForegroundColor Cyan
}

# iOS/iPadOS/Android app inventory (beta):
#   GET https://graph.microsoft.com/beta/deviceManagement/managedDevices/{id}/installedApps
# Not all tenants / management modes surface inventory. We skip quietly on 404/403 and continue.
$processed = 0
foreach ($d in $mobile) {
  $processed++
  if ($processed % 25 -eq 0) {
    Write-Host ("[INFO] Processed {0}/{1} mobile devices..." -f $processed, $mobile.Count)
  }

  $did = $d.Id
  $os  = $d.operatingSystem
  $url = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$did/installedApps`?$select=displayName,version"
  $resp = Invoke-GraphJson -Method GET -Uri $url
  if (-not $resp -or -not $resp.value) { continue }

  foreach ($app in $resp.value) {
    $name = $app.displayName
    $ver  = $app.version
    Add-AppSeen -Os $os -Name $name -Version $ver -DeviceId $did
  }
}

# -----------------------------
# Build final table
# -----------------------------
$rows = foreach ($k in $byApp.Keys) {
  $parts = $k.Split('|',3)
  [pscustomobject]@{
    OS          = $parts[0]
    Name        = $parts[1]
    Version     = $parts[2]
    DeviceCount = $byApp[$k].Count
  }
}

$sorted = $rows |
  Where-Object { $_.DeviceCount -gt 0 } |
  Sort-Object OS, Name, Version

# Output
$sorted | Format-Table -AutoSize

if ($Csv) {
  try {
    $sorted | Export-Csv -Path $Csv -NoTypeInformation -Encoding UTF8
    Write-Host "[OK] CSV exported to $Csv" -ForegroundColor Green
  } catch {
    Write-Host "[WARN] Failed to write CSV: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

Write-Host "[DONE] App inventory summary complete." -ForegroundColor Cyan
