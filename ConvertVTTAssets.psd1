@{
    RootModule        = 'ConvertVTTAssets.psm1'
    ModuleVersion     = '1.6.0'
    GUID              = '8e1e0c5c-1f2a-49a1-bf2e-000000000000'
    Author            = 'Andres Yuhnke, Claude (Anthropic)'
    CompanyName       = 'Andres Yuhnke'
    Copyright         = '(c) 2025 Andres Yuhnke. All rights reserved.'
    Description       = 'Foundry VTT-oriented asset converters with undo capability: Convert-ToWebM (animated), Convert-ToWebP (static), Optimize-FileNames (sanitization), and Undo-FileNameOptimization (batch undo).'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Convert-ToWebM','Convert-ToWebP','Optimize-FileNames','Undo-FileNameOptimization')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    FormatsToProcess  = @()
    PrivateData       = @{ 
        PSData = @{ 
            Tags = @('foundry','vtt','webm','webp','vp9','av1','ffmpeg','assets','undo','batch','optimization') 
        } 
    }
}