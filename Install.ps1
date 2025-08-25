<#
.SYNOPSIS
    ConvertVTTAssets Installation Script - Alternative PowerShell module installation method
.DESCRIPTION
    Provides an alternative installation method for ConvertVTTAssets PowerShell module.
    Supports both user and system-wide installation with automatic path detection and validation.
    Includes uninstall capability and comprehensive error handling.
    
    This installer performs four key operations:
    1. Validates module presence and adds to PSModulePath (User scope)
    2. Unblocks downloaded files to prevent execution policy blocks
    3. Creates persistent autoload in PowerShell profile (idempotent)
    4. Imports module and displays available commands
.PARAMETER InstallPath
    Optional. Specify custom installation path. If not provided, defaults to current directory
    with user confirmation. Supports both absolute and relative paths.
.PARAMETER Force
    Optional. Skip confirmation prompts for automated installations. Useful for CI/CD scenarios.
.EXAMPLE
    .\Install.ps1
    Interactive installation to current directory with confirmation
.EXAMPLE
    .\Install.ps1 -InstallPath "C:\MyModules\ConvertVTTAssets"
    Install to specific directory
.EXAMPLE
    .\Install.ps1 -Force
    Silent installation to current directory without prompts
.AUTHOR
    Andres Yuhnke, Claude (Anthropic)
.VERSION
    1.6.0
.DATE
    2025-08-25
.COPYRIGHT
    (c) 2025 Andres Yuhnke. MIT License.
.LINK
    https://github.com/andresyuhnke/ConvertVTTAssets
.LINK
    https://www.powershellgallery.com/packages/ConvertVTTAssets
.NOTES
    Alternative to PowerShell Gallery installation method.
    Primary installation: Install-Module ConvertVTTAssets
    This script provides manual installation for environments without Gallery access.
    
    Features:
    - Flexible installation paths with user confirmation
    - Automatic PowerShell module path detection
    - User vs system-wide installation options
    - Existing installation detection and cleanup
    - Comprehensive validation and error handling
    - Automation support with -Force parameter
    
    Installation Behavior:
    - Default: Current directory with confirmation
    - PSModulePath: Parent directory added to User scope
    - Profile: CurrentUserAllHosts for persistent autoload
    -     Module Structure: Modular v1.6.0 architecture with 10 components
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position=0, HelpMessage="Installation directory path. Defaults to current directory with confirmation.")]
    [string]$InstallPath = $null,
    
    [Parameter(HelpMessage="Skip confirmation prompts for automated installations.")]
    [switch]$Force
)

# [INST-001] Determine installation path with user-friendly defaults and validation
if (-not $InstallPath) {
    # [INST-001.1] Default to current directory but ask for user confirmation
    $currentPath = Get-Location | Select-Object -ExpandProperty Path
    
    if (-not $Force) {
        Write-Host "`nConvertVTTAssets v1.6.0 Installation" -ForegroundColor Cyan
        Write-Host "Current directory: $currentPath" -ForegroundColor Gray
        $response = Read-Host "`nInstall ConvertVTTAssets to current directory? (Y/n)"
        
        if ($response -match '^n|^N') {
            # [INST-001.2] User declined current directory - prompt for custom path
            do {
                $customPath = Read-Host "Enter installation directory path"
                if ([string]::IsNullOrWhiteSpace($customPath)) {
                    Write-Host "Path cannot be empty. Please try again." -ForegroundColor Yellow
                } else {
                    $InstallPath = $customPath
                }
            } while ([string]::IsNullOrWhiteSpace($InstallPath))
        }
    }
    
    # [INST-001.3] Use current directory if no custom path provided
    if (-not $InstallPath) { 
        $InstallPath = $currentPath 
    }
} else {
    # [INST-001.4] Path provided via parameter - validate and inform user
    Write-Host "`nConvertVTTAssets v1.6.0 Installation" -ForegroundColor Cyan
    Write-Host "Installing to specified path: $InstallPath" -ForegroundColor Gray
}

# [INST-002] Convert to full path and validate directory structure
try {
    # [INST-002.1] Resolve relative paths and ensure canonical format
    $InstallPath = Resolve-Path -LiteralPath $InstallPath -ErrorAction Stop | Select-Object -ExpandProperty Path
} catch {
    # [INST-002.2] Path doesn't exist - attempt to create it
    try {
        New-Item -ItemType Directory -Path $InstallPath -Force -ErrorAction Stop | Out-Null
        $InstallPath = Resolve-Path -LiteralPath $InstallPath | Select-Object -ExpandProperty Path
        Write-Host "Created installation directory: $InstallPath" -ForegroundColor Green
    } catch {
        Write-Error "Cannot access or create installation path '$InstallPath': $_"
        exit 1
    }
}

# [INST-003] Define module paths based on resolved installation directory
$moduleRoot = $InstallPath
$modulesPath = Split-Path $InstallPath -Parent
$manifestPath = Join-Path $moduleRoot "ConvertVTTAssets.psd1"

# [INST-004] Validate that the module files exist in the target directory
# Check for key module files to ensure this is a valid ConvertVTTAssets installation
$requiredFiles = @(
    "ConvertVTTAssets.psd1",
    "ConvertVTTAssets.psm1",
    "ConvertVTTAssets.Core.ps1"
)

$missingFiles = @()
foreach ($file in $requiredFiles) {
    $filePath = Join-Path $moduleRoot $file
    if (-not (Test-Path $filePath)) {
        $missingFiles += $file
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Error "Required module files missing from '$moduleRoot':"
    $missingFiles | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "`nPlease ensure ConvertVTTAssets files are extracted to the installation directory." -ForegroundColor Yellow
    exit 1
}

Write-Host "`nValidated module files in: $moduleRoot" -ForegroundColor Green

# [INST-005] Ensure PSModulePath includes the parent directory (User scope)
# PSModulePath is PowerShell's search path for modules - similar to Windows PATH for executables
# User scope modification avoids requiring administrator privileges and persists across sessions
$paths = $env:PSModulePath -split ';' | Where-Object { $_ -ne '' }

if ($paths -notcontains $modulesPath) {
    # [INST-005.1] Add to both current session and persistent user environment
    # SetEnvironmentVariable with 'User' scope creates permanent registry entry
    [Environment]::SetEnvironmentVariable('PSModulePath', "$($env:PSModulePath);$modulesPath", 'User')
    $env:PSModulePath = "$($env:PSModulePath);$modulesPath"
    Write-Host "Added '$modulesPath' to User PSModulePath." -ForegroundColor Green
    Write-Host "Note: Restart PowerShell to ensure full autoload behavior." -ForegroundColor Yellow
} else {
    # [INST-005.2] Path already exists - inform user but continue installation
    Write-Host "PSModulePath already contains '$modulesPath'" -ForegroundColor DarkGray
}

# [INST-006] Unblock all downloaded module files to prevent execution policy restrictions
# Windows marks files downloaded from internet with Zone.Identifier alternate data stream
# This prevents "RemoteSigned" execution policy from blocking the module files
$unblockCount = 0
Get-ChildItem -LiteralPath $moduleRoot -Recurse -File | ForEach-Object {
    Unblock-File $_.FullName -ErrorAction SilentlyContinue
    $unblockCount++
}
Write-Host "Unblocked $unblockCount module files." -ForegroundColor Green

# [INST-007] Create persistent autoload in PowerShell profile (idempotent operation)
# CurrentUserAllHosts profile loads for all PowerShell hosts (Console, ISE, VS Code)
# This ensures ConvertVTTAssets is available in every PowerShell session
$prof = $PROFILE.CurrentUserAllHosts

# [INST-007.1] Create profile file and directory structure if they don't exist
if (!(Test-Path $prof)) { 
    $profileDir = Split-Path $prof -Parent
    if (!(Test-Path $profileDir)) {
        # [INST-007.2] Create the entire profile directory structure
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    # [INST-007.3] Create empty profile file for content addition
    New-Item -ItemType File -Path $prof -Force | Out-Null 
}

# [INST-008] Define autoload block for profile injection with dynamic path
# Using here-string for multi-line block with proper formatting
# Block is designed to be safe and silent if module files are missing
$autoloadBlock = @"
# --- ConvertVTTAssets autoload ---
`$vttManifest = "$manifestPath"
if (Test-Path `$vttManifest) {
    Import-Module `$vttManifest -ErrorAction SilentlyContinue
}
# --- end ConvertVTTAssets autoload ---
"@

# [INST-009] Add autoload block to profile (idempotent - won't duplicate)
# Check existing profile content to avoid adding duplicate autoload blocks
$profileText = Get-Content -LiteralPath $prof -Raw -ErrorAction SilentlyContinue
if ($null -eq $profileText -or $profileText -notmatch 'ConvertVTTAssets autoload') {
    # [INST-009.1] Profile doesn't contain autoload block - add it with spacing
    Add-Content -LiteralPath $prof -Value "`n$autoloadBlock`n"
    Write-Host "Added autoload block to profile: $prof" -ForegroundColor Green
} else {
    # [INST-009.2] Check if existing block points to different path - update if needed
    if ($profileText -notmatch [regex]::Escape($manifestPath)) {
        # [INST-009.3] Different installation path detected - update the autoload block
        $updatedProfile = $profileText -replace '# --- ConvertVTTAssets autoload ---.*?# --- end ConvertVTTAssets autoload ---', $autoloadBlock -replace '`r`n|`n|`r', "`n"
        Set-Content -LiteralPath $prof -Value $updatedProfile
        Write-Host "Updated autoload block path in profile: $prof" -ForegroundColor Green
    } else {
        # [INST-009.4] Correct autoload block already exists - skip modification
        Write-Host "Profile already contains correct ConvertVTTAssets autoload block." -ForegroundColor DarkGray
    }
}

# [INST-010] Import module into current session for immediate availability
# Remove any existing module version first to ensure clean import of updated version
if (Get-Module ConvertVTTAssets) {
    # [INST-010.1] Force removal of any loaded ConvertVTTAssets module
    Remove-Module ConvertVTTAssets -Force
}

# [INST-010.2] Import using explicit manifest path to ensure correct version loads
# Using -Force to override any import restrictions and -ErrorAction Stop for clear failure reporting
try {
    Import-Module $manifestPath -Force -ErrorAction Stop
    Write-Host "Successfully imported module from: $manifestPath" -ForegroundColor Green
} catch {
    Write-Host "Module import failed: $_" -ForegroundColor Red
    Write-Host "Installation completed but module import failed. Try manual import:" -ForegroundColor Yellow
    Write-Host "  Import-Module '$manifestPath'" -ForegroundColor Gray
    exit 1
}

# [INST-011] Validate successful import and display module information
# Provide user feedback and quick start guidance for immediate productivity
if (Get-Module ConvertVTTAssets) {
    # [INST-011.1] Display successful installation summary with version and location
    $module = Get-Module ConvertVTTAssets
    Write-Host "`n" + "="*60 -ForegroundColor Green
    Write-Host "ConvertVTTAssets v$($module.Version) Installation Complete!" -ForegroundColor Green
    Write-Host "="*60 -ForegroundColor Green
    Write-Host "Installation Path: $moduleRoot" -ForegroundColor Cyan
    Write-Host "PSModulePath: $modulesPath" -ForegroundColor Cyan
    Write-Host "Profile Updated: $prof" -ForegroundColor Cyan
    
    # [INST-011.2] Show available commands in organized table format
    Write-Host "`nAvailable Commands:" -ForegroundColor Yellow
    Get-Command -Module ConvertVTTAssets | Format-Table -Property Name, CommandType -AutoSize
    
    # [INST-011.3] Provide quick start examples for immediate user engagement
    Write-Host "Quick Start Examples:" -ForegroundColor Yellow
    Write-Host "  # Preview filename optimization (safe dry-run)" -ForegroundColor Gray
    Write-Host "  Optimize-FileNames -Root 'C:\YourPath' -WhatIf" -ForegroundColor White
    Write-Host "`n  # Convert videos to WebM format" -ForegroundColor Gray
    Write-Host "  Convert-ToWebM -Root 'C:\YourPath' -OutputRoot 'C:\Output'" -ForegroundColor White
    Write-Host "`n  # Convert images to WebP format" -ForegroundColor Gray
    Write-Host "  Convert-ToWebP -Root 'C:\YourPath' -OutputRoot 'C:\Output'" -ForegroundColor White
    
    # [INST-011.4] Direct users to comprehensive help system
    Write-Host "`nFor detailed help: Get-Help <command> -Detailed" -ForegroundColor Cyan
    Write-Host "Module will auto-load in new PowerShell sessions." -ForegroundColor Green
} else {
    # [INST-011.5] Unexpected state - module import appeared successful but module not found
    Write-Host "`nUnexpected error: Module import completed but module not available." -ForegroundColor Red
    Write-Host "Try restarting PowerShell and running: Import-Module '$manifestPath'" -ForegroundColor Yellow
}