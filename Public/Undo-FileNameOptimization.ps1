<#
.SYNOPSIS
    Undo-FileNameOptimization - Complete rollback of filename optimization operations
.DESCRIPTION
    Provides comprehensive undo capability for filename optimization operations with validation,
    dependency tracking, and conflict resolution. Supports complete restoration of original
    filenames and directory structures with integrity checking and error handling.
.PARAMETER UndoLogPath
    Path to the undo log JSON file created during filename optimization (Required)
.PARAMETER BackupUndoLogPath
    Create backup copy of undo log before processing (optional safety measure)
.PARAMETER Force
    Overwrite existing files when conflicts occur during undo operations
.PARAMETER Silent
    Suppress progress output and display minimal information
.PARAMETER WhatIf
    Preview undo operations without making any changes
.EXAMPLE
    Undo-FileNameOptimization -UndoLogPath "D:\Logs\undo.json"
    Restore all files and directories to original names using undo log
.EXAMPLE
    Undo-FileNameOptimization -UndoLogPath "D:\Logs\undo.json" -Force -BackupUndoLogPath "D:\Backups\undo_backup.json"
    Force restoration with conflict resolution and create backup of undo log
.EXAMPLE
    Undo-FileNameOptimization -UndoLogPath "D:\Logs\undo.json" -WhatIf
    Preview undo operations without making any changes
.NOTES
    Author: Andres Yuhnke, Claude (Anthropic)
    Version: 1.6.0
    
    Requirements:
    - Valid undo log JSON file created by Optimize-FileNames function
    - Files and directories must still exist at their optimized locations
    - Sufficient permissions to rename/move files and directories
    
    Safety Features:
    - Two-phase validation system (integrity + conflict detection)
    - Dependency tracking for proper restoration order
    - Complete backup and rollback capabilities
    - Comprehensive error handling and reporting
    
    Limitations:
    - Only works with undo logs from Optimize-FileNames operations
    - Cannot undo operations where OutputRoot was used (copy operations)
    - Files must not have been moved/deleted since optimization
.LINK
    https://github.com/andresyuhnke/ConvertVTTAssets
.LINK
    https://www.powershellgallery.com/packages/ConvertVTTAssets
#>

function Undo-FileNameOptimization {
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory=$true)]
    [string]$UndoLogPath,
    
    [switch]$Force,
    
    [switch]$Silent,
    
    [string]$BackupUndoLogPath  # Create backup of undo log before processing
)

# [UNDO-001] Validate undo log file exists and is accessible
if (-not (Test-Path -LiteralPath $UndoLogPath)) {
    throw "Undo log not found: $UndoLogPath"
}

# [UNDO-001.1] Read and parse undo log with comprehensive error handling
try {
    $undoLogContent = Get-Content -LiteralPath $UndoLogPath -Raw -Encoding UTF8
    $undoLog = $undoLogContent | ConvertFrom-Json
} catch {
    throw "Failed to read or parse undo log: $($_.Exception.Message)"
}

# [UNDO-001.2] Validate undo log structure and content
if (-not $undoLog.metadata -or -not $undoLog.operations) {
    throw "Invalid undo log format. Missing required 'metadata' or 'operations' sections."
}

if (-not $undoLog.operations -or $undoLog.operations.Count -eq 0) {
    Write-Warning "Undo log contains no operations to reverse."
    return
}

# [UNDO-002] Create backup of undo log if requested
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

# [UNDO-003] Initialize processing collections and statistics
$undoOperations = @()
$errors = @()
$warnings = @()
$skipped = @()

# [UNDO-003.1] Get operations and sort for proper undo order
$operations = $undoLog.operations

# [UNDO-003.2] Sort operations for safe restoration order
# Files first, then directories by dependency depth (deepest first)
$fileOps = $operations | Where-Object { $_.type -eq "File" }
$dirOps = $operations | Where-Object { $_.type -eq "Directory" }

# Sort directories by dependency count (most dependencies = deepest = undo last)
$sortedDirOps = $dirOps | Sort-Object { $_.dependencies.Count } -Descending

# [UNDO-003.3] Combine operations in proper order: files first, then directories
$sortedOperations = @($fileOps) + @($sortedDirOps)

# [UNDO-004] Initialize progress tracking and user feedback
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

# [UNDO-005] Validation pass - check current state before making changes
if (-not $Silent) {
    Write-Host "Validating current state..." -ForegroundColor Yellow
}

$validationErrors = @()
$currentPathMap = @{}  # Track current state

foreach ($op in $sortedOperations) {
    $opNum++
    
    # [UNDO-005.1] Display validation progress
    if (-not $Silent) {
        $percentComplete = [math]::Round(($opNum / $totalOps) * 50, 0)  # Validation is first 50%
        Write-Host ("[{0,3}%] Validating {1}/{2}: {3}" -f $percentComplete, $opNum, $totalOps, $op.new_name) -ForegroundColor Cyan
    }
    
    # [UNDO-005.2] Check if the "new" file/directory still exists at expected location
    if (-not (Test-Path -LiteralPath $op.new_path)) {
        $validationErrors += "Missing renamed item: $($op.new_path)"
        continue
    }
    
    # [UNDO-005.3] Get current item information for validation
    $currentItem = Get-Item -LiteralPath $op.new_path
    
    # [UNDO-005.4] For files, validate they haven't been significantly modified
    if ($op.type -eq "File" -and $op.file_size -ne $null) {
        if ($currentItem.Length -ne $op.file_size) {
            $validationErrors += "File size changed: $($op.new_path) (was $($op.file_size), now $($currentItem.Length))"
        }
        
        # [UNDO-005.5] Check if last write time is significantly different
        # Allow for small clock differences (file system precision)
        $originalTime = [DateTime]::Parse($op.last_write_time)
        $timeDiff = [Math]::Abs(($currentItem.LastWriteTimeUtc - $originalTime).TotalSeconds)
        if ($timeDiff -gt 2) {  # Allow 2 second difference for file system precision
            $warnings += "File modified since optimization: $($op.new_path)"
        }
    }
    
    # [UNDO-005.6] Check if original name would cause conflicts
    if ((Test-Path -LiteralPath $op.original_path) -and -not $Force) {
        $validationErrors += "Original name already exists: $($op.original_path) (use -Force to overwrite)"
    }
    
    # [UNDO-005.7] Track current state for dependency validation
    $currentPathMap[$op.new_path] = $op
}

# [UNDO-006] Report validation results and handle errors
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

# [UNDO-006.1] Display validation warnings if present
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

# [UNDO-007] Reset progress counter for undo operations phase
$opNum = 0

# [UNDO-007.1] Perform actual undo operations with comprehensive error handling
foreach ($op in $sortedOperations) {
    $opNum++
    
    # [UNDO-007.2] Display undo operation progress
    if (-not $Silent) {
        $percentComplete = [math]::Round(50 + ($opNum / $totalOps) * 50, 0)  # Undo is second 50%
        Write-Host ("[{0,3}%] Undoing {1}/{2}: {3} → {4}" -f $percentComplete, $opNum, $totalOps, $op.new_name, $op.original_name) -ForegroundColor Cyan
    }
    
    # [UNDO-007.3] Create undo operation record for tracking
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
        # [UNDO-007.4] Check if current path still exists
        if (-not (Test-Path -LiteralPath $op.new_path)) {
            $undoResult.Status = "Skipped"
            $undoResult.Error = "Source no longer exists"
            $skipped += $undoResult
            
            if (-not $Silent) {
                Write-Host "       ⚠ Skipped: Source no longer exists" -ForegroundColor Yellow
            }
            continue
        }
        
        # [UNDO-007.5] Handle target path conflicts with force resolution
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
        
        # [UNDO-007.6] Perform the actual undo rename operation
        if ($PSCmdlet.ShouldProcess($op.new_path, "Undo rename to $($op.original_name)")) {
            # [UNDO-007.7] Ensure target directory exists
            $targetDir = [System.IO.Path]::GetDirectoryName($op.original_path)
            
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
            }
            
            # [UNDO-007.8] Execute the rename operation
            Rename-Item -LiteralPath $op.new_path -NewName $op.original_name -Force:$Force -ErrorAction Stop
            
            $undoResult.Status = "Success"
            
            if (-not $Silent) {
                Write-Host "       ✓ Restored: $($op.new_name) → $($op.original_name)" -ForegroundColor Green
            }
        } else {
            # [UNDO-007.9] Handle WhatIf preview mode
            $undoResult.Status = "WhatIf"
            if (-not $Silent) {
                Write-Host "       → Would restore: $($op.new_name) → $($op.original_name)" -ForegroundColor Cyan
            }
        }
        
    } catch {
        # [UNDO-007.10] Handle operation failures with detailed error tracking
        $undoResult.Status = "Failed"
        $undoResult.Error = $_.Exception.Message
        $errors += $undoResult
        
        if (-not $Silent) {
            Write-Host "       ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    $undoOperations += $undoResult
}

# [UNDO-008] Generate comprehensive operation summary and statistics
$successful = ($undoOperations | Where-Object { $_.Status -eq "Success" }).Count
$failed = ($undoOperations | Where-Object { $_.Status -eq "Failed" }).Count
$whatif = ($undoOperations | Where-Object { $_.Status -eq "WhatIf" }).Count
$skippedCount = ($undoOperations | Where-Object { $_.Status -eq "Skipped" }).Count

# [UNDO-008.1] Display comprehensive summary with statistics
if (-not $Silent) { Write-Host "" }
Write-Host "=== Undo-FileNameOptimization Summary ===" -ForegroundColor Cyan
Write-Host "Restored: $successful" -ForegroundColor Green
Write-Host "Skipped:  $skippedCount" -ForegroundColor Yellow
if ($whatif -gt 0) { Write-Host "WhatIf:   $whatif" -ForegroundColor Cyan }
if ($failed -gt 0) { Write-Host "Failed:   $failed" -ForegroundColor Red }

# [UNDO-008.2] Display detailed error information if failures occurred
if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "Errors encountered:" -ForegroundColor Red
    foreach ($err in $errors) {
        Write-Host "  - Operation $($err.OperationId): $($err.Error)" -ForegroundColor Red
    }
}

# [UNDO-009] Create comprehensive undo operation log for audit trails
$undoLogDir = [System.IO.Path]::GetDirectoryName($UndoLogPath)
$undoLogName = [System.IO.Path]::GetFileNameWithoutExtension($UndoLogPath)
$undoOpLogPath = Join-Path $undoLogDir "${undoLogName}_undo_operations.json"

# [UNDO-009.1] Assemble complete undo operation log with metadata
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

# [UNDO-009.2] Write comprehensive undo operation log to file
$undoOpLog | ConvertTo-Json -Depth 10 | Set-Content -Path $undoOpLogPath -Encoding UTF8

if (-not $Silent) {
    Write-Host ""
    Write-Host "Undo operations logged to: $undoOpLogPath" -ForegroundColor Green
}

# [UNDO-010] Return comprehensive results object with all metrics
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