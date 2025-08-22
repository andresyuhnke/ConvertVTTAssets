# ConvertVTTAssets.psm1 (v1.5.1)
# Public functions:
#   Convert-ToWebM  (animated -> .webm)
#   Convert-ToWebP  (static   -> .webp)

#region ===== Version-gated parallel helpers =====
$script:IsPS7 = $PSVersionTable.PSVersion.Major -ge 7
if ($script:IsPS7) {
    . $PSScriptRoot\ConvertVTTAssets.Core.ps1
}
#endregion

#region ===== Shared Helpers =====

function Test-Tool {
    param([Parameter(Mandatory=$true)][string]$Name)
    $ErrorActionPreferenceBackup = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    $null = & $Name -version 2>$null
    $ErrorActionPreference = $ErrorActionPreferenceBackup
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
        throw "Required tool '$Name' not found or not executable. Add it to PATH or pass a full path."
    }
}

function Invoke-FFProbeJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$FfprobePath
    )
    $args = @('-v','error','-print_format','json','-select_streams','v:0','-show_streams','-show_format',$Path)
    $json = & $FfprobePath @args 2>$null
    if (-not $json) { return $null }
    try { return $json | ConvertFrom-Json } catch { return $null }
}

function Get-HasAlpha {
    param($Info)
    if (-not $Info) { return $false }
    $fmt = $Info.streams[0].pix_fmt
    if (-not $fmt) { return $false }
    return ($fmt -match 'a') -or ($fmt -match 'rgba|bgra|argb|abgr|ya8|yuva420p|yuva422p|yuva444p')
}

function Get-FrameRate {
    param($Info)
    if (-not $Info) { return $null }
    $r = $Info.streams[0].avg_frame_rate
    if ([string]::IsNullOrWhiteSpace($r) -or $r -eq '0/0') {
        $r = $Info.streams[0].r_frame_rate
    }
    if (-not $r -or $r -eq '0/0') { return $null }
    if ($r -match '^\d+/\d+$') {
        $num,$den = $r -split '/'
        if ([int]$den -ne 0) { return [double]$num / [double]$den }
        else { return $null }
    }
    [double]::TryParse($r, [ref]([double]$fr = 0)) | Out-Null
    if ($fr -gt 0) { return $fr } else { return $null }
}

function Get-Width { param($Info) if (-not $Info) { return $null } return $Info.streams[0].width }
function Get-Height{ param($Info) if (-not $Info) { return $null } return $Info.streams[0].height }

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
    if ($SrcWidth -and $SrcWidth -gt $MaxWidth) {
        $filters += "scale=min(iw\,${MaxWidth}):-2:flags=lanczos"
    }
    if ($SrcFps -and ($SrcFps -gt $MaxFPS)) {
        $filters += "fps=${MaxFPS}"
    }
    if ($AlphaMode -eq 'disable' -and $FlattenBlack) {
        $filters += "format=yuv420p"
    }
    if ($filters.Count -gt 0) { return ($filters -join ',') }
    return $null
}

function Get-DestinationPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$false)][string]$OutputRoot,
        [Parameter(Mandatory=$true)][string]$NewExtension
    )

    if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        $destDir = $SourceFile.DirectoryName
    } else {
        $rootFull = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\')
        $srcDirFull = (Resolve-Path -LiteralPath $SourceFile.DirectoryName).Path.TrimEnd('\')

        $rootUri = New-Object System.Uri(($rootFull + '\'))
        $dirUri  = New-Object System.Uri(($srcDirFull + '\'))
        $relUri  = $rootUri.MakeRelativeUri($dirUri).ToString()
        $relPath = [System.Uri]::UnescapeDataString($relUri) -replace '/', '\'

        if ([string]::IsNullOrWhiteSpace($relPath)) { $destDir = $OutputRoot }
        else { $destDir = Join-Path $OutputRoot $relPath }

        if (-not (Test-Path -LiteralPath $destDir)) {
            if ($PSCmdlet.ShouldProcess($destDir, "Create destination directory")) {
                New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            } else {
                Write-Host "WhatIf: would create directory '$destDir'"
            }
        }
    }

    $destName = [System.IO.Path]::GetFileNameWithoutExtension($SourceFile.Name) + $NewExtension
    return (Join-Path $destDir $destName)
}

function Move-ToRecycleBin {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory=$true)][string]$Path)

    try { Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue } catch {
    Write-Verbose "Add-Type already loaded or not available: $_"
}

    if ($PSCmdlet.ShouldProcess($Path, "Send to Recycle Bin")) {
        try {
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

function Write-LogRecords {
    param(
        [Parameter(Mandatory=$true)][System.Collections.IEnumerable]$Records,
        [Parameter(Mandatory=$true)][string]$LogPath
    )
    $dir = [System.IO.Path]::GetDirectoryName($LogPath)
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    $ext = [System.IO.Path]::GetExtension($LogPath).ToLower()
    switch ($ext) {
        '.csv'  { $Records | Export-Csv -NoTypeInformation -Path $LogPath -Encoding UTF8 }
        '.json' { $Records | ConvertTo-Json -Depth 5 | Set-Content -Path $LogPath -Encoding UTF8 }
        default { $Records | Export-Csv -NoTypeInformation -Path $LogPath -Encoding UTF8 }
    }
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -eq $null) { return '' }
    $sizes = 'B','KB','MB','GB','TB'
    $i = 0; $val = [double]$Bytes
    while ($val -ge 1024 -and $i -lt $sizes.Length-1) { $val /= 1024; $i++ }
    return ('{0:N2} {1}' -f $val, $sizes[$i])
}

#endregion ===== Shared Helpers =====

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

Test-Tool -Name $FfmpegPath
Test-Tool -Name $FfprobePath

$recurse = -not $NoRecurse.IsPresent
$extensions = @('.gif','.webp','.mp4','.m4v','.mov','.mkv','.apng')
if ($IncludeExt) {
    $extensions += ($IncludeExt | ForEach-Object { $_.ToLower() })
    $extensions = $extensions | Select-Object -Unique
}
if ($ExcludeExt) {
    $excludeSet = [System.Collections.Generic.HashSet[string]]::new([string[]]($ExcludeExt | ForEach-Object { $_.ToLower() }))
    $extensions = $extensions | Where-Object { -not $excludeSet.Contains($_) }
}

$files = Get-ChildItem -LiteralPath $Root -File -Recurse:$recurse |
    Where-Object { $extensions -contains ([System.IO.Path]::GetExtension($_.Name).ToLower()) } |
    Sort-Object FullName

if (-not $files) { Write-Verbose "No candidate files under '$Root'."; return }

# Initialize progress tracking
$totalFiles = @($files).Count
$fileNum = 0
if (-not $Silent -and $totalFiles -gt 0) {
    Write-Host ""
    Write-Host "=== Convert-ToWebM Starting ===" -ForegroundColor Cyan
    Write-Host "Found $totalFiles file(s) to process" -ForegroundColor Yellow
    Write-Host ""
}

# Choose engine
$records = @()
if ($Parallel) {
    if (-not $script:IsPS7) {
        Write-Warning "-Parallel requested but you're on Windows PowerShell 5.1. Falling back to sequential. For real parallelism, run in PowerShell 7+ (pwsh)."
    } else {
        $settings = @{
            Root = $Root; OutputRoot=$OutputRoot; Force=$Force;
            FfmpegPath=$FfmpegPath; FfprobePath=$FfprobePath;
            MaxFPS=$MaxFPS; MaxWidth=$MaxWidth; Codec=$Codec;
            MaxBitrateKbps=$MaxBitrateKbps; AlphaMode=$AlphaMode;
            AlphaBackground=$AlphaBackground; ThrottleLimit=$ThrottleLimit;
            WhatIfPreference=$WhatIfPreference; VerbosePreference=$VerbosePreference;
            Silent=$Silent
        }
        $records = Invoke-WebMParallel -Files $files -S $settings
    }
} 

if ($records.Count -eq 0) {
    # Sequential engine
    foreach ($f in $files) {
        # Progress output
        if (-not $Silent) {
            $fileNum++
            $percentComplete = [math]::Round(($fileNum / $totalFiles) * 100, 0)
            $fileName = Split-Path $f.Name -Leaf
            Write-Host ("[{0,3}%] Processing {1}/{2}: {3}" -f $percentComplete, $fileNum, $totalFiles, $fileName) -ForegroundColor Cyan
        }
        
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
            $dest = Get-DestinationPath -SourceFile $f -Root $Root -OutputRoot $OutputRoot -NewExtension '.webm'
            $result.Destination = $dest

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

            $info = Invoke-FFProbeJson -Path $f.FullName -FfprobePath $FfprobePath
            $hasAlpha = $false
            if ($info) { $hasAlpha = Get-HasAlpha -Info $info }
            elseif ($f.Extension.ToLower() -in @('.gif','.apng','.webp')) { $hasAlpha = $true }
            switch ($AlphaMode) {
                'force'   { $hasAlpha = $true }
                'disable' { $hasAlpha = $false }
            }
            $result.HasAlpha = $hasAlpha

            $srcW = Get-Width  -Info $info
            $srcH = Get-Height -Info $info
            $srcFps = Get-FrameRate -Info $info

            $vf = $null
            $useFlatten = ($AlphaMode -eq 'disable' -and -not $AlphaBackground)
            $vf = Get-FilterGraph -SrcWidth $srcW -SrcFps $srcFps -MaxWidth $MaxWidth -MaxFPS $MaxFPS -AlphaMode $AlphaMode -FlattenBlack:$useFlatten

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
            if ($MaxBitrateKbps -gt 0) {
                $codecArgs += @('-maxrate', ("{0}k" -f $MaxBitrateKbps), '-bufsize', ("{0}k" -f ($MaxBitrateKbps*2)))
            }

            $args = @('-y','-hide_banner','-loglevel','error','-i', $f.FullName)

            $filtersApplied = $false
            if ($AlphaMode -eq 'disable' -and $AlphaBackground) {
                $w = $srcW; $h = $srcH
                if ($w -and $h -and $w -gt 0 -and $h -gt 0) {
                    $bg = $AlphaBackground.Trim('#')
                    $fc = @()
                    if ($MaxFPS -gt 0) { $fc += ("fps={0}" -f $MaxFPS) }
                    if ($MaxWidth -gt 0 -and $w -gt $MaxWidth) { $fc += ("scale=min(iw\,{0}):-2:flags=lanczos" -f $MaxWidth) }
                    if ($fc.Count -eq 0) { $fc = @('format=rgba') } else { $fc.Insert(0,'format=rgba') }
                    $filterComplex = "color=c=#${bg}:s=${w}x${h}[bg];[0:v]" + ($fc -join ',') + "[v];[bg][v]overlay=format=auto,format=yuv420p"
                    $args += @('-filter_complex', $filterComplex)
                    $filtersApplied = $true
                }
            }

            if (-not $filtersApplied) {
                if ($vf) { $args += @('-filter:v', $vf) }
            }

            $args += $codecArgs
            $args += @('-an','-f','webm', $dest)

            if ($WhatIfPreference) {
                Write-Host "WhatIf: would convert '$($f.FullName)' → '$dest'"
                $result.Status = 'WhatIf'
                $records += [pscustomobject]$result
                continue
            }

            & $FfmpegPath @args
            $ok = ($LASTEXITCODE -eq 0)
            if ($ok) {
                $result.Status = 'Converted'
                $dst = Get-Item $dest -ErrorAction SilentlyContinue
                if ($dst) {
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

# Summary section
# Totals for converted items only
$conv = $records | Where-Object {$_.Status -eq 'Converted'}
$srcTotal = ($conv | Measure-Object -Property SrcBytes -Sum).Sum
$dstTotal = ($conv | Measure-Object -Property DstBytes -Sum).Sum
$delta    = $dstTotal - $srcTotal
$pct      = $null
if ($srcTotal -gt 0) { $pct = [math]::Round((($dstTotal / [double]$srcTotal) - 1.0) * 100.0, 2) }

$converted = $conv.Count
$skipped   = ($records | Where-Object {$_.Status -eq 'Skipped'}).Count
$failed    = ($records | Where-Object {$_.Status -eq 'Failed'}).Count
$whatif    = ($records | Where-Object {$_.Status -eq 'WhatIf'}).Count

if ($LogPath) { Write-LogRecords -Records $records -LogPath $LogPath }

if (-not $Silent) { Write-Host "" }
Write-Host "=== Convert-ToWebM Summary ==="
Write-Host ("Converted: {0}" -f $converted)
Write-Host ("Skipped:   {0}" -f $skipped)
if ($whatif -gt 0) { Write-Host ("WhatIf:    {0}" -f $whatif) }
Write-Host ("Failed:    {0}" -f $failed)
if ($converted -gt 0) {
    Write-Host ("Size Total → Src: {0}  Dst: {1}  Δ: {2} ({3}%)" -f (Format-Bytes $srcTotal),(Format-Bytes $dstTotal),(Format-Bytes $delta),$pct)
}

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

Test-Tool -Name $FfmpegPath
Test-Tool -Name $FfprobePath

$recurse = -not $NoRecurse.IsPresent
$extensions = @('.png','.jpg','.jpeg','.tif','.tiff','.bmp')
if ($IncludeExt) {
    $extensions += ($IncludeExt | ForEach-Object { $_.ToLower() })
    $extensions = $extensions | Select-Object -Unique
}
if ($ExcludeExt) {
    $excludeSet = [System.Collections.Generic.HashSet[string]]::new([string[]]($ExcludeExt | ForEach-Object { $_.ToLower() }))
    $extensions = $extensions | Where-Object { -not $excludeSet.Contains($_) }
}

$files = Get-ChildItem -LiteralPath $Root -File -Recurse:$recurse |
    Where-Object { $extensions -contains ([System.IO.Path]::GetExtension($_.Name).ToLower()) } |
    Sort-Object FullName

if (-not $files) { Write-Verbose "No candidate static images under '$Root'."; return }

# Initialize progress tracking
$totalFiles = @($files).Count
$fileNum = 0
if (-not $Silent -and $totalFiles -gt 0) {
    Write-Host ""
    Write-Host "=== Convert-ToWebP Starting ===" -ForegroundColor Cyan
    Write-Host "Found $totalFiles file(s) to process" -ForegroundColor Yellow
    Write-Host ""
}

$records = @()
if ($Parallel) {
    if (-not $script:IsPS7) {
        Write-Warning "-Parallel requested but you're on Windows PowerShell 5.1. Falling back to sequential. For real parallelism, run in PowerShell 7+ (pwsh)."
    } else {
        $settings = @{
            Root=$Root; OutputRoot=$OutputRoot; Force=$Force;
            FfmpegPath=$FfmpegPath; FfprobePath=$FfprobePath;
            Quality=$Quality; Lossless=$Lossless; MaxWidth=$MaxWidth;
            ThrottleLimit=$ThrottleLimit;
            WhatIfPreference=$WhatIfPreference; VerbosePreference=$VerbosePreference;
            Silent=$Silent
        }
        $records = Invoke-WebPParallel -Files $files -S $settings
    }
}

if ($records.Count -eq 0) {
    # Sequential
    foreach ($f in $files) {
        # Progress output
        if (-not $Silent) {
            $fileNum++
            $percentComplete = [math]::Round(($fileNum / $totalFiles) * 100, 0)
            $fileName = Split-Path $f.Name -Leaf
            Write-Host ("[{0,3}%] Processing {1}/{2}: {3}" -f $percentComplete, $fileNum, $totalFiles, $fileName) -ForegroundColor Cyan
        }
        
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
            $dest = Get-DestinationPath -SourceFile $f -Root $Root -OutputRoot $OutputRoot -NewExtension '.webp'
            $result.Destination = $dest

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

            $info = Invoke-FFProbeJson -Path $f.FullName -FfprobePath $FfprobePath
            $srcW = Get-Width  -Info $info

            $vf = $null
            if ($srcW -and $srcW -gt $MaxWidth) { $vf = "scale=min(iw\,${MaxWidth}):-2:flags=lanczos" }

            $args = @('-y','-hide_banner','-loglevel','error','-i', $f.FullName)
            if ($vf) { $args += @('-vf', $vf) }

            $args += @('-c:v','libwebp')
            if ($Lossless) { $args += @('-lossless','1','-compression_level','6') }
            else { $args += @('-q:v', $Quality) }

            $args += @('-frames:v','1', $dest)

            if ($WhatIfPreference) {
                Write-Host "WhatIf: would convert '$($f.FullName)' → '$dest'"
                $result.Status = 'WhatIf'
                $records += [pscustomobject]$result
                continue
            }

            & $FfmpegPath @args
            $ok = ($LASTEXITCODE -eq 0)
            if ($ok) {
                $result.Status = 'Converted'
                $dst = Get-Item $dest -ErrorAction SilentlyContinue
                if ($dst) {
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

# Summary section
# Totals for converted items only
$conv = $records | Where-Object {$_.Status -eq 'Converted'}
$srcTotal = ($conv | Measure-Object -Property SrcBytes -Sum).Sum
$dstTotal = ($conv | Measure-Object -Property DstBytes -Sum).Sum
$delta    = $dstTotal - $srcTotal
$pct      = $null
if ($srcTotal -gt 0) { $pct = [math]::Round((($dstTotal / [double]$srcTotal) - 1.0) * 100.0, 2) }

$converted = $conv.Count
$skipped   = ($records | Where-Object {$_.Status -eq 'Skipped'}).Count
$failed    = ($records | Where-Object {$_.Status -eq 'Failed'}).Count
$whatif    = ($records | Where-Object {$_.Status -eq 'WhatIf'}).Count

if ($LogPath) { Write-LogRecords -Records $records -LogPath $LogPath }

if (-not $Silent) { Write-Host "" }
Write-Host "=== Convert-ToWebP Summary ==="
Write-Host ("Converted: {0}" -f $converted)
Write-Host ("Skipped:   {0}" -f $skipped)
if ($whatif -gt 0) { Write-Host ("WhatIf:    {0}" -f $whatif) }
Write-Host ("Failed:    {0}" -f $failed)
if ($converted -gt 0) {
    Write-Host ("Size Total → Src: {0}  Dst: {1}  Δ: {2} ({3}%)" -f (Format-Bytes $srcTotal),(Format-Bytes $dstTotal),(Format-Bytes $delta),$pct)
}

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

function Optimize-FileNames {
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory=$true)]
    [string]$Root,
    
    [switch]$NoRecurse,
    
    [string[]]$IncludeExt,
    
    [string[]]$ExcludeExt,
    
    [switch]$RemoveMetadata,
    
    [ValidateSet('Remove','Dash','Underscore')]
    [string]$SpaceReplacement = 'Underscore',
    
    [switch]$LowercaseExtensions,
    
    [switch]$PreserveCase,
    
    [switch]$ExpandAmpersand,
    
    [string]$LogPath,
    
    [string]$UndoLogPath,  # NEW: Dedicated undo log path
    
    [switch]$Silent,
    
    [switch]$Force
)

# Validate root path exists
if (-not (Test-Path -LiteralPath $Root)) {
    throw "Path not found: $Root"
}

# Generate automatic undo log path if not specified but LogPath is provided
if (-not $UndoLogPath -and $LogPath) {
    $logDir = [System.IO.Path]::GetDirectoryName($LogPath)
    $logName = [System.IO.Path]::GetFileNameWithoutExtension($LogPath)
    $UndoLogPath = Join-Path $logDir "${logName}_undo.json"
}

# Initialize collections
$renameOperations = @()
$errors = @()
$skipped = @()
$renamedPaths = @{} # Track renamed paths for child file updates
$operationId = 0

# Define problematic characters for web URIs
$problematicChars = @(
    '*', '"', '[', ']', ':', ';', '|', ',', '&', '=', '+', '$', '?', '%', '#',
    '(', ')', '{', '}', '<', '>', '!', '@', '^', '~', '`', "'"
)

# Create undo log metadata
$undoMetadata = @{
    timestamp = (Get-Date).ToString('o')  # ISO 8601 format
    root_path = (Resolve-Path -LiteralPath $Root).Path
    settings = @{
        RemoveMetadata = $RemoveMetadata.IsPresent
        SpaceReplacement = $SpaceReplacement
        LowercaseExtensions = $LowercaseExtensions.IsPresent
        PreserveCase = $PreserveCase.IsPresent
        ExpandAmpersand = $ExpandAmpersand.IsPresent
        Force = $Force.IsPresent
    }
    powershell_version = $PSVersionTable.PSVersion.ToString()
    module_version = (Get-Module ConvertVTTAssets).Version.ToString()
}

# Get all files and directories
$recurse = -not $NoRecurse.IsPresent
$allItems = Get-ChildItem -LiteralPath $Root -Recurse:$recurse

# Filter by extension if specified (for files only)
if ($IncludeExt -or $ExcludeExt) {
    $includeSet = if ($IncludeExt) { 
        [System.Collections.Generic.HashSet[string]]::new([string[]]($IncludeExt | ForEach-Object { $_.ToLower() }))
    } else { 
        $null 
    }
    
    $excludeSet = if ($ExcludeExt) { 
        [System.Collections.Generic.HashSet[string]]::new([string[]]($ExcludeExt | ForEach-Object { $_.ToLower() }))
    } else { 
        $null 
    }
    
    $allItems = $allItems | Where-Object {
        if ($_.PSIsContainer) { return $true } # Always include directories
        $ext = [System.IO.Path]::GetExtension($_.Name).ToLower()
        $include = if ($includeSet) { $includeSet.Contains($ext) } else { $true }
        $exclude = if ($excludeSet) { $excludeSet.Contains($ext) } else { $false }
        return $include -and -not $exclude
    }
}

# Sort items - directories first (deepest first for renaming), then files
$directories = $allItems | Where-Object { $_.PSIsContainer } | Sort-Object { $_.FullName.Split('\').Count } -Descending
$files = $allItems | Where-Object { -not $_.PSIsContainer } | Sort-Object FullName

# Process directories first, then files
$itemsToProcess = @($directories) + @($files)

# Initialize progress
$totalItems = $itemsToProcess.Count
$itemNum = 0

if (-not $Silent -and $totalItems -gt 0) {
    Write-Host ""
    Write-Host "=== Optimize-FileNames Starting ===" -ForegroundColor Cyan
    Write-Host "Analyzing $totalItems item(s) for optimization..." -ForegroundColor Yellow
    if ($UndoLogPath) {
        Write-Host "Undo log will be created at: $UndoLogPath" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# Helper function to sanitize names (unchanged)
function Get-SanitizedName {
    param(
        [string]$Name,
        [string]$Extension = ""
    )
    
    # Start with original name
    $newName = $Name
    
    # Step 1: Remove metadata if requested
    if ($RemoveMetadata) {
        $newName = $newName -replace '\([^)]*\)', ''  # Remove (metadata)
        $newName = $newName -replace '\[[^\]]*\]', ''  # Remove [metadata]
        $newName = $newName -replace '_\d+x\d+', ''    # Remove _100x100 dimensions
        $newName = $newName -replace '-\d+x\d+', ''    # Remove -100x100 dimensions
        $newName = $newName -replace '__+', '_'        # Collapse multiple underscores
        $newName = $newName -replace '--+', '-'        # Collapse multiple dashes
        $newName = $newName -replace '[_-]+$', ''      # Remove trailing separators
        $newName = $newName -replace '^[_-]+', ''      # Remove leading separators
    }
    
    # Step 2: Handle spaces
    switch ($SpaceReplacement) {
        'Remove'     { $newName = $newName -replace '\s+', '' }
        'Dash'       { $newName = $newName -replace '\s+', '-' }
        'Underscore' { $newName = $newName -replace '\s+', '_' }
    }
    
    # Step 3: Handle ampersands
    if ($ExpandAmpersand) {
        $newName = $newName -replace '&', '_and_'
        $newName = $newName -replace '_and_+', '_and_'  # Clean up multiple and's
    } else {
        $newName = $newName -replace '&', '_'
    }
    
    # Step 4: Remove or replace other problematic characters
    foreach ($char in $problematicChars) {
        if ($char -ne '&') {  # Already handled ampersands above
            $escaped = [Regex]::Escape($char)
            if ($char -in @('[',']','(',')')) {
                $newName = $newName -replace $escaped, '-'
            } else {
                $newName = $newName -replace $escaped, ''
            }
        }
    }
    
    # Step 5: Clean up multiple separators
    $newName = $newName -replace '_{2,}', '_'
    $newName = $newName -replace '-{2,}', '-'
    $newName = $newName -replace '\.{2,}', '.'
    $newName = $newName -replace '^[_.-]+', ''
    $newName = $newName -replace '[_.-]+$', ''
    
    # Step 6: Handle case conversion
    if (-not $PreserveCase) {
        $newName = $newName.ToLower()
    }
    
    # Step 7: Handle extension
    $newExt = $Extension
    if ($LowercaseExtensions -and $Extension) {
        $newExt = $Extension.ToLower()
    }
    
    # Combine name and extension
    if ($Extension) {
        $finalName = "${newName}${newExt}"
    } else {
        $finalName = $newName
    }
    
    # Ensure we have a valid name
    if ([string]::IsNullOrWhiteSpace($finalName)) {
        $finalName = "unnamed_$(Get-Random -Maximum 9999)"
        if ($Extension) { $finalName += $newExt }
    }
    
    return $finalName
}

# Process each item
foreach ($item in $itemsToProcess) {
    $itemNum++
    $operationId++
    
    # Progress output
    if (-not $Silent) {
        $percentComplete = [math]::Round(($itemNum / $totalItems) * 100, 0)
        $itemType = if ($item.PSIsContainer) { "Dir" } else { "File" }
        Write-Host ("[{0,3}%] Checking {1}/{2}: [{3}] {4}" -f $percentComplete, $itemNum, $totalItems, $itemType, $item.Name) -ForegroundColor Cyan
    }
    
    # Get current path (may have been updated if parent was renamed)
    $currentPath = $item.FullName
    foreach ($oldPath in $renamedPaths.Keys | Sort-Object -Property Length -Descending) {
        if ($currentPath.StartsWith($oldPath)) {
            $currentPath = $currentPath.Replace($oldPath, $renamedPaths[$oldPath])
            break
        }
    }
    
    # Skip if item no longer exists (parent was renamed)
    if (-not (Test-Path -LiteralPath $currentPath)) {
        if (-not $Silent) {
            Write-Host "       ⚠ Skipped: Parent directory was renamed" -ForegroundColor Yellow
        }
        continue
    }
    
    # Get updated item
    $currentItem = Get-Item -LiteralPath $currentPath
    
    # Get original name components
    $originalName = $currentItem.Name
    $isDirectory = $currentItem.PSIsContainer
    
    # Get parent directory
    if ($isDirectory) {
        $directory = $currentItem.Parent.FullName
        if (-not $directory) {
            $directory = Split-Path $currentPath -Parent
        }
    } else {
        $directory = $currentItem.DirectoryName
    }
    
    # For files, separate name and extension
    if (-not $isDirectory) {
        $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($originalName)
        $extension = [System.IO.Path]::GetExtension($originalName)
    } else {
        $nameWithoutExt = $originalName
        $extension = ""
    }
    
    # Get sanitized name
    $newName = Get-SanitizedName -Name $nameWithoutExt -Extension $extension
    
    # Check if rename is needed
    if ($newName -eq $originalName) {
        if (-not $Silent) {
            Write-Host "       ✓ Already optimized" -ForegroundColor Green
        }
        continue
    }
    
    # Build the new full path
    $newPath = Join-Path $directory $newName
    
    # Check if target already exists
    if ((Test-Path -LiteralPath $newPath) -and ($currentPath -ne $newPath) -and -not $Force) {
        if (-not $Silent) {
            Write-Host "       ⚠ Skipped: Target name already exists: $newName" -ForegroundColor Yellow
        }
        $skipped += [PSCustomObject]@{
            Original = $currentPath
            Proposed = $newPath
            Reason = "Target exists"
        }
        continue
    }
    
    # Get file info for undo log
    $fileInfo = Get-Item -LiteralPath $currentPath
    $lastWriteTime = $fileInfo.LastWriteTimeUtc.ToString('o')
    $fileSize = if ($isDirectory) { $null } else { $fileInfo.Length }
    
    # Create enhanced operation record with undo information
    $operation = [PSCustomObject]@{
        # Standard operation log fields
        Time = (Get-Date).ToString('s')
        Type = if ($isDirectory) { "Directory" } else { "File" }
        OriginalPath = $currentPath
        OriginalName = $originalName
        NewPath = $newPath
        NewName = $newName
        Status = "Pending"
        Error = ""
        
        # Enhanced undo log fields
        OperationId = $operationId
        ParentDirectory = $directory
        LastWriteTime = $lastWriteTime
        FileSize = $fileSize
        Dependencies = @()  # Will be filled in later for directories
    }
    
    # Perform rename
    if ($PSCmdlet.ShouldProcess($currentPath, "Rename to $newName")) {
        try {
            # Handle existing file if Force is specified
            if ((Test-Path -LiteralPath $newPath) -and ($currentPath -ne $newPath) -and $Force) {
                if (-not $Silent) {
                    Write-Host "       ⚠ Overwriting existing: $newName" -ForegroundColor Yellow
                }
                Remove-Item -LiteralPath $newPath -Force
            }
            
            # Perform the rename
            Rename-Item -LiteralPath $currentPath -NewName $newName -Force:$Force -ErrorAction Stop
            $operation.Status = "Success"
            
            # Track renamed directories for updating child paths
            if ($isDirectory) {
                $renamedPaths[$currentPath] = $newPath
            }
            
            if (-not $Silent) {
                Write-Host "       ✓ Renamed: $originalName → $newName" -ForegroundColor Green
            }
        } catch {
            $operation.Status = "Failed"
            $operation.Error = $_.Exception.Message
            $errors += $operation
            
            if (-not $Silent) {
                Write-Host "       ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    } else {
        $operation.Status = "WhatIf"
        if (-not $Silent) {
            Write-Host "       → Would rename: $originalName → $newName" -ForegroundColor Cyan
        }
    }
    
    $renameOperations += $operation
}

# Create comprehensive undo log
if ($UndoLogPath -and $renameOperations.Count -gt 0) {
    $successfulOps = $renameOperations | Where-Object { $_.Status -eq "Success" }
    
    if ($successfulOps.Count -gt 0) {
        # Build dependency relationships for directories
        foreach ($op in $successfulOps | Where-Object { $_.Type -eq "Directory" }) {
            # Find all operations that occurred within this directory
            $dependents = $successfulOps | Where-Object { 
                $_.OperationId -ne $op.OperationId -and 
                $_.OriginalPath.StartsWith($op.NewPath)  # Use new path since rename already happened
            }
            
            $op.Dependencies = @($dependents | ForEach-Object { $_.OperationId })
        }
        
# Add total operations to metadata before creating the hash
        $undoMetadata.total_operations = $successfulOps.Count
        
        $undoLog = @{
            metadata = $undoMetadata
            operations = @($successfulOps | ForEach-Object {
                @{
                    operation_id = $_.OperationId
                    type = $_.Type
                    original_path = $_.OriginalPath
                    new_path = $_.NewPath
                    original_name = $_.OriginalName
                    new_name = $_.NewName
                    parent_directory = $_.ParentDirectory
                    timestamp = $_.Time
                    last_write_time = $_.LastWriteTime
                    file_size = $_.FileSize
                    dependencies = $_.Dependencies
                }
            })
        }
        
        # Ensure directory exists
        $undoLogDir = [System.IO.Path]::GetDirectoryName($UndoLogPath)
        if ($undoLogDir -and -not (Test-Path $undoLogDir)) {
            New-Item -ItemType Directory -Force -Path $undoLogDir | Out-Null
        }
        
        # Write undo log
        $undoLog | ConvertTo-Json -Depth 10 | Set-Content -Path $UndoLogPath -Encoding UTF8
        
        if (-not $Silent) {
            Write-Host ""
            Write-Host "Undo log created: $UndoLogPath" -ForegroundColor Green
            Write-Host "  Operations logged: $($successfulOps.Count)" -ForegroundColor DarkGray
        }
    }
}

# Write standard log if requested
if ($LogPath) {
    $dir = [System.IO.Path]::GetDirectoryName($LogPath)
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    
    $logData = @{
        Timestamp = (Get-Date).ToString('s')
        Root = $Root
        TotalItems = $totalItems
        Operations = $renameOperations
        Skipped = $skipped
        Settings = @{
            SpaceReplacement = $SpaceReplacement
            RemoveMetadata = $RemoveMetadata
            LowercaseExtensions = $LowercaseExtensions
            PreserveCase = $PreserveCase
            ExpandAmpersand = $ExpandAmpersand
        }
    }
    
    $ext = [System.IO.Path]::GetExtension($LogPath).ToLower()
    switch ($ext) {
        '.json' { $logData | ConvertTo-Json -Depth 5 | Set-Content -Path $LogPath -Encoding UTF8 }
        default { $renameOperations | Export-Csv -NoTypeInformation -Path $LogPath -Encoding UTF8 }
    }
}

# Summary
$successful = ($renameOperations | Where-Object { $_.Status -eq "Success" }).Count
$failed = ($renameOperations | Where-Object { $_.Status -eq "Failed" }).Count
$whatif = ($renameOperations | Where-Object { $_.Status -eq "WhatIf" }).Count
$skippedCount = $skipped.Count

if (-not $Silent) { Write-Host "" }
Write-Host "=== Optimize-FileNames Summary ===" -ForegroundColor Cyan
Write-Host "Renamed:  $successful" -ForegroundColor Green
Write-Host "Skipped:  $skippedCount" -ForegroundColor Yellow
if ($whatif -gt 0) { Write-Host "WhatIf:   $whatif" -ForegroundColor Cyan }
if ($failed -gt 0) { Write-Host "Failed:   $failed" -ForegroundColor Red }

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "Errors encountered:" -ForegroundColor Red
    foreach ($err in $errors) {
        Write-Host "  - $($err.OriginalName): $($err.Error)" -ForegroundColor Red
    }
}

# Return summary object
return [PSCustomObject]@{
    TotalItems = $totalItems
    Renamed = $successful
    Skipped = $skippedCount
    Failed = $failed
    WhatIf = $whatif
    Operations = $renameOperations
    UndoLogPath = $UndoLogPath
}
}

function Undo-FileNameOptimization {
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory=$true)]
    [string]$UndoLogPath,
    
    [switch]$Force,
    
    [switch]$Silent,
    
    [string]$BackupUndoLogPath  # Create backup of undo log before processing
)

# Validate undo log exists
if (-not (Test-Path -LiteralPath $UndoLogPath)) {
    throw "Undo log not found: $UndoLogPath"
}

# Read and validate undo log
try {
    $undoLogContent = Get-Content -LiteralPath $UndoLogPath -Raw -Encoding UTF8
    $undoLog = $undoLogContent | ConvertFrom-Json
} catch {
    throw "Failed to read or parse undo log: $($_.Exception.Message)"
}

# Validate undo log structure
if (-not $undoLog.metadata -or -not $undoLog.operations) {
    throw "Invalid undo log format. Missing required 'metadata' or 'operations' sections."
}

if (-not $undoLog.operations -or $undoLog.operations.Count -eq 0) {
    Write-Warning "Undo log contains no operations to reverse."
    return
}

# Create backup of undo log if requested
if ($BackupUndoLogPath) {
    $backupDir = [System.IO.Path]::GetDirectoryName($BackupUndoLogPath)
    if ($backupDir -and -not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    }
    
    Copy-Item -LiteralPath $UndoLogPath -Destination $BackupUndoLogPath -Force
    if (-not $Silent) {
        Write-Host "Undo log backed up to: $BackupUndoLogPath" -ForegroundColor DarkGray
    }
}

# Initialize collections
$undoOperations = @()
$errors = @()
$warnings = @()
$skipped = @()

# Get operations and sort them for proper undo order
# Directories with dependencies must be undone after their children
$operations = $undoLog.operations

# Sort operations: files first, then directories by dependency depth (deepest first)
$fileOps = $operations | Where-Object { $_.type -eq "File" }
$dirOps = $operations | Where-Object { $_.type -eq "Directory" }

# Sort directories by dependency count (most dependencies = deepest = undo last)
$sortedDirOps = $dirOps | Sort-Object { $_.dependencies.Count } -Descending

# Combine: files first, then directories in reverse dependency order
$sortedOperations = @($fileOps) + @($sortedDirOps)

# Initialize progress
$totalOps = $sortedOperations.Count
$opNum = 0

if (-not $Silent) {
    Write-Host ""
    Write-Host "=== Undo-FileNameOptimization Starting ===" -ForegroundColor Cyan
    Write-Host "Original optimization: $($undoLog.metadata.timestamp)" -ForegroundColor DarkGray
    Write-Host "Root path: $($undoLog.metadata.root_path)" -ForegroundColor DarkGray
    Write-Host "Operations to undo: $totalOps" -ForegroundColor Yellow
    Write-Host ""
}

# Validation pass: check current state before making any changes
if (-not $Silent) {
    Write-Host "Validating current state..." -ForegroundColor Yellow
}

$validationErrors = @()
$currentPathMap = @{}  # Track current state

foreach ($op in $sortedOperations) {
    $opNum++
    
    # Progress for validation
    if (-not $Silent) {
        $percentComplete = [math]::Round(($opNum / $totalOps) * 50, 0)  # Validation is first 50%
        Write-Host ("[{0,3}%] Validating {1}/{2}: {3}" -f $percentComplete, $opNum, $totalOps, $op.new_name) -ForegroundColor Cyan
    }
    
    # Check if the "new" file/directory still exists at expected location
    if (-not (Test-Path -LiteralPath $op.new_path)) {
        $validationErrors += "Missing renamed item: $($op.new_path)"
        continue
    }
    
    # Get current file info
    $currentItem = Get-Item -LiteralPath $op.new_path
    
    # For files, validate they haven't been modified
    if ($op.type -eq "File" -and $op.file_size -ne $null) {
        if ($currentItem.Length -ne $op.file_size) {
            $validationErrors += "File size changed: $($op.new_path) (was $($op.file_size), now $($currentItem.Length))"
        }
        
        # Check if last write time is significantly different (allow for small clock differences)
        $originalTime = [DateTime]::Parse($op.last_write_time)
        $timeDiff = [Math]::Abs(($currentItem.LastWriteTimeUtc - $originalTime).TotalSeconds)
        if ($timeDiff -gt 2) {  # Allow 2 second difference for file system precision
            $warnings += "File modified since optimization: $($op.new_path)"
        }
    }
    
    # Check if original name would cause conflicts
    if ((Test-Path -LiteralPath $op.original_path) -and -not $Force) {
        $validationErrors += "Original name already exists: $($op.original_path) (use -Force to overwrite)"
    }
    
    # Track current state for dependency validation
    $currentPathMap[$op.new_path] = $op
}

# Report validation results
if ($validationErrors.Count -gt 0) {
    Write-Host ""
    Write-Host "Validation failed with $($validationErrors.Count) error(s):" -ForegroundColor Red
    foreach ($err in $validationErrors) {
        Write-Host "  ✗ $err" -ForegroundColor Red
    }
    
    if (-not $Force) {
        Write-Host ""
        Write-Host "Use -Force to attempt undo despite validation errors, or fix the issues above." -ForegroundColor Yellow
        return
    } else {
        Write-Host ""
        Write-Host "-Force specified, continuing despite validation errors..." -ForegroundColor Yellow
    }
}

if ($warnings.Count -gt 0 -and -not $Silent) {
    Write-Host ""
    Write-Host "Validation warnings:" -ForegroundColor Yellow
    foreach ($warn in $warnings) {
        Write-Host "  ⚠ $warn" -ForegroundColor Yellow
    }
}

if (-not $Silent) {
    Write-Host ""
    Write-Host "Validation complete. Beginning undo operations..." -ForegroundColor Green
    Write-Host ""
}

# Reset progress counter for undo operations
$opNum = 0

# Perform undo operations
foreach ($op in $sortedOperations) {
    $opNum++
    
    # Progress for undo operations
    if (-not $Silent) {
        $percentComplete = [math]::Round(50 + ($opNum / $totalOps) * 50, 0)  # Undo is second 50%
        Write-Host ("[{0,3}%] Undoing {1}/{2}: {3} → {4}" -f $percentComplete, $opNum, $totalOps, $op.new_name, $op.original_name) -ForegroundColor Cyan
    }
    
    # Create undo operation record
    $undoResult = [PSCustomObject]@{
        OperationId = $op.operation_id
        Type = $op.type
        CurrentPath = $op.new_path
        TargetPath = $op.original_path
        CurrentName = $op.new_name
        TargetName = $op.original_name
        Status = "Pending"
        Error = ""
        Timestamp = (Get-Date).ToString('s')
    }
    
    try {
        # Check if current path still exists
        if (-not (Test-Path -LiteralPath $op.new_path)) {
            $undoResult.Status = "Skipped"
            $undoResult.Error = "Source no longer exists"
            $skipped += $undoResult
            
            if (-not $Silent) {
                Write-Host "       ⚠ Skipped: Source no longer exists" -ForegroundColor Yellow
            }
            continue
        }
        
        # Check for target conflicts
        if ((Test-Path -LiteralPath $op.original_path)) {
            if ($Force) {
                if (-not $Silent) {
                    Write-Host "       ⚠ Overwriting existing file: $($op.original_name)" -ForegroundColor Yellow
                }
                Remove-Item -LiteralPath $op.original_path -Force -Recurse:($op.type -eq "Directory")
            } else {
                $undoResult.Status = "Skipped"
                $undoResult.Error = "Target already exists (use -Force to overwrite)"
                $skipped += $undoResult
                
                if (-not $Silent) {
                    Write-Host "       ⚠ Skipped: Target already exists" -ForegroundColor Yellow
                }
                continue
            }
        }
        
        # Perform the undo rename
        if ($PSCmdlet.ShouldProcess($op.new_path, "Undo rename to $($op.original_name)")) {
            # Get the target directory
            $targetDir = [System.IO.Path]::GetDirectoryName($op.original_path)
            
            # Ensure target directory exists
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
            }
            
            # Perform the rename
            Rename-Item -LiteralPath $op.new_path -NewName $op.original_name -Force:$Force -ErrorAction Stop
            
            $undoResult.Status = "Success"
            
            if (-not $Silent) {
                Write-Host "       ✓ Restored: $($op.new_name) → $($op.original_name)" -ForegroundColor Green
            }
        } else {
            $undoResult.Status = "WhatIf"
            if (-not $Silent) {
                Write-Host "       → Would restore: $($op.new_name) → $($op.original_name)" -ForegroundColor Cyan
            }
        }
        
    } catch {
        $undoResult.Status = "Failed"
        $undoResult.Error = $_.Exception.Message
        $errors += $undoResult
        
        if (-not $Silent) {
            Write-Host "       ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    $undoOperations += $undoResult
}

# Generate summary
$successful = ($undoOperations | Where-Object { $_.Status -eq "Success" }).Count
$failed = ($undoOperations | Where-Object { $_.Status -eq "Failed" }).Count
$whatif = ($undoOperations | Where-Object { $_.Status -eq "WhatIf" }).Count
$skippedCount = ($undoOperations | Where-Object { $_.Status -eq "Skipped" }).Count

if (-not $Silent) { Write-Host "" }
Write-Host "=== Undo-FileNameOptimization Summary ===" -ForegroundColor Cyan
Write-Host "Restored: $successful" -ForegroundColor Green
Write-Host "Skipped:  $skippedCount" -ForegroundColor Yellow
if ($whatif -gt 0) { Write-Host "WhatIf:   $whatif" -ForegroundColor Cyan }
if ($failed -gt 0) { Write-Host "Failed:   $failed" -ForegroundColor Red }

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "Errors encountered:" -ForegroundColor Red
    foreach ($err in $errors) {
        Write-Host "  - Operation $($err.OperationId): $($err.Error)" -ForegroundColor Red
    }
}

# Create undo operation log
$undoLogDir = [System.IO.Path]::GetDirectoryName($UndoLogPath)
$undoLogName = [System.IO.Path]::GetFileNameWithoutExtension($UndoLogPath)
$undoOpLogPath = Join-Path $undoLogDir "${undoLogName}_undo_operations.json"

$undoOpLog = @{
    metadata = @{
        timestamp = (Get-Date).ToString('o')
        original_undo_log = $UndoLogPath
        original_optimization_timestamp = $undoLog.metadata.timestamp
        total_undo_operations = $undoOperations.Count
        successful_undos = $successful
        powershell_version = $PSVersionTable.PSVersion.ToString()
        module_version = (Get-Module ConvertVTTAssets).Version.ToString()
    }
    operations = $undoOperations
    validation_errors = $validationErrors
    warnings = $warnings
}

$undoOpLog | ConvertTo-Json -Depth 10 | Set-Content -Path $undoOpLogPath -Encoding UTF8

if (-not $Silent) {
    Write-Host ""
    Write-Host "Undo operations logged to: $undoOpLogPath" -ForegroundColor Green
}

# Return summary object
return [PSCustomObject]@{
    TotalOperations = $totalOps
    Restored = $successful
    Skipped = $skippedCount
    Failed = $failed
    WhatIf = $whatif
    ValidationErrors = $validationErrors.Count
    Warnings = $warnings.Count
    UndoOperations = $undoOperations
    UndoLogPath = $undoOpLogPath
}
}

# Export all functions
Export-ModuleMember -Function Convert-ToWebM, Convert-ToWebP, Optimize-FileNames, Undo-FileNameOptimization

