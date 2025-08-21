<#
.SYNOPSIS
    Bootstrap installer for ConvertVTTAssets module.
.DESCRIPTION
    - Ensures C:\PowerShell-Scripts is on PSModulePath (User scope)
    - Unblocks module files
    - Adds Import-Module to your CurrentUserAllHosts profile (idempotent)
    - Imports the module and prints status
#>

$moduleRoot = "C:\PowerShell-Scripts\ConvertVTTAssets"
$modulesPath = "C:\PowerShell-Scripts"
$manifestPath = Join-Path $moduleRoot "ConvertVTTAssets.psd1"

if (-not (Test-Path $moduleRoot)) {
    Write-Error "Module folder not found at $moduleRoot. Make sure you've extracted the zip to C:\PowerShell-Scripts\ConvertVTTAssets"
    exit 1
}

# 1) Ensure PSModulePath includes C:\PowerShell-Scripts
$paths = $env:PSModulePath -split ';'
if ($paths -notcontains $modulesPath) {
    [Environment]::SetEnvironmentVariable('PSModulePath', "$($env:PSModulePath);$modulesPath", 'User')
    $env:PSModulePath = "$($env:PSModulePath);$modulesPath"
    Write-Host "Added $modulesPath to User PSModulePath. Restart PowerShell to ensure full autoload behavior." -ForegroundColor Yellow
}

# 2) Unblock downloaded files
Get-ChildItem -LiteralPath $moduleRoot -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
Write-Host "Unblocked all module files." -ForegroundColor Green

# 3) Add profile import block (CurrentUserAllHosts), idempotent
$prof = $PROFILE.CurrentUserAllHosts
if (!(Test-Path $prof)) { 
    $profileDir = Split-Path $prof -Parent
    if (!(Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    New-Item -ItemType File -Path $prof -Force | Out-Null 
}

$block = @'
# --- ConvertVTTAssets autoload ---
$vttManifest = "C:\PowerShell-Scripts\ConvertVTTAssets\ConvertVTTAssets.psd1"
if (Test-Path $vttManifest) {
    Import-Module $vttManifest -ErrorAction SilentlyContinue
}
# --- end ConvertVTTAssets autoload ---
'@

# Only append if not already present
$profileText = Get-Content -LiteralPath $prof -Raw -ErrorAction SilentlyContinue
if ($null -eq $profileText -or $profileText -notmatch 'ConvertVTTAssets autoload') {
    Add-Content -LiteralPath $prof -Value "`n$block`n"
    Write-Host "Added autoload block to profile: $prof" -ForegroundColor Green
} else {
    Write-Host "Profile already contains ConvertVTTAssets autoload block." -ForegroundColor DarkGray
}

# 4) Try importing now using full path
if (Get-Module ConvertVTTAssets) {
    Remove-Module ConvertVTTAssets -Force
}

Import-Module $manifestPath -Force -ErrorAction Stop

if (Get-Module ConvertVTTAssets) {
    $module = Get-Module ConvertVTTAssets
    Write-Host "`nConvertVTTAssets v$($module.Version) imported successfully!" -ForegroundColor Green
    Write-Host "`nAvailable commands:" -ForegroundColor Cyan
    Get-Command -Module ConvertVTTAssets | Format-Table -Property Name, CommandType -AutoSize
    
    Write-Host "`nQuick Start:" -ForegroundColor Yellow
    Write-Host "  Optimize-FileNames -Root 'C:\YourPath' -WhatIf" -ForegroundColor Gray
    Write-Host "  Convert-ToWebM -Root 'C:\YourPath' -OutputRoot 'C:\Output'" -ForegroundColor Gray
    Write-Host "  Convert-ToWebP -Root 'C:\YourPath' -OutputRoot 'C:\Output'" -ForegroundColor Gray
    Write-Host "`nUse Get-Help <command> -Detailed for more information." -ForegroundColor Gray
} else {
    Write-Host "Module import failed. Please check for errors above." -ForegroundColor Red
}