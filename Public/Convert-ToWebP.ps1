<#
.SYNOPSIS
    Convert-ToWebP - Convert static images to WebP format for Foundry VTT optimization
.DESCRIPTION
    Converts static images (PNG, JPG/JPEG, TIFF, BMP) to WebP format with configurable quality settings.
    Features parallel processing, intelligent scaling, lossless/lossy compression options, and significant 
    file size reduction while maintaining visual quality for optimal Foundry VTT performance.
.PARAMETER Root
    Source directory containing images to convert (default: current directory)
.PARAMETER Quality
    Compression quality for lossy WebP (1-100, default: 80, higher = better quality)
.PARAMETER MaxWidth
    Maximum width in pixels, maintains aspect ratio (64-8192, default: 4096)
.PARAMETER IncludeExt
    Array of additional extensions to include (e.g., @('.tga', '.dds'))
.PARAMETER ExcludeExt
    Array of extensions to skip processing
.PARAMETER ThrottleLimit
    Maximum concurrent conversions (1-64, default: 4)
.PARAMETER FfmpegPath
    Path to FFmpeg executable (default: 'ffmpeg')
.PARAMETER FfprobePath
    Path to FFprobe executable (default: 'ffprobe')
.PARAMETER OutputRoot
    Destination directory for converted files (preserves directory structure)
.PARAMETER LogPath
    Path for operation log file (.csv or .json format)
.PARAMETER NoRecurse
    Only process files in root directory, skip subdirectories
.PARAMETER Lossless
    Enable lossless WebP compression (ignores Quality setting)
.PARAMETER Parallel
    Enable parallel processing using ThreadJob engine (PowerShell 7+ only)
.PARAMETER Force
    Re-convert files even if destination already exists and is newer
.PARAMETER DeleteSource
    Send original files to Recycle Bin after successful conversion
.PARAMETER Silent
    Suppress progress output and display minimal information
.PARAMETER WhatIf
    Preview what would be converted without making any changes
.EXAMPLE
    Convert-ToWebP
    Convert all static images in current directory to WebP with default quality
.EXAMPLE
    Convert-ToWebP -Root "D:\Portraits" -OutputRoot "D:\Optimized" -Quality 90 -Parallel
    Convert portraits with high quality using parallel processing
.EXAMPLE
    Convert-ToWebP -Root "D:\Tokens" -Lossless -MaxWidth 512
    Convert tokens with lossless compression, scaled to 512px maximum width
.EXAMPLE
    Convert-ToWebP -Root "D:\Maps" -Quality 75 -DeleteSource -LogPath "D:\Logs\webp_conversion.csv"
    Convert maps, delete originals, and log all operations to CSV file
.NOTES
    Author: Andres Yuhnke, Claude (Anthropic)
    Version: 1.6.0
    
    Requirements:
    - FFmpeg and FFprobe in PATH or specified via -FfmpegPath/-FfprobePath
    - PowerShell 7+ recommended for parallel processing
    - Sufficient disk space (output typically 25-40% of input size)
    
    Supported input formats: .png, .jpg, .jpeg, .tif, .tiff, .bmp
    Performance: 3-4x faster with parallel processing enabled
    Quality recommendations: 85-95 for portraits, 75-85 for maps, 90+ for UI elements
.LINK
    https://github.com/andresyuhnke/ConvertVTTAssets
.LINK
    https://www.powershellgallery.com/packages/ConvertVTTAssets
#>

function Convert-ToWebP {
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Root = ".",
    [switch]$NoRecurse,
    [ValidateRange(1,100)][int]$Quality = 80,
    [switch]$Lossless,
    [ValidateRange(64,8192)][int]$MaxWidth = 4096,
    [string[]]$IncludeExt,
    [string[]]$ExcludeExt,
    [switch]$Parallel,
    [ValidateRange(1,64)][int]$ThrottleLimit = 4,
    [string]$FfmpegPath = 'ffmpeg',
    [string]$FfprobePath = 'ffprobe',
    [switch]$Force,
    [switch]$DeleteSource,
    [string]$OutputRoot,
    [string]$LogPath,
    [switch]$Silent
)

# [WEBP-001] Validate required external tools before processing
Test-Tool -Name $FfmpegPath
Test-Tool -Name $FfprobePath

# [WEBP-002] Configure file discovery parameters for static image formats
$recurse = -not $NoRecurse.IsPresent
$extensions = @('.png','.jpg','.jpeg','.tif','.tiff','.bmp')

# [WEBP-003] Apply extension filtering if specified by user
if ($IncludeExt) {
    $extensions += ($IncludeExt | ForEach-Object { $_.ToLower() })
    $extensions = $extensions | Select-Object -Unique
}
if ($ExcludeExt) {
    $excludeSet = [System.Collections.Generic.HashSet[string]]::new([string[]]($ExcludeExt | ForEach-Object { $_.ToLower() }))
    $extensions = $extensions | Where-Object { -not $excludeSet.Contains($_) }
}

# [WEBP-004] Discover candidate static image files for conversion
$files = Get-ChildItem -LiteralPath $Root -File -Recurse:$recurse |
    Where-Object { $extensions -contains ([System.IO.Path]::GetExtension($_.Name).ToLower()) } |
    Sort-Object FullName

if (-not $files) { Write-Verbose "No candidate static images under '$Root'."; return }

# [WEBP-005] Initialize progress tracking and user feedback
$totalFiles = @($files).Count
$fileNum = 0
if (-not $Silent -and $totalFiles -gt 0) {
    Write-Host ""
    Write-Host "=== Convert-ToWebP Starting ===" -ForegroundColor Cyan
    Write-Host "Found $totalFiles file(s) to process" -ForegroundColor Yellow
    Write-Host ""
}

# [WEBP-006] Choose processing engine based on PowerShell version and user preference
$records = @()
if ($Parallel) {
    if (-not $script:IsPS7) {
        Write-Warning "-Parallel requested but you're on Windows PowerShell 5.1. Falling back to sequential. For real parallelism, run in PowerShell 7+ (pwsh)."
    } else {
        # [WEBP-007] Configure parallel processing settings for WebP conversion
        $settings = @{
            Root=$Root; OutputRoot=$OutputRoot; Force=$Force;
            FfmpegPath=$FfmpegPath; FfprobePath=$FfprobePath;
            Quality=$Quality; Lossless=$Lossless; MaxWidth=$MaxWidth;
            ThrottleLimit=$ThrottleLimit;
            WhatIfPreference=$WhatIfPreference; VerbosePreference=$VerbosePreference;
            Silent=$Silent
        }
        # [WEBP-008] Execute parallel conversion using ThreadJob engine
        $records = Invoke-WebPParallel -Files $files -S $settings
    }
}

# [WEBP-009] Sequential processing fallback and PowerShell 5.1 support
if ($records.Count -eq 0) {
    # Sequential engine
    foreach ($f in $files) {
        # [WEBP-010] Display conversion progress to user
        if (-not $Silent) {
            $fileNum++
            $percentComplete = [math]::Round(($fileNum / $totalFiles) * 100, 0)
            $fileName = Split-Path $f.Name -Leaf
            Write-Host ("[{0,3}%] Processing {1}/{2}: {3}" -f $percentComplete, $fileNum, $totalFiles, $fileName) -ForegroundColor Cyan
        }
        
        # [WEBP-011] Initialize conversion result tracking
        $VerbosePreference = $VerbosePreference
        $ErrorActionPreference = 'Stop'
        $result = [ordered]@{
            Time        = (Get-Date).ToString('s')
            Command     = 'Convert-ToWebP'
            Source      = $f.FullName
            Destination = $null
            Status      = 'Skipped'
            Reason      = ''
            DurationSec = 0.0
            SrcBytes    = $f.Length
            DstBytes    = 0
            SizeDeltaBytes = $null
            SizeDeltaPct   = $null
            Quality     = $Quality
            Lossless    = [bool]$Lossless
            WidthCap    = $MaxWidth
        }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        
        try {
            # [WEBP-012] Calculate destination path using OutputRoot if specified
            $dest = Get-DestinationPath -SourceFile $f -Root $Root -OutputRoot $OutputRoot -NewExtension '.webp'
            $result.Destination = $dest

            # [WEBP-013] Check if conversion can be skipped (up-to-date destination exists)
            if (-not $Force -and (Test-Path $dest)) {
                $dstInfo = Get-Item $dest
                if ($dstInfo.LastWriteTimeUtc -ge $f.LastWriteTimeUtc) {
                    $result.Status = 'Skipped'; $result.Reason='UpToDate'
                    if (-not $Silent) {
                        Write-Host "       ⚠ Skipped: Already up-to-date" -ForegroundColor Yellow
                    }
                    $records += [pscustomobject]$result
                    continue
                }
            }

            # [WEBP-014] Extract image metadata using FFprobe
            $info = Invoke-FFProbeJson -Path $f.FullName -FfprobePath $FfprobePath
            $srcW = Get-Width -Info $info

            # [WEBP-015] Generate scaling filter if image exceeds maximum width
            $vf = $null
            if ($srcW -and $srcW -gt $MaxWidth) { 
                $vf = "scale=min(iw\,${MaxWidth}):-2:flags=lanczos" 
            }

            # [WEBP-016] Build FFmpeg command line arguments for WebP conversion
            $args = @('-y','-hide_banner','-loglevel','error','-i', $f.FullName)
            if ($vf) { $args += @('-vf', $vf) }

            $args += @('-c:v','libwebp')
            
            # [WEBP-017] Configure compression settings based on lossless/lossy mode
            if ($Lossless) { 
                $args += @('-lossless','1','-compression_level','6') 
            } else { 
                $args += @('-q:v', $Quality) 
            }

            $args += @('-frames:v','1', $dest)

            # [WEBP-018] Handle WhatIf preview mode
            if ($WhatIfPreference) {
                Write-Host "WhatIf: would convert '$($f.FullName)' → '$dest'"
                $result.Status = 'WhatIf'
                $records += [pscustomobject]$result
                continue
            }

            # [WEBP-019] Execute FFmpeg conversion and evaluate success
            & $FfmpegPath @args
            $ok = ($LASTEXITCODE -eq 0)
            if ($ok) {
                $result.Status = 'Converted'
                $dst = Get-Item $dest -ErrorAction SilentlyContinue
                if ($dst) {
                    # [WEBP-020] Calculate size reduction metrics
                    $result.DstBytes = $dst.Length
                    if ($result.SrcBytes -gt 0) {
                        $result.SizeDeltaBytes = [long]($result.DstBytes - $result.SrcBytes)
                        $result.SizeDeltaPct   = [math]::Round((($result.DstBytes / [double]$result.SrcBytes) - 1.0) * 100.0, 2)
                    }
                }
                if (-not $Silent) {
                    $reduction = if ($result.SizeDeltaPct) { "{0:N1}%" -f $result.SizeDeltaPct } else { "N/A" }
                    Write-Host "       ✓ Converted: $(Split-Path $dest -Leaf) (Size reduction: $reduction)" -ForegroundColor Green
                }
            } else {
                $result.Status = 'Failed'; $result.Reason = "ffmpeg exit $LASTEXITCODE"
                if (-not $Silent) {
                    Write-Host "       ✗ Failed: $($result.Reason)" -ForegroundColor Red
                }
            }
            $records += [pscustomobject]$result
        } catch {
            $result.Status = 'Failed'; $result.Reason = $_.Exception.Message
            if (-not $Silent) {
                Write-Host "       ✗ Failed: $($result.Reason)" -ForegroundColor Red
            }
            $records += [pscustomobject]$result
        } finally {
            $sw.Stop(); $result.DurationSec = [math]::Round($sw.Elapsed.TotalSeconds,2)
        }
    }
}

# [WEBP-021] Generate comprehensive operation summary
$conv = $records | Where-Object {$_.Status -eq 'Converted'}
$srcTotal = ($conv | Measure-Object -Property SrcBytes -Sum).Sum
$dstTotal = ($conv | Measure-Object -Property DstBytes -Sum).Sum
$delta    = $dstTotal - $srcTotal
$pct      = $null
if ($srcTotal -gt 0) { $pct = [math]::Round((($dstTotal / [double]$srcTotal) - 1.0) * 100.0, 2) }

# [WEBP-021.1] Calculate summary statistics for display
$converted = $conv.Count
$skipped   = ($records | Where-Object {$_.Status -eq 'Skipped'}).Count
$failed    = ($records | Where-Object {$_.Status -eq 'Failed'}).Count
$whatif    = ($records | Where-Object {$_.Status -eq 'WhatIf'}).Count

# [WEBP-021.2] Write operation log if path specified
if ($LogPath) { Write-LogRecords -Records $records -LogPath $LogPath }

# [WEBP-021.3] Display final summary to user
if (-not $Silent) { Write-Host "" }
Write-Host "=== Convert-ToWebP Summary ==="
Write-Host ("Converted: {0}" -f $converted)
Write-Host ("Skipped:   {0}" -f $skipped)
if ($whatif -gt 0) { Write-Host ("WhatIf:    {0}" -f $whatif) }
Write-Host ("Failed:    {0}" -f $failed)
if ($converted -gt 0) {
    Write-Host ("Size Total → Src: {0}  Dst: {1}  Δ: {2} ({3}%)" -f (Format-Bytes $srcTotal),(Format-Bytes $dstTotal),(Format-Bytes $delta),$pct)
}

# [WEBP-022] Handle source file cleanup if requested
if ($DeleteSource.IsPresent -and -not $WhatIfPreference) {
    foreach ($rec in $conv) {
        if (Test-Path $rec.Destination) {
            $dstInfo = Get-Item $rec.Destination
            if ($dstInfo.Length -gt 0 -and (Test-Path $rec.Source)) {
                $null = Move-ToRecycleBin -Path $rec.Source -WhatIf:$WhatIfPreference
            }
        }
    }
}

}