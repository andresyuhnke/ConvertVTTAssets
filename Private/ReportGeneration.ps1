<#
.SYNOPSIS
    ConvertVTTAssets ReportGeneration - Professional HTML reporting system for asset optimization
.DESCRIPTION
    Private module containing functions for generating comprehensive HTML reports with risk assessment,
    time estimates, file size projections, and detailed change previews. Creates professional reports
    suitable for stakeholder sharing and audit trails before executing optimization operations.
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
    - Get-TimeEstimate: Smart operation duration prediction based on file count and type
    - Get-FileSizeProjection: File size reduction estimates with compression ratios
    - New-HTMLReport: Complete HTML report generation with modern responsive design
    - Get-OperationWarnings: Risk assessment and validation warnings system
    
    Report features:
    - Interactive summary dashboard with key metrics
    - Before/after comparison tables with visual indicators
    - Color-coded risk assessment (High/Medium/Low)
    - Professional styling suitable for business presentations
#>

# [RPT-001] Time estimation algorithm - Predicts operation duration based on file characteristics
function Get-TimeEstimate {
    param(
        [int]$FileCount,
        [long]$TotalSize,
        [string]$OperationType = "FileNameOptimization"
    )
    
    # [RPT-001.1] Base processing times per operation type (in seconds per file)
    # These estimates are based on empirical testing across different hardware configurations
    $baseTimePerFile = switch ($OperationType) {
        "FileNameOptimization" { 0.1 }    # Very fast - just file system operations
        "WebMConversion" { 15.0 }          # Depends heavily on file size and complexity
        "WebPConversion" { 3.0 }           # Faster than WebM due to simpler processing
        default { 1.0 }                    # Conservative default for unknown operations
    }
    
    # [RPT-001.2] Size-based time adjustments for media conversions
    # Larger files take disproportionately longer due to encoding complexity
    if ($OperationType -in @("WebMConversion", "WebPConversion") -and $TotalSize -gt 0) {
        $avgFileSizeMB = ($TotalSize / $FileCount) / 1MB
        if ($avgFileSizeMB -gt 10) { $baseTimePerFile *= 2 }      # 10MB+ files take twice as long
        elseif ($avgFileSizeMB -gt 50) { $baseTimePerFile *= 4 }  # 50MB+ files are significantly slower
    }
    
    # [RPT-001.3] Calculate total estimated time
    $totalSeconds = $FileCount * $baseTimePerFile
    
    # [RPT-001.4] Format into human-readable time units
    if ($totalSeconds -lt 60) {
        return "$([math]::Round($totalSeconds, 1)) seconds"
    } elseif ($totalSeconds -lt 3600) {
        return "$([math]::Round($totalSeconds / 60, 1)) minutes" 
    } else {
        return "$([math]::Round($totalSeconds / 3600, 1)) hours"
    }
}

# [RPT-002] File size projection calculator - Estimates storage impact of conversions
function Get-FileSizeProjection {
    param(
        [System.IO.FileInfo[]]$Files,
        [string]$ConversionType,
        [hashtable]$Settings = @{}
    )
    
    # [RPT-002.1] Calculate current total file size
    $totalCurrentSize = ($Files | Measure-Object -Property Length -Sum).Sum
    
    # [RPT-002.2] Apply compression ratio estimates based on empirical testing
    # These ratios reflect typical results across diverse asset libraries
    $compressionRatio = switch ($ConversionType) {
        "WebM" { 0.35 }      # ~65% reduction (aggressive video compression)
        "WebP" { 
            if ($Settings.Lossless) { 0.8 } else { 0.25 }  # Lossless preserves more, lossy compresses heavily
        }
        default { 1.0 }      # No size change for filename-only operations
    }
    
    # [RPT-002.3] Calculate projected sizes and savings
    $projectedSize = [long]($totalCurrentSize * $compressionRatio)
    $savings = $totalCurrentSize - $projectedSize
    $savingsPercent = if ($totalCurrentSize -gt 0) { 
        [math]::Round((1 - $compressionRatio) * 100, 1) 
    } else { 0 }
    
    # [RPT-002.4] Return structured projection data with formatted values
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

# [RPT-003] HTML report generator - Creates comprehensive professional reports
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
    
    # [RPT-003.1] Generate complete HTML document with modern responsive design
    # Uses CSS Grid and Flexbox for responsive layout, professional color scheme
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

    # [RPT-003.2] Generate summary cards for key metrics
    # Each card displays a major statistic with visual emphasis
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

    # [RPT-003.3] Add warnings section with color-coded risk levels
    if ($Warnings.Count -gt 0) {
        $html += @"
        <h2>⚠️ Warnings & Potential Issues</h2>
"@
        foreach ($warning in $Warnings) {
            # [RPT-003.4] Apply risk-based CSS classes for visual distinction
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

    # [RPT-003.5] Generate detailed changes table with before/after comparison
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
        
        # [RPT-003.6] Process each item with appropriate styling for change status
        foreach ($item in $DetailedItems) {
            $beforeName = if ($item.Before) { $item.Before } else { $item.Current }
            $afterName = if ($item.After) { $item.After } else { $item.Current }
            $status = if ($beforeName -eq $afterName) { "No Change" } else { "Will Change" }
            
            # [RPT-003.7] Apply CSS classes based on change status for visual clarity
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

    # [RPT-003.8] Add comprehensive settings documentation section
    $html += @"
        <h2>⚙️ Operation Settings</h2>
        <div class="settings">
            <h3>Configuration Used</h3>
"@
    
    # [RPT-003.9] Display all operation settings for audit trail purposes
    foreach ($key in $Settings.Keys) {
        $value = $Settings[$key]
        $html += "<p><strong>${key}:</strong> $value</p>"
    }
    
    # [RPT-003.10] Add footer with module information and usage instructions
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

    # [RPT-003.11] Write complete HTML report to specified file path
    $html | Set-Content -Path $OutputPath -Encoding UTF8
    
    return $OutputPath
}

# [RPT-004] Operation risk assessment - Identifies potential issues and conflicts
function Get-OperationWarnings {
    param(
        [array]$Items,
        [string]$OperationType,
        [hashtable]$Settings
    )
    
    $warnings = @()
    
    # [RPT-004.1] Filename optimization specific warnings
    switch ($OperationType) {
        "FileNameOptimization" {
            # [RPT-004.2] Check for potential naming conflicts
            $conflicts = @()
            $proposedNames = @{}
            
            # [RPT-004.3] Build conflict detection map using case-insensitive comparison
            foreach ($item in $Items) {
                if ($item.After -and $item.After -ne $item.Before) {
                    $targetPath = Join-Path (Split-Path $item.Path -Parent) $item.After
                    if ($proposedNames.ContainsKey($targetPath.ToLower())) {
                        $conflicts += $targetPath
                    }
                    $proposedNames[$targetPath.ToLower()] = $true
                }
            }
            
            # [RPT-004.4] Generate high-priority warning for naming conflicts
            if ($conflicts.Count -gt 0) {
                $warnings += @{
                    Level = "High"
                    Title = "Name Conflicts Detected"
                    Description = "$($conflicts.Count) files would result in naming conflicts. Use -Force to overwrite or rename manually."
                }
            }
            
            # [RPT-004.5] Directory dependency warning for complex operations
            $directoryCount = ($Items | Where-Object { $_.Type -eq "Directory" }).Count
            if ($directoryCount -gt 0) {
                $warnings += @{
                    Level = "Low"
                    Title = "Directory Renaming"
                    Description = "$directoryCount directories will be renamed. Files within them will be moved automatically."
                }
            }
        }
        
        # [RPT-004.6] Media conversion specific warnings
        "WebMConversion" {
            # [RPT-004.7] Check for FFmpeg availability
            if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue)) {
                $warnings += @{
                    Level = "High"
                    Title = "FFmpeg Not Found"
                    Description = "FFmpeg is required for WebM conversion but was not found in PATH. Install FFmpeg before proceeding."
                }
            }
            
            # [RPT-004.8] Large file processing time warning
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