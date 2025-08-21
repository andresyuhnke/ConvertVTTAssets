@{
    RootModule        = 'ConvertVTTAssets.psm1'
    ModuleVersion     = '1.5.2'
    GUID              = '8e1e0c5c-1f2a-49a1-bf2e-000000000000'
    Author            = 'Andres + ChatGPT'
    CompanyName       = 'Andres'
    Copyright         = '(c) 2025 Andres. All rights reserved.'
    Description       = 'Foundry VTT-oriented asset converters: Convert-ToWebM (animated) and Convert-ToWebP (static).'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Convert-ToWebM','Convert-ToWebP','Optimize-FileNames')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    FormatsToProcess  = @()
    PrivateData       = @{ PSData = @{ Tags = @('foundry','vtt','webm','webp','vp9','av1','ffmpeg','assets') } }
}


