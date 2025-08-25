<#
.SYNOPSIS
    Convert-ToWebM - Convert animated content to WebM format for Foundry VTT optimization
.DESCRIPTION
    Converts animated images and videos (GIF, animated WebP, MP4, MOV, MKV, APNG) to WebM format 
    using VP9 or AV1 codecs. Features parallel processing, alpha channel preservation, frame rate 
    limiting, and intelligent scaling for optimal Foundry VTT compatibility and file size reduction.
.PARAMETER Root
    Source directory containing files to convert (default: current directory)
.PARAMETER MaxFPS
    Maximum frame rate for output videos (1-240, default: 30)
.PARAMETER MaxWidth
    Maximum width in pixels, maintains aspect ratio (64-8192, default: 1920)
.PARAMETER Codec
    Video codec: 'vp9' (default) or 'av1' for next-generation compression
.PARAMETER MaxBitrateKbps
    Optional bitrate ceiling in kbps (default: 0 - no limit)
.PARAMETER AlphaMode
    Alpha channel handling: 'auto' (default), 'force', or 'disable'
.PARAMETER AlphaBackground
    Background color when disabling alpha (hex color, e.g., '#000000')
.PARAMETER IncludeExt
    Array of additional extensions to include (e.g., @('.avi', '.wmv'))
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
    Convert-ToWebM
    Convert all animated content in current directory to WebM
.EXAMPLE
    Convert-ToWebM -Root "D:\FoundryAssets" -OutputRoot "D:\Optimized" -MaxFPS 24 -Parallel
    Convert all animated content with 24fps limit using parallel processing
.EXAMPLE
    Convert-ToWebM -Root "D:\Maps" -Codec av1 -MaxWidth 1280 -AlphaMode disable -AlphaBackground '#000000'
    Convert with AV1 codec, scaled to 1280px width, alpha flattened to black background
.EXAMPLE
    Convert-ToWebM -Root "D:\Animations" -Parallel -ThrottleLimit 8 -DeleteSource -LogPath "D:\Logs\conversion.json"
    High-performance conversion with source cleanup and detailed logging
.NOTES
    Author: Andres Yuhnke, Claude (Anthropic)
    Version: 1.6.0
    
    Requirements:
    - FFmpeg and FFprobe in PATH or specified via -FfmpegPath/-FfprobePath
    - PowerShell 7+ recommended for parallel processing
    - Sufficient disk space (output typically 35% of input size)
    
    Supported input formats: .gif, .webp, .mp4, .m4v, .mov, .mkv, .apng
    Performance: 3-4x faster with parallel processing enabled
.LINK
    https://github.com/andresyuhnke/ConvertVTTAssets
.LINK
    https://www.powershellgallery.com/packages/ConvertVTTAssets
#>

function Convert-ToWebM {
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Root = ".",
    [switch]$NoRecurse,
    [ValidateRange(1,240)][int]$MaxFPS = 30,
    [ValidateRange(64,8192)][int]$MaxWidth = 1920,
    [ValidateSet('vp9','av1')][string]$Codec = 'vp9',
    [int]$MaxBitrateKbps = 0,
    [ValidateSet('auto','force','disable')][string]$AlphaMode = 'auto',
    [string]$AlphaBackground,
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

# [WEBM-001] Validate required external tools before processing
Test-Tool -Name $FfmpegPath
Test-Tool -Name $FfprobePath

# [WEBM-002] Configure file discovery parameters
$recurse = -not $NoRecurse.IsPresent
$extensions = @('.gif','.webp','.mp4','.m4v','.mov','.mkv','.apng')

# [WEBM-003] Apply extension filtering if specified
if ($IncludeExt) {
    $extensions += ($IncludeExt | ForEach-Object { $_.ToLower() })
    $extensions = $extensions | Select-Object -Unique
}
if ($ExcludeExt) {
    $excludeSet = [System.Collections.Generic.HashSet[string]]::new([string[]]($ExcludeExt | ForEach-Object { $_.ToLower() }))
    $extensions = $extensions | Where-Object { -not $excludeSet.Contains($_) }
}

# [WEBM-004] Discover candidate files for conversion
$files = Get-ChildItem -LiteralPath $Root -File -Recurse:$recurse |
    Where-Object { $extensions -contains ([System.IO.Path]::GetExtension($_.Name).ToLower()) } |
    Sort-Object FullName

if (-not $files) { Write-Verbose "No candidate files under '$Root'."; return }

# [WEBM-005] Initialize progress tracking and user feedback
$totalFiles = @($files).Count
$fileNum = 0
if (-not $Silent -and $totalFiles -gt 0) {
    Write-Host ""
    Write-Host "=== Convert-ToWebM Starting ===" -ForegroundColor Cyan
    Write-Host "Found $totalFiles file(s) to process" -ForegroundColor Yellow
    Write-Host ""
}

# [WEBM-006] Choose processing engine based on PowerShell version and user preference
$records = @()
if ($Parallel) {
    if (-not $script:IsPS7) {
        Write-Warning "-Parallel requested but you're on Windows PowerShell 5.1. Falling back to sequential. For real parallelism, run in PowerShell 7+ (pwsh)."
    } else {
        # [WEBM-007] Configure parallel processing settings
        $settings = @{
            Root = $Root; OutputRoot=$OutputRoot; Force=$Force;
            FfmpegPath=$FfmpegPath; FfprobePath=$FfprobePath;
            MaxFPS=$MaxFPS; MaxWidth=$MaxWidth; Codec=$Codec;
            MaxBitrateKbps=$MaxBitrateKbps; AlphaMode=$AlphaMode;
            AlphaBackground=$AlphaBackground; ThrottleLimit=$ThrottleLimit;
            WhatIfPreference=$WhatIfPreference; VerbosePreference=$VerbosePreference;
            Silent=$Silent
        }
        # [WEBM-008] Execute parallel conversion using ThreadJob engine
        $records = Invoke-WebMParallel -Files $files -S $settings
    }
} 

# [WEBM-009] Sequential processing fallback and PowerShell 5.1 support
if ($records.Count -eq 0) {
    # Sequential engine
    foreach ($f in $files) {
        # [WEBM-010] Display conversion progress to user
        if (-not $Silent) {
            $fileNum++
            $percentComplete = [math]::Round(($fileNum / $totalFiles) * 100, 0)
            $fileName = Split-Path $f.Name -Leaf
            Write-Host ("[{0,3}%] Processing {1}/{2}: {3}" -f $percentComplete, $fileNum, $totalFiles, $fileName) -ForegroundColor Cyan
        }
        
        # [WEBM-011] Initialize conversion result tracking
        $VerbosePreference = $VerbosePreference
        $ErrorActionPreference = 'Stop'
        $result = [ordered]@{
            Time        = (Get-Date).ToString('s')
            Command     = 'Convert-ToWebM'
            Source      = $f.FullName
            Destination = $null
            Status      = 'Skipped'
            Reason      = ''
            DurationSec = 0.0
            SrcBytes    = $f.Length
            DstBytes    = 0
            SizeDeltaBytes = $null
            SizeDeltaPct   = $null
            Codec       = $Codec
            HasAlpha    = $false
            AlphaMode   = $AlphaMode
            FPSCap      = $MaxFPS
            WidthCap    = $MaxWidth
        }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        
        try {
            # [WEBM-012] Calculate destination path using OutputRoot if specified
            $dest = Get-DestinationPath -SourceFile $f -Root $Root -OutputRoot $OutputRoot -NewExtension '.webm'
            $result.Destination = $dest

            # [WEBM-013] Check if conversion can be skipped (up-to-date destination exists)
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

            # [WEBM-014] Extract media metadata using FFprobe
            $info = Invoke-FFProbeJson -Path $f.FullName -FfprobePath $FfprobePath
            $hasAlpha = $false
            
            # [WEBM-015] Determine alpha channel presence and handling
            if ($info) { $hasAlpha = Get-HasAlpha -Info $info }
            elseif ($f.Extension.ToLower() -in @('.gif','.apng','.webp')) { $hasAlpha = $true }
            
            switch ($AlphaMode) {
                'force'   { $hasAlpha = $true }
                'disable' { $hasAlpha = $false }
            }
            $result.HasAlpha = $hasAlpha

            # [WEBM-016] Extract source video properties for processing decisions
            $srcW = Get-Width  -Info $info
            $srcH = Get-Height -Info $info
            $srcFps = Get-FrameRate -Info $info

            # [WEBM-017] Generate FFmpeg filter graph for scaling and frame rate limiting
            $vf = $null
            $useFlatten = ($AlphaMode -eq 'disable' -and -not $AlphaBackground)
            $vf = Get-FilterGraph -SrcWidth $srcW -SrcFps $srcFps -MaxWidth $MaxWidth -MaxFPS $MaxFPS -AlphaMode $AlphaMode -FlattenBlack:$useFlatten

            # [WEBM-018] Configure codec-specific encoding parameters
            $codecArgs = @()
            switch ($Codec) {
                'vp9' {
                    $codecArgs = @('-c:v','libvpx-vp9','-crf','28','-b:v','0','-row-mt','1','-threads','0','-speed','2','-deadline','good')
                    if ($hasAlpha) { $codecArgs += @('-pix_fmt','yuva420p','-auto-alt-ref','0') } else { $codecArgs += @('-pix_fmt','yuv420p') }
                }
                'av1' {
                    $codecArgs = @('-c:v','libaom-av1','-crf','30','-b:v','0','-threads','0','-cpu-used','4')
                    if ($hasAlpha) { $codecArgs += @('-pix_fmt','yuva420p') } else { $codecArgs += @('-pix_fmt','yuv420p') }
                }
            }
            
            # [WEBM-019] Apply bitrate limiting if specified
            if ($MaxBitrateKbps -gt 0) {
                $codecArgs += @('-maxrate', ("{0}k" -f $MaxBitrateKbps), '-bufsize', ("{0}k" -f ($MaxBitrateKbps*2)))
            }

            # [WEBM-020] Build FFmpeg command line arguments
            $args = @('-y','-hide_banner','-loglevel','error','-i', $f.FullName)

            # [WEBM-021] Handle special case: alpha background color replacement
            $filtersApplied = $false
            if ($AlphaMode -eq 'disable' -and $AlphaBackground) {
                $w = $srcW; $h = $srcH
                if ($w -and $h -and $w -gt 0 -and $h -gt 0) {
                    $bg = ($AlphaBackground).Trim('#')
                    $fc = @()
                    if ($MaxFPS -gt 0) { $fc += ("fps={0}" -f $MaxFPS) }
                    if ($MaxWidth -gt 0 -and $w -gt $MaxWidth) { $fc += ("scale=min(iw\,{0}):-2:flags=lanczos" -f $MaxWidth) }
                    if ($fc.Count -eq 0) { $fc = @('format=rgba') } else { $fc.Insert(0,'format=rgba') }
                    $filterComplex = "color=c=#${bg}:s=${w}x${h}[bg];[0:v]" + ($fc -join ',') + "[v];[bg][v]overlay=format=auto,format=yuv420p"
                    $args += @('-filter_complex', $filterComplex)
                    $filtersApplied = $true
                }
            }

            # [WEBM-022] Apply standard video filters if no complex filtering was used
            if (-not $filtersApplied) {
                if ($vf) { $args += @('-filter:v', $vf) }
            }

            $args += $codecArgs
            $args += @('-an','-f','webm', $dest)

            # [WEBM-023] Handle WhatIf preview mode
            if ($WhatIfPreference) {
                Write-Host "WhatIf: would convert '$($f.FullName)' → '$dest'"
                $result.Status = 'WhatIf'
                $records += [pscustomobject]$result
                continue
            }

            # [WEBM-024] Execute FFmpeg conversion and evaluate success
            & $FfmpegPath @args
            $ok = ($LASTEXITCODE -eq 0)
            if ($ok) {
                $result.Status = 'Converted'
                $dst = Get-Item $dest -ErrorAction SilentlyContinue
                if ($dst) {
                    # [WEBM-025] Calculate size reduction metrics
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

# [WEBM-025] Generate comprehensive operation summary
$conv = $records | Where-Object {$_.Status -eq 'Converted'}
$srcTotal = ($conv | Measure-Object -Property SrcBytes -Sum).Sum
$dstTotal = ($conv | Measure-Object -Property DstBytes -Sum).Sum
$delta    = $dstTotal - $srcTotal
$pct      = $null
if ($srcTotal -gt 0) { $pct = [math]::Round((($dstTotal / [double]$srcTotal) - 1.0) * 100.0, 2) }

# [WEBM-025.1] Calculate summary statistics for display
$converted = $conv.Count
$skipped   = ($records | Where-Object {$_.Status -eq 'Skipped'}).Count
$failed    = ($records | Where-Object {$_.Status -eq 'Failed'}).Count
$whatif    = ($records | Where-Object {$_.Status -eq 'WhatIf'}).Count

# [WEBM-025.2] Write operation log if path specified
if ($LogPath) { Write-LogRecords -Records $records -LogPath $LogPath }

# [WEBM-025.3] Display final summary to user
if (-not $Silent) { Write-Host "" }
Write-Host "=== Convert-ToWebM Summary ==="
Write-Host ("Converted: {0}" -f $converted)
Write-Host ("Skipped:   {0}" -f $skipped)
if ($whatif -gt 0) { Write-Host ("WhatIf:    {0}" -f $whatif) }
Write-Host ("Failed:    {0}" -f $failed)
if ($converted -gt 0) {
    Write-Host ("Size Total → Src: {0}  Dst: {1}  Δ: {2} ({3}%)" -f (Format-Bytes $srcTotal),(Format-Bytes $dstTotal),(Format-Bytes $delta),$pct)
}

# [WEBM-026] Handle source file cleanup if requested
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