<#
.SYNOPSIS
    ConvertVTTAssets SharedHelpers - Core utility functions for asset optimization operations
.DESCRIPTION
    Private module containing shared utility functions used across all ConvertVTTAssets operations.
    Includes tool validation, FFmpeg integration, file system operations, logging, and format helpers.
    These functions are internal to the module and not directly exposed to users.
.AUTHOR
    Andres Yuhnke, Claude (Anthropic)
.VERSION
    1.6.0
.DATE
    2025-08-24
.COPYRIGHT
    (c) 2025 Andres Yuhnke. MIT License.
.NOTES
    Private functions included:
    - Test-Tool: External tool validation (FFmpeg/FFprobe)
    - Invoke-FFProbeJson: Media metadata extraction
    - Get-HasAlpha, Get-FrameRate, Get-Width, Get-Height: Media property extraction
    - Get-FilterGraph: FFmpeg filter chain generation
    - Get-DestinationPath: Output path calculation with OutputRoot support
    - Move-ToRecycleBin: Safe file deletion using Windows Recycle Bin
    - Write-LogRecords: Flexible logging (CSV/JSON auto-detection)
    - Format-Bytes: Human-readable file size formatting
#>

# [HELP-001] External tool validation - Ensures required tools are available and executable
function Test-Tool {
    param([Parameter(Mandatory=$true)][string]$Name)
    
    # [HELP-001.1] Temporarily suppress error output to avoid cluttering console
    $ErrorActionPreferenceBackup = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    
    # [HELP-001.2] Test tool availability by calling with version parameter
    # Most tools support -version and return 0 exit code when working
    $null = & $Name -version 2>$null
    
    # [HELP-001.3] Restore original error preference after test
    $ErrorActionPreference = $ErrorActionPreferenceBackup
    
    # [HELP-001.4] Evaluate exit code to determine if tool is functional
    # Non-zero exit codes (except null) indicate tool not found or not executable
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
        throw "Required tool '$Name' not found or not executable. Add it to PATH or pass a full path."
    }
}

# [HELP-002] FFmpeg probe integration - Extracts comprehensive media metadata as JSON
function Invoke-FFProbeJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$FfprobePath
    )
    
    # [HELP-002.1] Configure ffprobe for structured JSON output with video stream focus
    # -v error: Minimal logging, -print_format json: Machine-readable output
    # -select_streams v:0: First video stream only, -show_streams/-show_format: Complete metadata
    $args = @('-v','error','-print_format','json','-select_streams','v:0','-show_streams','-show_format',$Path)
    
    # [HELP-002.2] Execute ffprobe and capture JSON output, suppress stderr to avoid noise
    $json = & $FfprobePath @args 2>$null
    if (-not $json) { return $null }
    
    # [HELP-002.3] Parse JSON response with error handling for malformed output
    try { return $json | ConvertFrom-Json } catch { return $null }
}

# [HELP-003] Alpha channel detection - Determines if media contains transparency information
function Get-HasAlpha {
    param($Info)
    if (-not $Info) { return $false }
    
    # [HELP-003.1] Extract pixel format from first video stream metadata
    $fmt = $Info.streams[0].pix_fmt
    if (-not $fmt) { return $false }
    
    # [HELP-003.2] Check for alpha channel indicators in pixel format string
    # Simple 'a' check covers most cases, specific formats cover edge cases
    return ($fmt -match 'a') -or ($fmt -match 'rgba|bgra|argb|abgr|ya8|yuva420p|yuva422p|yuva444p')
}

# [HELP-004] Frame rate extraction - Gets video frame rate with fallback logic
function Get-FrameRate {
    param($Info)
    if (-not $Info) { return $null }
    
    # [HELP-004.1] Try average frame rate first (more accurate for variable rate content)
    $r = $Info.streams[0].avg_frame_rate
    
    # [HELP-004.2] Fall back to declared frame rate if average is unavailable
    if ([string]::IsNullOrWhiteSpace($r) -or $r -eq '0/0') {
        $r = $Info.streams[0].r_frame_rate
    }
    
    # [HELP-004.3] Handle invalid or missing frame rate data
    if (-not $r -or $r -eq '0/0') { return $null }
    
    # [HELP-004.4] Parse fractional frame rates (e.g., "30000/1001" for 29.97 fps)
    if ($r -match '^\d+/\d+$') {
        $num,$den = $r -split '/'
        if ([int]$den -ne 0) { return [double]$num / [double]$den }
        else { return $null }
    }
    
    # [HELP-004.5] Handle decimal frame rates with validation
    [double]::TryParse($r, [ref]([double]$fr = 0)) | Out-Null
    if ($fr -gt 0) { return $fr } else { return $null }
}

# [HELP-005] Media dimension extraction functions - Get width and height from metadata
function Get-Width { param($Info) if (-not $Info) { return $null } return $Info.streams[0].width }
function Get-Height{ param($Info) if (-not $Info) { return $null } return $Info.streams[0].height }

# [HELP-006] FFmpeg filter graph generation - Creates video processing filter chains
function Get-FilterGraph {
    param(
        [int]$SrcWidth,
        [double]$SrcFps,
        [int]$MaxWidth,
        [int]$MaxFPS,
        [string]$AlphaMode = 'auto',
        [switch]$FlattenBlack
    )
    
    $filters = @()
    
    # [HELP-006.1] Add scaling filter if source exceeds maximum width
    # Uses Lanczos algorithm for high-quality downscaling, maintains aspect ratio
    if ($SrcWidth -and $SrcWidth -gt $MaxWidth) {
        $filters += "scale=min(iw\,${MaxWidth}):-2:flags=lanczos"
    }
    
    # [HELP-006.2] Add frame rate limiting filter for high FPS content
    if ($SrcFps -and ($SrcFps -gt $MaxFPS)) {
        $filters += "fps=${MaxFPS}"
    }
    
    # [HELP-006.3] Add alpha channel flattening for transparency removal
    if ($AlphaMode -eq 'disable' -and $FlattenBlack) {
        $filters += "format=yuv420p"
    }
    
    # [HELP-006.4] Combine filters into single filter graph string
    if ($filters.Count -gt 0) { return ($filters -join ',') }
    return $null
}

# [HELP-007] Destination path calculation - Handles OutputRoot mapping and directory creation
function Get-DestinationPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$false)][string]$OutputRoot,
        [Parameter(Mandatory=$true)][string]$NewExtension
    )

    # [HELP-007.1] Simple case: No OutputRoot means in-place operation (same directory as source)
    if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        $destDir = $SourceFile.DirectoryName
    } else {
        # [HELP-007.2] Complex case: OutputRoot requires relative path calculation
        # Get absolute paths for reliable URI manipulation
        $rootFull = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\')
        $srcDirFull = (Resolve-Path -LiteralPath $SourceFile.DirectoryName).Path.TrimEnd('\')

        # [HELP-007.3] Calculate relative path from Root to source file's directory
        # Using URI objects ensures proper handling of spaces and special characters
        $rootUri = New-Object System.Uri(($rootFull + '\'))
        $dirUri  = New-Object System.Uri(($srcDirFull + '\'))
        $relUri  = $rootUri.MakeRelativeUri($dirUri).ToString()
        $relPath = [System.Uri]::UnescapeDataString($relUri) -replace '/', '\'

        # [HELP-007.4] Build destination directory path in OutputRoot
        if ([string]::IsNullOrWhiteSpace($relPath)) { $destDir = $OutputRoot }
        else { $destDir = Join-Path $OutputRoot $relPath }

        # [HELP-007.5] Create destination directory if it doesn't exist
        # Uses WhatIf support for preview operations
        if (-not (Test-Path -LiteralPath $destDir)) {
            if ($PSCmdlet.ShouldProcess($destDir, "Create destination directory")) {
                New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            } else {
                Write-Host "WhatIf: would create directory '$destDir'"
            }
        }
    }

    # [HELP-007.6] Build final destination file path with new extension
    $destName = [System.IO.Path]::GetFileNameWithoutExtension($SourceFile.Name) + $NewExtension
    return (Join-Path $destDir $destName)
}

# [HELP-008] Recycle Bin integration - Safe file deletion using Windows shell integration
function Move-ToRecycleBin {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory=$true)][string]$Path)

    # [HELP-008.1] Load Visual Basic assembly for Recycle Bin operations
    # This provides access to the Windows shell recycling functionality
    try { Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue } catch {
        Write-Verbose "Add-Type already loaded or not available: $_"
    }

    # [HELP-008.2] Perform safe deletion using Windows Recycle Bin
    # Supports WhatIf for preview operations
    if ($PSCmdlet.ShouldProcess($Path, "Send to Recycle Bin")) {
        try {
            # [HELP-008.3] Use VB.NET FileSystem for reliable recycling
            # OnlyErrorDialogs: Minimal UI, SendToRecycleBin: Don't permanently delete
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $Path,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            )
            Write-Verbose "Sent to Recycle Bin: $Path"
            return $true
        } catch {
            Write-Warning "Failed to recycle '$Path': $($_.Exception.Message)"
            return $false
        }
    } else {
        Write-Host "WhatIf: would send to Recycle Bin '$Path'"
        return $true
    }
}

# [HELP-009] Flexible logging system - Auto-detects format based on file extension
function Write-LogRecords {
    param(
        [Parameter(Mandatory=$true)][System.Collections.IEnumerable]$Records,
        [Parameter(Mandatory=$true)][string]$LogPath
    )
    
    # [HELP-009.1] Ensure log directory exists before writing
    $dir = [System.IO.Path]::GetDirectoryName($LogPath)
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    # [HELP-009.2] Auto-detect output format based on file extension
    $ext = [System.IO.Path]::GetExtension($LogPath).ToLower()
    switch ($ext) {
        '.csv'  { $Records | Export-Csv -NoTypeInformation -Path $LogPath -Encoding UTF8 }
        '.json' { $Records | ConvertTo-Json -Depth 5 | Set-Content -Path $LogPath -Encoding UTF8 }
        default { $Records | Export-Csv -NoTypeInformation -Path $LogPath -Encoding UTF8 }  # Default to CSV
    }
}

# [HELP-010] Human-readable file size formatting - Converts bytes to appropriate units
function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -eq $null) { return '' }
    
    # [HELP-010.1] Define size units and initialize conversion variables
    $sizes = 'B','KB','MB','GB','TB'
    $i = 0; $val = [double]$Bytes
    
    # [HELP-010.2] Convert to appropriate unit (divide by 1024 until value < 1024)
    while ($val -ge 1024 -and $i -lt $sizes.Length-1) { $val /= 1024; $i++ }
    
    # [HELP-010.3] Format with 2 decimal places and appropriate unit suffix
    return ('{0:N2} {1}' -f $val, $sizes[$i])
}