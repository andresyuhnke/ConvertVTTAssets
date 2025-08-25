@{
    RootModule        = 'ConvertVTTAssets.psm1'
    ModuleVersion     = '1.6.0'
    GUID              = '8e1e0c5c-1f2a-49a1-bf2e-000000000000'
    Author            = 'Andres Yuhnke, Claude (Anthropic)'
    CompanyName       = 'Andres Yuhnke'
    Copyright         = '(c) 2025 Andres Yuhnke. All rights reserved.'
    Description       = 'Comprehensive PowerShell module for optimizing Foundry VTT assets. Features include WebM/WebP conversion with parallel processing, filename sanitization with undo capability, dry-run reports, and enterprise-scale performance for 50,000+ files. Reduces file sizes by 50-75% while maintaining quality.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Convert-ToWebM','Convert-ToWebP','Optimize-FileNames','Undo-FileNameOptimization')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    FormatsToProcess  = @()
    PrivateData       = @{ 
        PSData = @{ 
            Tags = @('foundry','vtt','webm','webp','vp9','av1','ffmpeg','assets','undo','batch','optimization','parallel','performance','report')
            ProjectUri = 'https://github.com/andresyuhnke/ConvertVTTAssets'
            LicenseUri = 'https://github.com/andresyuhnke/ConvertVTTAssets/blob/main/LICENSE'
            ReleaseNotes = @'
v1.6.0 - Major Performance & Safety Update
- Added complete undo system for filename operations
- Added professional HTML report generation
- Added parallel processing with memory optimization
- Added chunked processing for 50,000+ files
- Performance: 3-4x faster with parallel processing
- Safety: Full rollback capability with validation
- Enterprise-ready with throttling and resource management
'@
        } 
    }
}