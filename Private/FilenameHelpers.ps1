<#
.SYNOPSIS
    ConvertVTTAssets FilenameHelpers - Core filename sanitization and validation functions
.DESCRIPTION
    Private module containing specialized functions for filename and directory name sanitization,
    conflict detection, and extension filtering. Provides the core logic for web-safe filename
    generation with comprehensive character handling and validation capabilities.
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
    - Get-SanitizedName: Core filename sanitization with character replacement
    - Test-FilenameConflicts: Conflict detection and resolution strategies
    - Get-ExtensionFilters: Include/exclude extension filtering logic
    
    Features comprehensive handling of:
    - Problematic web server characters
    - Metadata removal patterns
    - Space replacement strategies  
    - Ampersand expansion options
    - Case conversion preferences
#>

# [FNAME-001] Core filename sanitization function with comprehensive character handling
function Get-SanitizedName {
    param(
        [string]$Name,
        [string]$Extension = "",
        [hashtable]$Settings
    )
    
    $newName = $Name
    
    # [FNAME-001.1] Remove metadata patterns if requested
    if ($Settings.RemoveMetadata) {
        $newName = $newName -replace '\([^)]*\)', ''      # Remove (content)
        $newName = $newName -replace '\[[^\]]*\]', ''     # Remove [content]  
        $newName = $newName -replace '_\d+x\d+', ''       # Remove _1920x1080 patterns
        $newName = $newName -replace '-\d+x\d+', ''       # Remove -1920x1080 patterns
        $newName = $newName -replace '__+', '_'           # Collapse multiple underscores
        $newName = $newName -replace '--+', '-'           # Collapse multiple dashes
        $newName = $newName -replace '[_-]+$', ''         # Remove trailing separators
        $newName = $newName -replace '^[_-]+', ''         # Remove leading separators
    }
    
    # [FNAME-001.2] Handle space replacement according to user preference
    switch ($Settings.SpaceReplacement) {
        'Remove'     { $newName = $newName -replace '\s+', '' }
        'Dash'       { $newName = $newName -replace '\s+', '-' }
        'Underscore' { $newName = $newName -replace '\s+', '_' }
    }
    
    # [FNAME-001.3] Handle ampersand replacement with smart expansion
    if ($Settings.ExpandAmpersand) {
        $newName = $newName -replace '&', '_and_'
        $newName = $newName -replace '_and_+', '_and_'    # Prevent multiple 'and' sequences
    } else {
        $newName = $newName -replace '&', '_'
    }
    
    # [FNAME-001.4] Remove problematic characters for web server compatibility
    $problematicChars = @(
        '*', '"', ':', ';', '|', ',', '=', '+', '$', '?', '%', '#',
        '(', ')', '{', '}', '<', '>', '!', '@', '^', '~', '`', "'"
    )
    
    # [FNAME-001.5] Process each problematic character with appropriate replacement
    foreach ($char in $problematicChars) {
        $escaped = [Regex]::Escape($char)
        if ($char -in @('(', ')')) {
            $newName = $newName -replace $escaped, '-'  # Convert parentheses to dashes
        } else {
            $newName = $newName -replace $escaped, ''   # Remove other problematic chars
        }
    }
    
    # [FNAME-001.6] Handle square brackets separately (they need special escaping)
    $newName = $newName -replace '\[', '-'              # Convert [ to -
    $newName = $newName -replace '\]', '-'              # Convert ] to -
    
    # [FNAME-001.7] Clean up any duplicate separators and edge cases
    $newName = $newName -replace '_{2,}', '_'           # Collapse multiple underscores
    $newName = $newName -replace '-{2,}', '-'           # Collapse multiple dashes
    $newName = $newName -replace '\.{2,}', '.'          # Collapse multiple dots
    $newName = $newName -replace '^[_.-]+', ''          # Remove leading separators
    $newName = $newName -replace '[_.-]+$', ''          # Remove trailing separators
    
    # [FNAME-001.8] Apply case conversion based on user preference
    if (-not $Settings.PreserveCase) {
        $newName = $newName.ToLower()
    }
    
    # [FNAME-001.9] Handle extension case conversion
    $newExt = $Extension
    if ($Settings.LowercaseExtensions -and $Extension) {
        $newExt = $Extension.ToLower()
    }
    
    # [FNAME-001.10] Construct final filename and handle empty results
    if ($Extension) {
        $finalName = "${newName}${newExt}"
    } else {
        $finalName = $newName
    }
    
    # [FNAME-001.11] Provide fallback for completely sanitized names
    if ([string]::IsNullOrWhiteSpace($finalName)) {
        $finalName = "unnamed_$(Get-Random -Maximum 9999)"
        if ($Extension) { $finalName += $newExt }
    }
    
    return $finalName
}

# [FNAME-002] Conflict detection and validation for rename operations
function Test-FilenameConflicts {
    param(
        [array]$ProposedItems,
        [hashtable]$Settings
    )
    
    $conflicts = @()
    $proposedNames = @{}
    
    # [FNAME-002.1] Build conflict detection map using case-insensitive comparison
    foreach ($item in $ProposedItems) {
        if ($item.NewName -and $item.NewName -ne $item.OriginalName) {
            $targetPath = Join-Path $item.Directory $item.NewName
            $keyPath = $targetPath.ToLower()
            
            # [FNAME-002.2] Check for duplicate target names
            if ($proposedNames.ContainsKey($keyPath)) {
                $conflicts += @{
                    Type = "Duplicate"
                    Path = $targetPath
                    Items = @($proposedNames[$keyPath], $item)
                    Message = "Multiple items would be renamed to: $($item.NewName)"
                }
            } else {
                $proposedNames[$keyPath] = $item
            }
            
            # [FNAME-002.3] Check if target already exists on disk
            if ((Test-Path -LiteralPath $targetPath) -and -not $Settings.Force) {
                $conflicts += @{
                    Type = "Existing"
                    Path = $targetPath
                    Items = @($item)
                    Message = "Target already exists: $($item.NewName)"
                }
            }
        }
    }
    
    return $conflicts
}

# [FNAME-003] Extension filtering logic for include/exclude patterns
function Get-ExtensionFilters {
    param(
        [string[]]$IncludeExt,
        [string[]]$ExcludeExt
    )
    
    # [FNAME-003.1] Build include filter set if specified
    $includeSet = if ($IncludeExt) { 
        [System.Collections.Generic.HashSet[string]]::new([string[]]($IncludeExt | ForEach-Object { $_.ToLower() }))
    } else { 
        $null 
    }
    
    # [FNAME-003.2] Build exclude filter set if specified  
    $excludeSet = if ($ExcludeExt) { 
        [System.Collections.Generic.HashSet[string]]::new([string[]]($ExcludeExt | ForEach-Object { $_.ToLower() }))
    } else { 
        $null 
    }
    
    # [FNAME-003.3] Return filter function for easy application
    return {
        param($FileItem)
        $ext = [System.IO.Path]::GetExtension($FileItem.Name).ToLower()
        $include = if ($includeSet) { $includeSet.Contains($ext) } else { $true }
        $exclude = if ($excludeSet) { $excludeSet.Contains($ext) } else { $false }
        return $include -and -not $exclude
    }
}

# [FNAME-004] Validation helper for problematic filename patterns
function Test-ProblematicPatterns {
    param(
        [string]$Filename,
        [hashtable]$Settings
    )
    
    $issues = @()
    
    # [FNAME-004.1] Check for Windows reserved names
    $reservedNames = @('CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')
    $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($Filename)
    
    if ($reservedNames -contains $nameWithoutExt.ToUpper()) {
        $issues += "Reserved Windows filename: $nameWithoutExt"
    }
    
    # [FNAME-004.2] Check for extremely long filenames (Windows 260 char limit)
    if ($Filename.Length -gt 240) {  # Leave some buffer for path length
        $issues += "Filename too long: $($Filename.Length) characters (limit ~240)"
    }
    
    # [FNAME-004.3] Check for problematic ending characters
    if ($Filename -match '\.$') {
        $issues += "Filename ends with period"
    }
    
    if ($Filename -match '\s$') {
        $issues += "Filename ends with space"
    }
    
    return $issues
}

# [FNAME-005] Generate filename statistics for reporting
function Get-FilenameStatistics {
    param(
        [array]$Items,
        [hashtable]$Settings
    )
    
    $stats = @{
        TotalItems = $Items.Count
        ItemsNeedingChanges = 0
        ItemsAlreadyOptimized = 0
        DirectoryCount = 0
        FileCount = 0
        ProblematicPatterns = 0
        ConflictCount = 0
    }
    
    # [FNAME-005.1] Analyze each item for statistics
    foreach ($item in $Items) {
        if ($item.Type -eq "Directory") {
            $stats.DirectoryCount++
        } else {
            $stats.FileCount++
        }
        
        if ($item.NeedsChange) {
            $stats.ItemsNeedingChanges++
        } else {
            $stats.ItemsAlreadyOptimized++
        }
        
        # [FNAME-005.2] Check for problematic patterns
        $issues = Test-ProblematicPatterns -Filename $item.OriginalName -Settings $Settings
        if ($issues.Count -gt 0) {
            $stats.ProblematicPatterns++
        }
    }
    
    # [FNAME-005.3] Check for conflicts
    $conflicts = Test-FilenameConflicts -ProposedItems $Items -Settings $Settings
    $stats.ConflictCount = $conflicts.Count
    
    return $stats
}