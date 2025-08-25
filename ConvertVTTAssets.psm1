<#
.SYNOPSIS
    ConvertVTTAssets - Enterprise-grade PowerShell module for Foundry VTT asset optimization
.DESCRIPTION
    Comprehensive asset optimization suite with parallel processing, undo capability, and professional reporting.
    Features WebM/WebP conversion, filename sanitization, and enterprise-scale performance (50,000+ files).
.AUTHOR
    Andres Yuhnke, Claude (Anthropic)
.VERSION
    1.6.0
.DATE
    2025-08-24
.COPYRIGHT
    (c) 2025 Andres Yuhnke. MIT License.
.LINK
    https://github.com/andresyuhnke/ConvertVTTAssets
.LINK
    https://www.powershellgallery.com/packages/ConvertVTTAssets
.NOTES
    Modular architecture with enterprise performance capabilities:
    - Parallel processing: 3-4x performance improvement 
    - Memory efficient: Chunked processing for 50,000+ files
    - Complete undo system with validation
    - Professional HTML reporting
    Requirements: PowerShell 7+ (recommended), FFmpeg, ThreadJob module
#>

# [MAIN-001] PowerShell version detection and parallel processing capability assessment
$script:IsPS7 = $PSVersionTable.PSVersion.Major -ge 7

# [MAIN-002] Import parallel processing engine for PowerShell 7+ environments
# Only load Core.ps1 if we're running PowerShell 7+ for ThreadJob support
if ($script:IsPS7) {
    . $PSScriptRoot\ConvertVTTAssets.Core.ps1
}

# [MAIN-003] Load private utility functions - These are internal helpers not exposed to users
# Order matters: SharedHelpers must load before ReportGeneration (dependencies)
. $PSScriptRoot\Private\SharedHelpers.ps1
. $PSScriptRoot\Private\ReportGeneration.ps1
. $PSScriptRoot\Private\FilenameHelpers.ps1
. $PSScriptRoot\Private\ProcessingHelpers.ps1

# [MAIN-004] Load public function modules - These become the module's exported interface
# Each public function is in its own file for maintainability and focused responsibility
. $PSScriptRoot\Public\Convert-ToWebM.ps1
. $PSScriptRoot\Public\Convert-ToWebP.ps1  
. $PSScriptRoot\Public\Optimize-FileNames.ps1
. $PSScriptRoot\Public\Undo-FileNameOptimization.ps1

# [MAIN-005] Export module interface - Define what functions are available to users
# Only these 4 functions should be accessible when the module is imported
Export-ModuleMember -Function @(
    'Convert-ToWebM',
    'Convert-ToWebP', 
    'Optimize-FileNames',
    'Undo-FileNameOptimization'
)