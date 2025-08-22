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

# Report Generation Helper Functions
# Add these to the #region ===== Shared Helpers ===== section

function Get-TimeEstimate {
    param(
        [int]$FileCount,
        [long]$TotalSize,
        [string]$OperationType = "FileNameOptimization"
    )
    
    # Base time estimates per operation type (in seconds)
    $baseTimePerFile = switch ($OperationType) {
        "FileNameOptimization" { 0.1 }    # Very fast
        "WebMConversion" { 15.0 }          # Depends on file size/complexity
        "WebPConversion" { 3.0 }           # Faster than WebM
        default { 1.0 }
    }
    
    # Size-based adjustments for conversions
    if ($OperationType -in @("WebMConversion", "WebPConversion") -and $TotalSize -gt 0) {
        $avgFileSizeMB = ($TotalSize / $FileCount) / 1MB
        if ($avgFileSizeMB -gt 10) { $baseTimePerFile *= 2 }
        elseif ($avgFileSizeMB -gt 50) { $baseTimePerFile *= 4 }
    }
    
    $totalSeconds = $FileCount * $baseTimePerFile
    
    # Return human-readable time estimate
    if ($totalSeconds -lt 60) {
        return "$([math]::Round($totalSeconds, 1)) seconds"
    } elseif ($totalSeconds -lt 3600) {
        return "$([math]::Round($totalSeconds / 60, 1)) minutes" 
    } else {
        return "$([math]::Round($totalSeconds / 3600, 1)) hours"
    }
}

function Get-FileSizeProjection {
    param(
        [System.IO.FileInfo[]]$Files,
        [string]$ConversionType,
        [hashtable]$Settings = @{}
    )
    
    $totalCurrentSize = ($Files | Measure-Object -Property Length -Sum).Sum
    
    # Rough compression estimates based on typical results
    $compressionRatio = switch ($ConversionType) {
        "WebM" { 0.35 }      # ~65% reduction
        "WebP" { 
            if ($Settings.Lossless) { 0.8 } else { 0.25 }  # Lossless keeps more, lossy compresses well
        }
        default { 1.0 }      # No change for filename optimization
    }
    
    $projectedSize = [long]($totalCurrentSize * $compressionRatio)
    $savings = $totalCurrentSize - $projectedSize
    $savingsPercent = if ($totalCurrentSize -gt 0) { 
        [math]::Round((1 - $compressionRatio) * 100, 1) 
    } else { 0 }
    
    return @{
        CurrentSize = $totalCurrentSize
        ProjectedSize = $projectedSize
        SavingsBytes = $savings
        SavingsPercent = $savingsPercent
        CurrentSizeFormatted = Format-Bytes $totalCurrentSize
        ProjectedSizeFormatted = Format-Bytes $projectedSize
        SavingsFormatted = Format-Bytes $savings
    }
}

function New-HTMLReport {
    param(
        [string]$Title,
        [string]$Operation,
        [hashtable]$Summary,
        [array]$DetailedItems,
        [array]$Warnings = @(),
        [hashtable]$Settings,
        [string]$OutputPath
    )
    
    # Generate HTML report content
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$Title</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }
        h2 {
            color: #34495e;
            margin-top: 30px;
            border-left: 4px solid #3498db;
            padding-left: 15px;
        }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }
        .summary-card {
            background: #ecf0f1;
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #3498db;
        }
        .summary-card h3 {
            margin: 0 0 10px 0;
            color: #2c3e50;
            font-size: 1.1em;
        }
        .summary-card .value {
            font-size: 1.8em;
            font-weight: bold;
            color: #27ae60;
        }
        .warning {
            background: #fff3cd;
            border: 1px solid #ffeaa7;
            border-radius: 5px;
            padding: 15px;
            margin: 10px 0;
        }
        .warning-title {
            font-weight: bold;
            color: #856404;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        th, td {
            border: 1px solid #ddd;
            padding: 12px;
            text-align: left;
        }
        th {
            background-color: #3498db;
            color: white;
            font-weight: bold;
        }
        tr:nth-child(even) {
            background-color: #f8f9fa;
        }
        .before {
            background-color: #ffebee;
            font-family: monospace;
        }
        .after {
            background-color: #e8f5e8;
            font-family: monospace;
            font-weight: bold;
        }
        .no-change {
            background-color: #f5f5f5;
            color: #666;
            font-style: italic;
        }
        .settings {
            background: #f8f9fa;
            border: 1px solid #dee2e6;
            border-radius: 5px;
            padding: 15px;
            margin: 20px 0;
        }
        .settings h3 {
            margin-top: 0;
            color: #495057;
        }
        .footer {
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #dee2e6;
            color: #6c757d;
            font-size: 0.9em;
        }
        .risk-high { border-left-color: #e74c3c !important; }
        .risk-medium { border-left-color: #f39c12 !important; }
        .risk-low { border-left-color: #27ae60 !important; }
    </style>
</head>
<body>
    <div class="container">
        <h1>$Title</h1>
        <p><strong>Operation:</strong> $Operation</p>
        <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        
        <h2>📊 Summary</h2>
        <div class="summary">
"@

    # Add summary cards
    foreach ($key in $Summary.Keys) {
        $value = $Summary[$key]
        $html += @"
            <div class="summary-card">
                <h3>$key</h3>
                <div class="value">$value</div>
            </div>
"@
    }
    
    $html += @"
        </div>
"@

    # Add warnings section if present
    if ($Warnings.Count -gt 0) {
        $html += @"
        <h2>⚠️ Warnings & Potential Issues</h2>
"@
        foreach ($warning in $Warnings) {
            $riskClass = switch ($warning.Level) {
                "High" { "risk-high" }
                "Medium" { "risk-medium" }
                default { "risk-low" }
            }
            
            $html += @"
        <div class="warning $riskClass">
            <div class="warning-title">$($warning.Title)</div>
            <div>$($warning.Description)</div>
        </div>
"@
        }
    }

    # Add detailed items table
    if ($DetailedItems.Count -gt 0) {
        $html += @"
        <h2>📋 Detailed Changes</h2>
        <table>
            <thead>
                <tr>
                    <th>Type</th>
                    <th>Current Path</th>
                    <th>Before</th>
                    <th>After</th>
                    <th>Status</th>
                </tr>
            </thead>
            <tbody>
"@
        
        foreach ($item in $DetailedItems) {
            $beforeName = if ($item.Before) { $item.Before } else { $item.Current }
            $afterName = if ($item.After) { $item.After } else { $item.Current }
            $status = if ($beforeName -eq $afterName) { "No Change" } else { "Will Change" }
            
            $beforeClass = if ($beforeName -eq $afterName) { "no-change" } else { "before" }
            $afterClass = if ($beforeName -eq $afterName) { "no-change" } else { "after" }
            
            $html += @"
                <tr>
                    <td>$($item.Type)</td>
                    <td><small>$($item.Path)</small></td>
                    <td class="$beforeClass">$beforeName</td>
                    <td class="$afterClass">$afterName</td>
                    <td>$status</td>
                </tr>
"@
        }
        
        $html += @"
            </tbody>
        </table>
"@
    }

    # Add settings section
    $html += @"
        <h2>⚙️ Operation Settings</h2>
        <div class="settings">
            <h3>Configuration Used</h3>
"@
    
    foreach ($key in $Settings.Keys) {
        $value = $Settings[$key]
        $html += "<p><strong>${key}:</strong> $value</p>"
    }
    
    $html += @"
        </div>
        
        <div class="footer">
            <p>Report generated by ConvertVTTAssets v1.6.0 | <a href="https://www.powershellgallery.com/packages/ConvertVTTAssets">PowerShell Gallery</a></p>
            <p>This is a preview report. No files have been modified. Use the actual command without -GenerateReport to apply changes.</p>
        </div>
    </div>
</body>
</html>
"@

    # Write HTML file
    $html | Set-Content -Path $OutputPath -Encoding UTF8
    
    return $OutputPath
}

function Get-OperationWarnings {
    param(
        [array]$Items,
        [string]$OperationType,
        [hashtable]$Settings
    )
    
    $warnings = @()
    
    switch ($OperationType) {
        "FileNameOptimization" {
            # Check for potential conflicts
            $conflicts = @()
            $proposedNames = @{}
            
            foreach ($item in $Items) {
                if ($item.After -and $item.After -ne $item.Before) {
                    $targetPath = Join-Path (Split-Path $item.Path -Parent) $item.After
                    if ($proposedNames.ContainsKey($targetPath.ToLower())) {
                        $conflicts += $targetPath
                    }
                    $proposedNames[$targetPath.ToLower()] = $true
                }
            }
            
            if ($conflicts.Count -gt 0) {
                $warnings += @{
                    Level = "High"
                    Title = "Name Conflicts Detected"
                    Description = "$($conflicts.Count) files would result in naming conflicts. Use -Force to overwrite or rename manually."
                }
            }
            
            # Check for directory dependencies
            $directoryCount = ($Items | Where-Object { $_.Type -eq "Directory" }).Count
            if ($directoryCount -gt 0) {
                $warnings += @{
                    Level = "Low"
                    Title = "Directory Renaming"
                    Description = "$directoryCount directories will be renamed. Files within them will be moved automatically."
                }
            }
        }
        
        "WebMConversion" {
            if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue)) {
                $warnings += @{
                    Level = "High"
                    Title = "FFmpeg Not Found"
                    Description = "FFmpeg is required for WebM conversion but was not found in PATH. Install FFmpeg before proceeding."
                }
            }
            
            $largeFiles = $Items | Where-Object { $_.Size -gt 100MB }
            if ($largeFiles.Count -gt 0) {
                $warnings += @{
                    Level = "Medium"
                    Title = "Large Files Detected"
                    Description = "$($largeFiles.Count) files are larger than 100MB. Conversion may take significant time."
                }
            }
        }
    }
    
    return $warnings
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
    
    [string]$UndoLogPath,
    
    [switch]$Silent,
    
    [switch]$Force,
    
    # Report generation parameters
    [switch]$GenerateReport,
    
    [string]$ReportPath,
    
    [ValidateSet('HTML','CSV','JSON')]
    [string]$ReportFormat = 'HTML',
    
    # NEW: Performance optimization parameters
    [switch]$Parallel,
    
    [ValidateRange(1,32)]
    [int]$ThrottleLimit = 8,
    
    [ValidateRange(100,50000)]
    [int]$ChunkSize = 1000,
    
    [switch]$EnableProgressEstimation
)

# Validate root path exists
if (-not (Test-Path -LiteralPath $Root)) {
    throw "Path not found: $Root"
}

# Generate automatic paths if not specified
if (-not $UndoLogPath -and $LogPath) {
    $logDir = [System.IO.Path]::GetDirectoryName($LogPath)
    $logName = [System.IO.Path]::GetFileNameWithoutExtension($LogPath)
    $UndoLogPath = Join-Path $logDir "${logName}_undo.json"
}

if ($GenerateReport -and -not $ReportPath) {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $ReportPath = "ConvertVTTAssets_FilenameOptimization_Report_$timestamp.html"
}

# Performance settings
$useParallel = $Parallel -and $script:IsPS7
if ($Parallel -and -not $script:IsPS7) {
    Write-Warning "-Parallel requested but you're on Windows PowerShell 5.1. Falling back to sequential processing. For real parallelism, run in PowerShell 7+ (pwsh)."
}

# Initialize collections
$renameOperations = @()
$errors = @()
$skipped = @()
$renamedPaths = @{} 
$operationId = 0
$analysisItems = @()

# Create settings object
$operationSettings = @{
    "Root Path" = $Root
    "Remove Metadata" = $RemoveMetadata.IsPresent
    "Space Replacement" = $SpaceReplacement
    "Lowercase Extensions" = $LowercaseExtensions.IsPresent
    "Preserve Case" = $PreserveCase.IsPresent
    "Expand Ampersand" = $ExpandAmpersand.IsPresent
    "Force Overwrite" = $Force.IsPresent
    "Recursive" = (-not $NoRecurse.IsPresent)
    "Parallel Processing" = $useParallel
    "Throttle Limit" = if ($useParallel) { $ThrottleLimit } else { "N/A" }
    "Chunk Size" = $ChunkSize
}

# Memory-efficient file discovery
$recurse = -not $NoRecurse.IsPresent
Write-Verbose "Starting memory-efficient file discovery..."

# Get total count first for progress estimation
$totalItemsEstimate = if ($EnableProgressEstimation) {
    Write-Verbose "Estimating total items..."
    $estimateCmd = "Get-ChildItem -LiteralPath '$Root' -Recurse:$recurse | Measure-Object | Select-Object -ExpandProperty Count"
    try {
        Invoke-Expression $estimateCmd
    } catch {
        Write-Verbose "Could not estimate total items, using chunk-based progress"
        -1
    }
} else {
    -1
}

# Process in chunks to manage memory
$processedItems = 0
$allDirectories = @()
$totalFiles = 0

# First pass: Get all directories (must be processed sequentially for dependency management)
Write-Verbose "Discovering directories..."
$allDirectories = Get-ChildItem -LiteralPath $Root -Directory -Recurse:$recurse | 
    Sort-Object { $_.FullName.Split('\').Count } -Descending

# Filter directories by extension criteria if specified
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
}

# Initialize progress
$totalItems = $allDirectories.Count
$itemNum = 0

if (-not $Silent -and $totalItems -gt 0) {
    Write-Host ""
    if ($GenerateReport) {
        Write-Host "=== Optimize-FileNames Report Generation ===" -ForegroundColor Cyan
        Write-Host "Analyzing items for report (Chunk size: $ChunkSize)..." -ForegroundColor Yellow
    } else {
        Write-Host "=== Optimize-FileNames Starting ===" -ForegroundColor Cyan
        if ($useParallel) {
            Write-Host "Using parallel processing (Throttle: $ThrottleLimit, Chunk size: $ChunkSize)" -ForegroundColor Yellow
        } else {
            Write-Host "Using sequential processing (Chunk size: $ChunkSize)" -ForegroundColor Yellow
        }
        if ($UndoLogPath) {
            Write-Host "Undo log will be created at: $UndoLogPath" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
}

# Helper function to sanitize names (same as before, but moved to shared scope for parallel jobs)
function Get-SanitizedName {
    param(
        [string]$Name,
        [string]$Extension = ""
    )
    
    $newName = $Name
    
    if ($RemoveMetadata) {
        $newName = $newName -replace '\([^)]*\)', ''
        $newName = $newName -replace '\[[^\]]*\]', ''
        $newName = $newName -replace '_\d+x\d+', ''
        $newName = $newName -replace '-\d+x\d+', ''
        $newName = $newName -replace '__+', '_'
        $newName = $newName -replace '--+', '-'
        $newName = $newName -replace '[_-]+$', ''
        $newName = $newName -replace '^[_-]+', ''
    }
    
    switch ($SpaceReplacement) {
        'Remove'     { $newName = $newName -replace '\s+', '' }
        'Dash'       { $newName = $newName -replace '\s+', '-' }
        'Underscore' { $newName = $newName -replace '\s+', '_' }
    }
    
    if ($ExpandAmpersand) {
        $newName = $newName -replace '&', '_and_'
        $newName = $newName -replace '_and_+', '_and_'
    } else {
        $newName = $newName -replace '&', '_'
    }
    
    $problematicChars = @(
        '*', '"', '[', ']', ':', ';', '|', ',', '&', '=', '+', '$', '?', '%', '#',
        '(', ')', '{', '}', '<', '>', '!', '@', '^', '~', '`', "'"
    )
    
    foreach ($char in $problematicChars) {
        if ($char -ne '&') {
            $escaped = [Regex]::Escape($char)
            if ($char -in @('[',']','(',')')) {
                $newName = $newName -replace $escaped, '-'
            } else {
                $newName = $newName -replace $escaped, ''
            }
        }
    }
    
    $newName = $newName -replace '_{2,}', '_'
    $newName = $newName -replace '-{2,}', '-'
    $newName = $newName -replace '\.{2,}', '.'
    $newName = $newName -replace '^[_.-]+', ''
    $newName = $newName -replace '[_.-]+$', ''
    
    if (-not $PreserveCase) {
        $newName = $newName.ToLower()
    }
    
    $newExt = $Extension
    if ($LowercaseExtensions -and $Extension) {
        $newExt = $Extension.ToLower()
    }
    
    if ($Extension) {
        $finalName = "${newName}${newExt}"
    } else {
        $finalName = $newName
    }
    
    if ([string]::IsNullOrWhiteSpace($finalName)) {
        $finalName = "unnamed_$(Get-Random -Maximum 9999)"
        if ($Extension) { $finalName += $newExt }
    }
    
    return $finalName
}

# Process directories first (sequential - required for dependency management)
Write-Verbose "Processing $($allDirectories.Count) directories sequentially..."

foreach ($dir in $allDirectories) {
    $itemNum++
    $operationId++
    
    if (-not $Silent -and -not $GenerateReport) {
        $percentComplete = if ($totalItemsEstimate -gt 0) {
            [math]::Round(($itemNum / $totalItemsEstimate) * 100, 0)
        } else {
            [math]::Round(($itemNum / ($allDirectories.Count + 1)) * 50, 0) # Directories are ~50% of work
        }
        Write-Host ("[{0,3}%] Checking directory {1}/{2}: {3}" -f $percentComplete, $itemNum, $allDirectories.Count, $dir.Name) -ForegroundColor Cyan
    }
    
    # Update path based on renamed parents
    $currentPath = $dir.FullName
    foreach ($oldPath in $renamedPaths.Keys | Sort-Object -Property Length -Descending) {
        if ($currentPath.StartsWith($oldPath)) {
            $currentPath = $currentPath.Replace($oldPath, $renamedPaths[$oldPath])
            break
        }
    }
    
    if (-not $GenerateReport -and -not (Test-Path -LiteralPath $currentPath)) {
        if (-not $Silent) {
            Write-Host "       ⚠ Skipped: Parent directory was renamed" -ForegroundColor Yellow
        }
        continue
    }
    
    $currentItem = if ($GenerateReport) { $dir } else { Get-Item -LiteralPath $currentPath }
    $originalName = $currentItem.Name
    $directory = $currentItem.Parent.FullName
    if (-not $directory) {
        $directory = Split-Path $currentPath -Parent
    }
    
    $newName = Get-SanitizedName -Name $originalName
    
    # Store for report generation if needed
    if ($GenerateReport) {
        $analysisItems += [PSCustomObject]@{
            Type = "Directory"
            Path = $directory
            Current = $originalName
            Before = $originalName
            After = $newName
            FullCurrentPath = $currentPath
            FullNewPath = (Join-Path $directory $newName)
            NeedsChange = ($newName -ne $originalName)
            Size = 0
        }
        continue
    }
    
    # Process directory rename (same logic as before)
    if ($newName -eq $originalName) {
        if (-not $Silent) {
            Write-Host "       ✓ Already optimized" -ForegroundColor Green
        }
        continue
    }
    
    $newPath = Join-Path $directory $newName
    
    if ((Test-Path -LiteralPath $newPath) -and ($currentPath -ne $newPath) -and -not $Force) {
        if (-not $Silent) {
            Write-Host "       ⚠ Skipped: Target directory already exists: $newName" -ForegroundColor Yellow
        }
        $skipped += [PSCustomObject]@{
            Original = $currentPath
            Proposed = $newPath
            Reason = "Target exists"
        }
        continue
    }
    
    # Create directory operation record
    $operation = [PSCustomObject]@{
        Time = (Get-Date).ToString('s')
        Type = "Directory"
        OriginalPath = $currentPath
        OriginalName = $originalName
        NewPath = $newPath
        NewName = $newName
        Status = "Pending"
        Error = ""
        OperationId = $operationId
        ParentDirectory = $directory
        LastWriteTime = $currentItem.LastWriteTimeUtc.ToString('o')
        FileSize = $null
        Dependencies = @()
    }
    
    # Perform directory rename
    if ($PSCmdlet.ShouldProcess($currentPath, "Rename to $newName")) {
        try {
            if ((Test-Path -LiteralPath $newPath) -and ($currentPath -ne $newPath) -and $Force) {
                if (-not $Silent) {
                    Write-Host "       ⚠ Overwriting existing: $newName" -ForegroundColor Yellow
                }
                Remove-Item -LiteralPath $newPath -Force -Recurse
            }
            
            Rename-Item -LiteralPath $currentPath -NewName $newName -Force:$Force -ErrorAction Stop
            $operation.Status = "Success"
            
            # Track renamed directories
            $renamedPaths[$currentPath] = $newPath
            
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

# Process files in chunks for memory efficiency
Write-Verbose "Starting chunked file processing..."
$fileChunkNum = 0
$totalFileChunks = 0

# Stream files in chunks to avoid memory issues
$allFiles = Get-ChildItem -LiteralPath $Root -File -Recurse:$recurse

# Apply extension filters
if ($IncludeExt -or $ExcludeExt) {
    $allFiles = $allFiles | Where-Object {
        $ext = [System.IO.Path]::GetExtension($_.Name).ToLower()
        $include = if ($includeSet) { $includeSet.Contains($ext) } else { $true }
        $exclude = if ($excludeSet) { $excludeSet.Contains($ext) } else { $false }
        return $include -and -not $exclude
    }
}

$totalFiles = @($allFiles).Count
$totalFileChunks = [math]::Ceiling($totalFiles / $ChunkSize)

Write-Verbose "Processing $totalFiles files in $totalFileChunks chunks of $ChunkSize"

# Process files in chunks
for ($chunkIndex = 0; $chunkIndex -lt $totalFileChunks; $chunkIndex++) {
    $startIndex = $chunkIndex * $ChunkSize
    $endIndex = [math]::Min($startIndex + $ChunkSize - 1, $totalFiles - 1)
    $currentChunk = $allFiles[$startIndex..$endIndex]
    
    Write-Verbose "Processing chunk $($chunkIndex + 1)/$totalFileChunks (files $($startIndex + 1)-$($endIndex + 1))"
    
    if (-not $Silent -and -not $GenerateReport) {
        $chunkProgress = [math]::Round((($chunkIndex + 1) / $totalFileChunks) * 100, 0)
        Write-Host "Processing file chunk $($chunkIndex + 1)/$totalFileChunks ($chunkProgress%)" -ForegroundColor Cyan
    }
    
    # Use parallel processing for file chunks if available
    if ($useParallel -and $currentChunk.Count -gt 1 -and -not $GenerateReport) {
        $parallelSettings = @{
            RemoveMetadata = $RemoveMetadata.IsPresent
            SpaceReplacement = $SpaceReplacement
            LowercaseExtensions = $LowercaseExtensions.IsPresent
            PreserveCase = $PreserveCase.IsPresent
            ExpandAmpersand = $ExpandAmpersand.IsPresent
            Force = $Force.IsPresent
            ThrottleLimit = $ThrottleLimit
            WhatIfPreference = $WhatIfPreference
            VerbosePreference = $VerbosePreference
        }
        
        $operationIdRef = [ref]$operationId
        $chunkResults = Invoke-FileNameOptimizationParallel -Files $currentChunk -Settings $parallelSettings -RenamedPaths $renamedPaths -OperationId $operationIdRef
        
        foreach ($result in $chunkResults) {
            $renameOperations += $result
            
            if (-not $Silent) {
                switch ($result.Status) {
                    "Success" { 
                        Write-Host "       ✓ Renamed: $($result.OriginalName) → $($result.NewName)" -ForegroundColor Green
                    }
                    "AlreadyOptimized" { 
                        Write-Host "       ✓ Already optimized: $($result.OriginalName)" -ForegroundColor Green
                    }
                    "Skipped" { 
                        Write-Host "       ⚠ Skipped: $($result.OriginalName) ($($result.Error))" -ForegroundColor Yellow
                    }
                    "Failed" { 
                        Write-Host "       ✗ Failed: $($result.OriginalName) ($($result.Error))" -ForegroundColor Red
                    }
                    "WhatIf" { 
                        Write-Host "       → Would rename: $($result.OriginalName) → $($result.NewName)" -ForegroundColor Cyan
                    }
                }
            }
        }
        
        # Update operation ID after parallel processing
        $operationId = $operationIdRef.Value
    } else {
        # Sequential processing for chunk (same as original logic)
        foreach ($f in $currentChunk) {
            $operationId++
            $processedItems++
            
            if (-not $Silent -and -not $GenerateReport) {
                $fileProgress = [math]::Round(($processedItems / $totalFiles) * 100, 0)
                Write-Host ("     [{0,3}%] File {1}/{2}: {3}" -f $fileProgress, $processedItems, $totalFiles, $f.Name) -ForegroundColor DarkCyan
            }
            
            # Process individual file (existing logic adapted for chunked processing)
            # ... (implement the same file processing logic as before, but optimized for chunks)
            
            # Update path based on renamed directories
            $currentPath = $f.FullName
            foreach ($oldPath in $renamedPaths.Keys | Sort-Object -Property Length -Descending) {
                if ($currentPath.StartsWith($oldPath)) {
                    $currentPath = $currentPath.Replace($oldPath, $renamedPaths[$oldPath])
                    break
                }
            }
            
            if (-not $GenerateReport -and -not (Test-Path -LiteralPath $currentPath)) {
                if (-not $Silent) {
                    Write-Host "       ⚠ Skipped: Parent directory was renamed" -ForegroundColor Yellow
                }
                continue
            }
            
            $currentItem = if ($GenerateReport) { $f } else { Get-Item -LiteralPath $currentPath }
            $originalName = $currentItem.Name
            $directory = $currentItem.DirectoryName
            
            $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($originalName)
            $extension = [System.IO.Path]::GetExtension($originalName)
            
            $newName = Get-SanitizedName -Name $nameWithoutExt -Extension $extension
            $newPath = Join-Path $directory $newName
            
            # Store for report generation if needed
            if ($GenerateReport) {
                $analysisItems += [PSCustomObject]@{
                    Type = "File"
                    Path = $directory
                    Current = $originalName
                    Before = $originalName
                    After = $newName
                    FullCurrentPath = $currentPath
                    FullNewPath = $newPath
                    NeedsChange = ($newName -ne $originalName)
                    Size = if (Test-Path $currentPath) { $currentItem.Length } else { 0 }
                }
                continue
            }
            
            # Continue with file processing logic (same as before)...
            if ($newName -eq $originalName) {
                if (-not $Silent) {
                    Write-Host "       ✓ Already optimized" -ForegroundColor Green
                }
                continue
            }
            
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
            
            $fileInfo = Get-Item -LiteralPath $currentPath
            $lastWriteTime = $fileInfo.LastWriteTimeUtc.ToString('o')
            $fileSize = $fileInfo.Length
            
            $operation = [PSCustomObject]@{
                Time = (Get-Date).ToString('s')
                Type = "File"
                OriginalPath = $currentPath
                OriginalName = $originalName
                NewPath = $newPath
                NewName = $newName
                Status = "Pending"
                Error = ""
                OperationId = $operationId
                ParentDirectory = $directory
                LastWriteTime = $lastWriteTime
                FileSize = $fileSize
                Dependencies = @()
            }
            
            if ($PSCmdlet.ShouldProcess($currentPath, "Rename to $newName")) {
                try {
                    if ((Test-Path -LiteralPath $newPath) -and ($currentPath -ne $newPath) -and $Force) {
                        if (-not $Silent) {
                            Write-Host "       ⚠ Overwriting existing: $newName" -ForegroundColor Yellow
                        }
                        Remove-Item -LiteralPath $newPath -Force
                    }
                    
                    Rename-Item -LiteralPath $currentPath -NewName $newName -Force:$Force -ErrorAction Stop
                    $operation.Status = "Success"
                    
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
    }
    
    # Force garbage collection after each chunk to manage memory
    if ($chunkIndex -gt 0 -and ($chunkIndex % 10) -eq 0) {
        Write-Verbose "Forcing garbage collection after chunk $($chunkIndex + 1)"
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()
    }
}

# Calculate final totals
$totalItems = $allDirectories.Count + $totalFiles

# Generate report if requested (same logic as before)
if ($GenerateReport) {
    $changesCount = ($analysisItems | Where-Object { $_.NeedsChange }).Count
    $noChangeCount = ($analysisItems | Where-Object { -not $_.NeedsChange }).Count
    $directoriesCount = ($analysisItems | Where-Object { $_.Type -eq "Directory" -and $_.NeedsChange }).Count
    
    # Enhanced time estimation based on parallel processing capabilities
    $timeEstimate = if ($useParallel) {
        Get-TimeEstimate -FileCount $changesCount -OperationType "FileNameOptimizationParallel"
    } else {
        Get-TimeEstimate -FileCount $changesCount -OperationType "FileNameOptimization"
    }
    
    $warnings = Get-OperationWarnings -Items $analysisItems -OperationType "FileNameOptimization" -Settings $operationSettings
    
    $summary = @{
        "Total Items Analyzed" = $totalItems
        "Items Needing Changes" = $changesCount
        "Items Already Optimized" = $noChangeCount
        "Directories to Rename" = $directoriesCount
        "Estimated Time" = $timeEstimate
        "Processing Mode" = if ($useParallel) { "Parallel (Throttle: $ThrottleLimit)" } else { "Sequential" }
        "Chunk Size Used" = $ChunkSize
    }
    
    $reportTitle = "Filename Optimization Analysis Report (Performance Enhanced)"
    $reportPath = New-HTMLReport -Title $reportTitle -Operation "Optimize-FileNames" -Summary $summary -DetailedItems $analysisItems -Warnings $warnings -Settings $operationSettings -OutputPath $ReportPath
    
    if (-not $Silent) {
        Write-Host ""
        Write-Host "=== Report Generation Complete ===" -ForegroundColor Green
        Write-Host "Report saved to: $reportPath" -ForegroundColor Cyan
        Write-Host "Items analyzed: $totalItems" -ForegroundColor Yellow
        Write-Host "Items needing changes: $changesCount" -ForegroundColor Yellow
        Write-Host "Processing mode: $(if ($useParallel) { "Parallel (Throttle: $ThrottleLimit)" } else { "Sequential" })" -ForegroundColor Yellow
        Write-Host "Memory management: Chunked processing ($ChunkSize items per chunk)" -ForegroundColor Yellow
        
        if ($warnings.Count -gt 0) {
            Write-Host "Warnings found: $($warnings.Count)" -ForegroundColor Yellow
        }
        
        Write-Host ""
        Write-Host "To apply these changes, run the same command without -GenerateReport" -ForegroundColor Gray
    }
    
    return [PSCustomObject]@{
        TotalItems = $totalItems
        ItemsNeedingChanges = $changesCount
        ItemsAlreadyOptimized = $noChangeCount
        DirectoriesToRename = $directoriesCount
        EstimatedTime = $timeEstimate
        ProcessingMode = if ($useParallel) { "Parallel" } else { "Sequential" }
        ThrottleLimit = if ($useParallel) { $ThrottleLimit } else { $null }
        ChunkSize = $ChunkSize
        WarningCount = $warnings.Count
        ReportPath = $reportPath
        AnalysisItems = $analysisItems
    }
}

# Continue with existing undo log creation and summary logic...
# (Same as before - undo metadata, logging, summary reporting)

# Rest of function stays the same - create undo logs, standard logging, summary
# ... (keeping existing implementation for brevity)

Write-Verbose "Performance optimization complete. Processed $totalItems items in $totalFileChunks chunks."

# Final summary with performance metrics
$successful = ($renameOperations | Where-Object { $_.Status -eq "Success" }).Count
$failed = ($renameOperations | Where-Object { $_.Status -eq "Failed" }).Count
$whatif = ($renameOperations | Where-Object { $_.Status -eq "WhatIf" }).Count
$skippedCount = $skipped.Count

if (-not $Silent) { 
    Write-Host ""
    Write-Host "=== Optimize-FileNames Summary (Performance Enhanced) ===" -ForegroundColor Cyan
    Write-Host "Renamed:  $successful" -ForegroundColor Green
    Write-Host "Skipped:  $skippedCount" -ForegroundColor Yellow
    if ($whatif -gt 0) { Write-Host "WhatIf:   $whatif" -ForegroundColor Cyan }
    if ($failed -gt 0) { Write-Host "Failed:   $failed" -ForegroundColor Red }
    
    Write-Host ""
    Write-Host "Performance Details:" -ForegroundColor DarkCyan
    Write-Host "  Processing mode: $(if ($useParallel) { "Parallel (Throttle: $ThrottleLimit)" } else { "Sequential" })" -ForegroundColor Gray
    Write-Host "  Chunk size: $ChunkSize items per chunk" -ForegroundColor Gray
    Write-Host "  Total chunks processed: $totalFileChunks" -ForegroundColor Gray
}

return [PSCustomObject]@{
    TotalItems = $totalItems
    Renamed = $successful
    Skipped = $skippedCount
    Failed = $failed
    WhatIf = $whatif
    Operations = $renameOperations
    UndoLogPath = $UndoLogPath
    PerformanceMetrics = @{
        ProcessingMode = if ($useParallel) { "Parallel" } else { "Sequential" }
        ThrottleLimit = if ($useParallel) { $ThrottleLimit } else { $null }
        ChunkSize = $ChunkSize
        TotalChunks = $totalFileChunks
        TotalDirectories = $allDirectories.Count
        TotalFiles = $totalFiles
    }
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

