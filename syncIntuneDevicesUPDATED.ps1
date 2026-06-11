<#
.SYNOPSIS
  Sync Intune devices (All, iOS, Android, Windows, or targeted names)
  - Uses native SyncDevice cmdlet if available; otherwise REST fallback
  - Quiet imports; real runtime errors only
  - Local-first selection for Option 5 (name pattern) and Option 6 (lists)
  - Server-side near-match discovery + pre-flight ID resolution
  - Strong lists to avoid string coercion
  - Summary report and optional CSV export
  Author: Kaan Balci | Updated: 2025-10-16
#>

# =========================
#   INITIAL SETUP (quiet)
# =========================
$prevErrorPref = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'   # import-time noise only

if (-not (Get-Module -ListAvailable Microsoft.Graph)) {
    Write-Host "[INFO] Installing Microsoft Graph..." -ForegroundColor Yellow
    Install-Module Microsoft.Graph -Force -AllowClobber -Scope CurrentUser
}

Import-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
Import-Module Microsoft.Graph.DeviceManagement   -ErrorAction SilentlyContinue

$ErrorActionPreference = $prevErrorPref

# =========================
#   CONNECT TO GRAPH
# =========================
Write-Host "`n[INFO] Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.ReadWrite.All"

# =========================
#   DETECT SYNC METHOD
# =========================
$Script:SyncCmd = Get-Command -Name "Invoke-MgDeviceManagementManagedDeviceSyncDevice" -ErrorAction SilentlyContinue
if ($Script:SyncCmd) { Write-Host "[INFO] Using native SyncDevice cmdlet." -ForegroundColor Green }
else                 { Write-Host "[WARN] Native SyncDevice cmdlet not found. Using REST API fallback." -ForegroundColor Yellow }

# =========================
#   HELPERS
# =========================
function Invoke-DeviceSync {
    param([Parameter(Mandatory)][string]$ManagedDeviceId)
    if ($Script:SyncCmd) {
        Invoke-MgDeviceManagementManagedDeviceSyncDevice -ManagedDeviceId $ManagedDeviceId
    } else {
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$ManagedDeviceId/syncDevice"
        Invoke-MgGraphRequest -Method POST -Uri $uri
    }
}

function Search-ManagedDevicesByName {
    <#
      Server-side search (returns real managedDevice objects with Id):
        1) deviceName eq 'X'
        2) startsWith(deviceName,'X')
        3) contains(deviceName,'X')
    #>
    param([Parameter(Mandatory)][string]$Name, [int]$Top = 25)
    $escaped = $Name.Replace("'", "''")
    $bag = New-Object System.Collections.Generic.List[object]

    try {
        $eq = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$escaped'" -ConsistencyLevel eventual -CountVariable _ -Top 1
        if ($eq) { [void]$bag.Add($eq) }
    } catch {}

    if ($bag.Count -eq 0) {
        try {
            $sw = Get-MgDeviceManagementManagedDevice -Filter "startsWith(deviceName,'$escaped')" -ConsistencyLevel eventual -CountVariable _ -Top $Top
            if ($sw) { $sw | ForEach-Object { [void]$bag.Add($_) } }
        } catch {}
    }

    if ($bag.Count -eq 0) {
        try {
            $ct = Get-MgDeviceManagementManagedDevice -Filter "contains(deviceName,'$escaped')" -ConsistencyLevel eventual -CountVariable _ -Top $Top
            if ($ct) { $ct | ForEach-Object { [void]$bag.Add($_) } }
        } catch {}
    }

    if ($bag.Count -gt 0) {
        $seen = New-Object System.Collections.Generic.HashSet[string]
        $out  = New-Object System.Collections.Generic.List[object]
        foreach ($d in $bag) { if ($d.Id -and $seen.Add($d.Id)) { [void]$out.Add($d) } }
        return $out.ToArray()
    }
    return @()
}

function Get-ManagedDeviceIdSafe {
    param([Parameter(Mandatory)][object]$Device)

    if ($Device -and -not [string]::IsNullOrWhiteSpace($Device.Id)) { return $Device.Id }

    if ($Device -is [string] -and $Device.Length -gt 0) {
        $cands = Search-ManagedDevicesByName -Name $Device -Top 10
        if ($cands.Count -gt 0) { return $cands[0].Id }
    }

    if (-not [string]::IsNullOrWhiteSpace($Device.DeviceName)) {
        $cands = Search-ManagedDevicesByName -Name $Device.DeviceName -Top 10
        if ($cands.Count -gt 0) {
            $exact = $cands | Where-Object { $_.DeviceName -ieq $Device.DeviceName }
            if ($exact) { return $exact[0].Id }
            return $cands[0].Id
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Device.AzureADDeviceId)) {
        try {
            $found2 = Get-MgDeviceManagementManagedDevice -Filter "azureADDeviceId eq '$($Device.AzureADDeviceId)'" -Top 1
            if ($found2 -and -not [string]::IsNullOrWhiteSpace($found2.Id)) { return $found2.Id }
        } catch {}
    }

    return $null
}

function SelectFromList {
    param([Parameter(Mandatory)][object[]]$Items)
    $idx = 0
    foreach ($r in $Items) { $idx++; Write-Host ("{0,3}) {1}  [{2}]  (Id: {3})" -f $idx, $r.DeviceName, $r.OperatingSystem, $r.Id) }
    $sel = Read-Host "Enter numbers (e.g., 1,3,5-7) or 'A' for all"
    if ($sel -match '^[Aa]$') { return $Items }

    $indices = New-Object System.Collections.Generic.List[int]
    foreach ($token in ($sel -split ',')) {
        if ($token -match '^\s*\d+\s*-\s*\d+\s*$') {
            $parts = $token -split '-'
            $start = [int]$parts[0].Trim()
            $end   = [int]$parts[1].Trim()
            foreach ($n in $start..$end) { [void]$indices.Add($n) }
        } elseif ($token -match '^\s*\d+\s*$') {
            [void]$indices.Add([int]$token.Trim())
        }
    }

    $picked = New-Object System.Collections.Generic.List[object]
    foreach ($n in $indices) { if ($n -ge 1 -and $n -le $Items.Count) { [void]$picked.Add($Items[$n-1]) } }
    return $picked.ToArray()
}

# =========================
#   MAIN LOOP (menu → preflight → sync)
# =========================
while ($true) {
    # Inventory
    Write-Host "[INFO] Retrieving Intune devices..." -ForegroundColor Cyan
    $allDevices = Get-MgDeviceManagementManagedDevice -All
    if (-not $allDevices -or $allDevices.Count -eq 0) {
        Write-Host "[WARN] No devices returned from Graph. Check permissions/tenant or try again." -ForegroundColor Yellow
        break
    }
    $iOS     = $allDevices | Where-Object { $_.OperatingSystem -match "iOS" }
    $Android = $allDevices | Where-Object { $_.OperatingSystem -match "Android" }
    $Windows = $allDevices | Where-Object { $_.OperatingSystem -match "Windows" }

    # Uncomment to peek at naming:
    # ($Windows | Select-Object -First 10 DeviceName, Id) | Format-Table -AutoSize

    # Menu
    $target = $null
    while (-not $target) {
        $choice = Read-Host @"
What would you like to sync today?
1.) All Devices
2.) iOS
3.) Android
4.) Windows
5.) Specific device name (partial OK)  [local-first + server fallback]
6.) Paste list of names                [local-first per name + server fallback]
Select (1-6)
"@
        switch ($choice) {
            1 { $target = $allDevices }
            2 { $target = $iOS }
            3 { $target = $Android }
            4 { $target = $Windows }

            5 {
                $pattern = Read-Host "Enter device name (partial match allowed)"
                # Local-first search (real objects with Id)
                $localMatches = $allDevices | Where-Object { $_.DeviceName -and $_.DeviceName -like ("*" + $pattern + "*") }

                if ($localMatches -and $localMatches.Count -gt 0) {
                    Write-Host "`nLocal matches:" -ForegroundColor Cyan
                    $arrLocal = @($localMatches)
                    $picked   = SelectFromList -Items $arrLocal
                    if ($picked.Count -gt 0) { $target = $picked } else { Write-Host "[INFO] Nothing selected. Try again." -ForegroundColor Yellow }
                }
                else {
                    # Fallback to server-side query if local inventory doesn't show it
                    Write-Host "[INFO] No local matches — trying Graph search..." -ForegroundColor Yellow
                    $serverMatches = Search-ManagedDevicesByName -Name $pattern -Top 50
                    if ($serverMatches.Count -gt 0) {
                        Write-Host "`nServer matches:" -ForegroundColor Cyan
                        $picked = SelectFromList -Items $serverMatches
                        if ($picked.Count -gt 0) { $target = $picked } else { Write-Host "[INFO] Nothing selected. Try again." -ForegroundColor Yellow }
                    } else {
                        Write-Host ("[INFO] No devices found for '{0}'." -f $pattern) -ForegroundColor Yellow
                    }
                }
            }

            6 {
                Write-Host "Paste names (one per line, or comma/semicolon separated). Press ENTER twice when done." -ForegroundColor Cyan
                $lines = @()
                while ($true) {
                    $line = Read-Host
                    if ($line -eq "") { break }
                    $lines += $line
                }
                $rawNames = $lines | ForEach-Object { ($_ -split '[,;]') } | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                if (-not $rawNames -or $rawNames.Count -eq 0) { Write-Host "[INFO] No names provided." -ForegroundColor Yellow; continue }

                $accum = New-Object System.Collections.Generic.List[object]
                foreach ($name in $rawNames) {
                    # local-first for each name
                    $lm = $allDevices | Where-Object { $_.DeviceName -and $_.DeviceName -like ("*" + $name + "*") }
                    if ($lm -and $lm.Count -gt 0) {
                        foreach ($x in $lm) { [void]$accum.Add($x) }
                        continue
                    }
                    # server fallback per name
                    $found = Search-ManagedDevicesByName -Name $name -Top 10
                    if ($found.Count -gt 0) {
                        foreach ($f in $found) { [void]$accum.Add($f) }
                    } else {
                        Write-Host ("[WARN] No matches for '{0}'" -f $name) -ForegroundColor Yellow
                    }
                }

                if ($accum.Count -eq 0) {
                    Write-Host "[INFO] No matching devices found. Try again." -ForegroundColor Yellow
                    continue
                }

                # Show and confirm
                Write-Host "`nMatches (aggregated):" -ForegroundColor Cyan
                $arr = $accum.ToArray()
                $picked = SelectFromList -Items $arr
                if ($picked.Count -gt 0) { $target = $picked } else { Write-Host "[INFO] Nothing selected. Try again." -ForegroundColor Yellow }
            }

            default { Write-Host "Invalid choice. Try again." -ForegroundColor Red }
        }
    }

    # ---- PRE-FLIGHT VALIDATION ----
    Write-Host "`n[PRE-FLIGHT] Resolving ManagedDeviceId(s) for selected devices..." -ForegroundColor Cyan

    $preflight = foreach ($d in $target) {
        $rid = Get-ManagedDeviceIdSafe -Device $d
        [pscustomobject]@{
            DeviceName      = if ($d -is [string]) { $d } else { $d.DeviceName }
            OS              = if ($d -is [string]) { ""  } else { $d.OperatingSystem }
            ManagedDeviceId = $rid
        }
    }

    $resolved   = $preflight | Where-Object { -not [string]::IsNullOrWhiteSpace($_.ManagedDeviceId) }
    $unresolved = $preflight | Where-Object {  [string]::IsNullOrWhiteSpace($_.ManagedDeviceId) }

    Write-Host "`n[PRE-FLIGHT] Candidate devices (resolved IDs shown):" -ForegroundColor Cyan
    $preflight | Sort-Object DeviceName | Format-Table -Property DeviceName, OS, ManagedDeviceId -AutoSize

    $targetResolved = $null
    if ($unresolved.Count -gt 0) {
        Write-Host "`n[WARN] Some devices could not be resolved to a ManagedDeviceId." -ForegroundColor Yellow
        $choicePF = Read-Host "Proceed with RESOLVED only (P), Re-select (R), or Cancel (N)?"
        if     ($choicePF -match '^[Pp]$') { $targetResolved = $resolved }
        elseif ($choicePF -match '^[Rr]$') { Write-Host "[INFO] Returning to menu..."; continue }
        else   { Write-Host "[INFO] Cancelled."; break }
    } else {
        $go = Read-Host "All devices resolved. Proceed? (Y/N)"
        if ($go -notmatch '^[Yy]$') { Write-Host "[INFO] Cancelled."; break }
        $targetResolved = $resolved
    }

    if (-not $targetResolved -or $targetResolved.Count -eq 0) {
        Write-Host "[INFO] No resolvable devices to sync. Returning to menu." -ForegroundColor Yellow
        continue
    }

    # ---- SYNC LOOP ----
    $results   = New-Object System.Collections.Generic.List[object]
    $count     = 0
    $startTime = Get-Date

    foreach ($row in $targetResolved) {
        $count++
        $nameForLog = if ($row.DeviceName) { $row.DeviceName } else { "<no name>" }
        $idForUse   = $row.ManagedDeviceId

        $entry = [ordered]@{
            Index      = $count
            DeviceName = $nameForLog
            OS         = $row.OS
            Timestamp  = (Get-Date)
            Result     = ''
            Message    = ''
        }

        Write-Host ("[{0}] Syncing {1}..." -f $count, $nameForLog)
        try {
            if ([string]::IsNullOrWhiteSpace($idForUse)) {
                $idForUse = Get-ManagedDeviceIdSafe -Device $nameForLog
                if ([string]::IsNullOrWhiteSpace($idForUse)) { throw "No ManagedDeviceId available after pre-flight." }
            }

            Invoke-DeviceSync -ManagedDeviceId $idForUse
            Write-Host ("[{0}] ✅ Sync initiated for {1}" -f $count, $nameForLog) -ForegroundColor Green
            $entry.Result = 'Success'
        }
        catch {
            $msg = $_.Exception.Message
            Write-Host ("[{0}] ❌ ERROR syncing {1}: {2}" -f $count, $nameForLog, $msg) -ForegroundColor Red
            $entry.Result = 'Failed'
            $entry.Message = $msg
        }

        [void]$results.Add([pscustomobject]$entry)
        Start-Sleep -Seconds 1
    }

    # ---- SUMMARY ----
    $endTime   = Get-Date
    $success   = ($results | Where-Object { $_.Result -eq 'Success' }).Count
    $failed    = ($results | Where-Object { $_.Result -eq 'Failed'  }).Count
    $total     = $results.Count
    $failColor = if ($failed -gt 0) { 'Red' } else { 'Green' }

    Write-Host "`n[SUMMARY REPORT]" -ForegroundColor Cyan
    Write-Host ("-" * 60)
    Write-Host ("Started:  {0}" -f $startTime)
    Write-Host ("Finished: {0}" -f $endTime)
    Write-Host ("Duration: {0} minutes" -f ([math]::Round(($endTime - $startTime).TotalMinutes,2)))
    Write-Host ("Total Devices: {0}" -f $total)
    Write-Host ("Successful:    {0}" -f $success) -ForegroundColor Green
    Write-Host ("Failed:        {0}" -f $failed)  -ForegroundColor $failColor
    Write-Host ("-" * 60)

    # Optional CSV export:
    # $results | Export-Csv -Path "$env:USERPROFILE\Desktop\IntuneDeviceSyncReport.csv" -NoTypeInformation -Encoding UTF8

    Write-Host "`n[DONE] All selected device syncs completed." -ForegroundColor Cyan

    $again = Read-Host "Run another selection? (Y/N)"
    if ($again -notmatch '^[Yy]$') { break }
}

# End of script
