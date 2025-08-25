# ConvertVTTAssets v1.6.0

A comprehensive PowerShell module for optimizing Foundry Virtual Tabletop (VTT) assets through efficient WebM and WebP conversion, filename sanitization with undo capability, and enterprise-scale performance optimizations.

## ✨ What's New in v1.6.0

### 🗃️ Modular Architecture
- **Clean 10-module design** for enhanced maintainability
- **Professional code organization** with focused responsibilities
- **Comprehensive documentation** with indexed inline comments

### 🚀 Enhanced Performance
- **Parallel processing** with ThreadJob engine (3-4x speed improvement)
- **Memory-efficient** chunked processing for 50,000+ files
- **Enterprise-scale** operations with configurable throttling

### 📊 Professional Reporting
- **HTML reports** with risk assessment and time estimates
- **Visual indicators** for before/after comparisons
- **Audit trails** with complete settings documentation

### 🔄 Complete Undo System
- **Full rollback capability** for filename operations
- **Two-phase validation** with integrity and conflict detection
- **JSON-based undo logs** with dependency tracking

## ✨ Key Features

- **Convert-ToWebM** — Convert animated images/videos (GIF, animated WebP, MP4, MOV, MKV, APNG) to WebM
- **Convert-ToWebP** — Convert static images (PNG, JPG/JPEG, TIFF, BMP) to WebP
- **Optimize-FileNames** — Sanitize filenames and directories for Foundry VTT web server compatibility
- **Undo-FileNameOptimization** — Complete rollback capability for filename operations
- **Parallel Processing** — Multi-threaded conversion using ThreadJob engine (PS7+)
- **Enterprise Scale** — Handles 50,000+ files with chunked memory management
- **Professional Reports** — Generate HTML analysis reports before making changes
- **Real-time Progress** — Live console output showing conversion status and compression ratios
- **Smart Skip Logic** — Automatically skips already-converted files based on timestamps
- **Safe Source Management** — Optional source deletion to Recycle Bin after successful conversion
- **Comprehensive Logging** — CSV/JSON export with detailed metrics including size deltas

## Prerequisites

### Required Software

1. **PowerShell 7.0 or higher** (recommended)
   - Windows PowerShell 5.1 works but without parallel processing
   - Download PowerShell 7: https://github.com/PowerShell/PowerShell/releases
   - Verify version: `$PSVersionTable.PSVersion`

2. **FFmpeg and FFprobe**
   - Download: https://www.gyan.dev/ffmpeg/builds/ (recommended: full or essentials build)
   - Add to system PATH or specify paths via `-FfmpegPath` and `-FfprobePath` parameters
   - Verify installation: `ffmpeg -version` and `ffprobe -version`

### System Requirements

- **Operating System**: Windows 10/11 or Windows Server 2016+
- **Memory**: 4GB minimum, 8GB+ recommended for parallel processing
- **CPU**: Multi-core processor recommended for parallel conversion
- **Disk Space**: Sufficient space for output files (typically 40-50% of source size)

## 📁 Module Structure

ConvertVTTAssets v1.6.0 uses a clean modular architecture:

```
ConvertVTTAssets/
├── ConvertVTTAssets.psd1           # Module manifest
├── ConvertVTTAssets.psm1           # Main loader module
├── ConvertVTTAssets.Core.ps1       # Parallel processing engine
├── Private/
│   ├── SharedHelpers.ps1           # Shared utility functions
│   ├── ReportGeneration.ps1        # HTML reporting functions
│   ├── FilenameHelpers.ps1         # Filename sanitization logic
│   └── ProcessingHelpers.ps1       # Enterprise processing functions
└── Public/
    ├── Convert-ToWebM.ps1          # WebM conversion
    ├── Convert-ToWebP.ps1          # WebP conversion
    ├── Optimize-FileNames.ps1      # Filename optimization
    └── Undo-FileNameOptimization.ps1 # Undo functionality
```

## Installation

### Prerequisites for Installation

1. **Set PowerShell Execution Policy** (if not already done):
   ```powershell
   # Check current policy
   Get-ExecutionPolicy
   
   # If it shows "Restricted", set it to RemoteSigned
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

2. **PowerShell Version** (check with `$PSVersionTable.PSVersion`):
   - PowerShell 7+ recommended for full functionality
   - Windows PowerShell 5.1 minimum (no parallel processing)

### Method 1: PowerShell Gallery (Recommended)

```powershell
# Install from PowerShell Gallery
Install-Module -Name ConvertVTTAssets -Scope CurrentUser

# Import the module
Import-Module ConvertVTTAssets

# Verify installation
Get-Command -Module ConvertVTTAssets
```

### Method 2: Automated Installation from GitHub

1. **Download and extract** the module to your preferred location (e.g., `C:\MyModules\ConvertVTTAssets\`)

2. **Unblock the downloaded files** (required for files downloaded from internet):
   ```powershell
   # Navigate to the module folder
   cd "C:\MyModules\ConvertVTTAssets"
   
   # Unblock all files
   Get-ChildItem -Recurse | Unblock-File
   ```

3. **Run the installer**:
   ```powershell
   .\Install.ps1
   ```
   
   The installer will:
   - Prompt for installation location (defaults to current directory)
   - Add the module path to your PSModulePath
   - Configure auto-loading in your PowerShell profile
   - Import the module immediately
   - Display available commands

4. **Restart PowerShell** for auto-loading to take effect in new sessions

### Method 3: Manual Installation

1. **Download** the module files to your preferred location

2. **Unblock the files**:
   ```powershell
   Get-ChildItem -Path "C:\PowerShell-Scripts\ConvertVTTAssets" -Recurse | Unblock-File
   ```

3. **Add to PSModulePath** (for auto-discovery):
   ```powershell
   # Add to current session
   $env:PSModulePath = "$env:PSModulePath;C:\PowerShell-Scripts"
   
   # Add permanently for current user
   [Environment]::SetEnvironmentVariable('PSModulePath', 
       "$env:PSModulePath;C:\PowerShell-Scripts", 'User')
   ```

4. **Import the module**:
   ```powershell
   Import-Module "C:\PowerShell-Scripts\ConvertVTTAssets\ConvertVTTAssets.psd1"
   ```

5. **Optional: Add to PowerShell profile** for auto-loading:
   ```powershell
   # Open your profile
   notepad $PROFILE
   
   # Add this line
   Import-Module "C:\PowerShell-Scripts\ConvertVTTAssets\ConvertVTTAssets.psd1"
   ```

### Troubleshooting Installation

**"Cannot be loaded. The file is not digitally signed"**
- Run: `Unblock-File -Path ".\Install.ps1"` before running the installer
- Or unblock all files: `Get-ChildItem -Recurse | Unblock-File`

**"Running scripts is disabled on this system"**
- Run: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
- This allows local scripts to run while blocking unsigned remote scripts

**"Module not found" after installation**
- Restart PowerShell to reload the PSModulePath
- Or manually import: `Import-Module "C:\PowerShell-Scripts\ConvertVTTAssets\ConvertVTTAssets.psd1"`

### Verify Installation

```powershell
# Check if module is available
Get-Module -ListAvailable ConvertVTTAssets

# See available commands
Get-Command -Module ConvertVTTAssets

# Test with a simple command
Optimize-FileNames -Root "C:\Test" -WhatIf
```

## Usage Examples

### Complete Workflow for Foundry VTT Assets

```powershell
# Step 1: Generate a report to preview changes
Optimize-FileNames -Root "D:\FoundryAssets" -RemoveMetadata -GenerateReport

# Step 2: Sanitize filenames for web compatibility (with undo log)
Optimize-FileNames -Root "D:\FoundryAssets" -RemoveMetadata -SpaceReplacement Underscore -UndoLogPath "D:\Logs\undo.json"

# Step 3: Convert animated content to WebM with parallel processing
Convert-ToWebM -Root "D:\FoundryAssets" -OutputRoot "D:\FoundryAssets-Optimized" -MaxFPS 24 -Parallel

# Step 4: Convert static images to WebP with parallel processing
Convert-ToWebP -Root "D:\FoundryAssets" -OutputRoot "D:\FoundryAssets-Optimized" -Quality 85 -Parallel

# Optional: Undo filename changes if needed
Undo-FileNameOptimization -UndoLogPath "D:\Logs\undo.json"
```

### Filename Optimization Examples

```powershell
# Basic filename sanitization (current directory)
Optimize-FileNames

# Remove metadata and use dashes for spaces
Optimize-FileNames `
    -Root "D:\FoundryVTT\Data" `
    -RemoveMetadata `
    -SpaceReplacement Dash `
    -LogPath "D:\Logs\filename_changes.csv"

# Expand ampersands to 'and' and preserve case
Optimize-FileNames `
    -Root "D:\Maps" `
    -ExpandAmpersand `
    -PreserveCase `
    -Silent

# Preview changes without applying them
Optimize-FileNames -Root "D:\Tokens" -RemoveMetadata -WhatIf

# Generate HTML report for review
Optimize-FileNames -Root "D:\Assets" -RemoveMetadata -GenerateReport -ReportPath "D:\Reports\preview.html"

# Enterprise-scale with parallel processing
Optimize-FileNames `
    -Root "D:\MassiveLibrary" `
    -RemoveMetadata `
    -UndoLogPath "D:\Logs\undo.json" `
    -Parallel `
    -ThrottleLimit 16 `
    -ChunkSize 2000
```

### Media Conversion Examples

```powershell
# Convert animated maps to WebM (current directory)
Convert-ToWebM -OutputRoot "D:\Optimized"

# Convert static tokens to WebP with specific quality
Convert-ToWebP -Root "D:\FoundryVTT\Data\tokens" -OutputRoot "D:\FoundryVTT\Data\tokens-optimized" -Quality 90

# Advanced conversion with specific settings
Convert-ToWebM `
    -Root "D:\FoundryAssets" `
    -OutputRoot "D:\FoundryAssets-Optimized" `
    -MaxFPS 24 `
    -MaxWidth 1920 `
    -Codec vp9 `
    -AlphaMode auto `
    -Parallel `
    -ThrottleLimit 6 `
    -LogPath "D:\Logs\webm_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv" `
    -Force

# Batch convert with cleanup
Convert-ToWebP `
    -Root "D:\Portraits" `
    -OutputRoot "D:\Portraits-WebP" `
    -Quality 85 `
    -DeleteSource `
    -LogPath "D:\Logs\portrait_conversion.json"
```

## Parameters

### Optimize-FileNames Parameters

**Parameters:**
- `-Root <string>` — Source directory (default: "." | any valid path)
- `-SpaceReplacement <string>` — Space handling (default: "Underscore" | "Dash" | "Remove")
- `-ThrottleLimit <int>` — Parallel thread count (default: 8 | range: 1-32)
- `-ChunkSize <int>` — Items per processing chunk (default: 1000 | range: 100-50,000)

**Switch Parameters:**
- `-RemoveMetadata [switch]` — Remove content in brackets/parentheses
- `-LowercaseExtensions [switch]` — Force extensions to lowercase
- `-PreserveCase [switch]` — Keep original case (default converts to lowercase)
- `-ExpandAmpersand [switch]` — Replace & with 'and' instead of underscore
- `-NoRecurse [switch]` — Only process root directory
- `-Parallel [switch]` — Enable parallel processing (PowerShell 7+ only)
- `-GenerateReport [switch]` — Create preview report without making changes
- `-Silent [switch]` — Suppress progress output
- `-Force [switch]` — Overwrite existing files
- `-WhatIf [switch]` — Preview changes without applying

**Optional Parameters:**
- `-LogPath <string>` — Log file path (format: .csv or .json)
- `-UndoLogPath <string>` — Save undo information for rollback
- `-ReportPath <string>` — Custom path for HTML report
- `-IncludeExt <string[]>` — Array of extensions to include (e.g., @('.png', '.jpg'))
- `-ExcludeExt <string[]>` — Array of extensions to exclude

#### Filename Transformation Examples

| Original | With Default Settings | With -RemoveMetadata | With -ExpandAmpersand |
|----------|----------------------|---------------------|----------------------|
| `player's handbook.pdf` | `players_handbook.pdf` | `players_handbook.pdf` | `players_handbook.pdf` |
| `map [night time].png` | `map-night_time.png` | `map.png` | `map-night_time.png` |
| `token (v2).webp` | `token-v2.webp` | `token.webp` | `token-v2.webp` |
| `maps & tokens/` | `maps_tokens/` | `maps_tokens/` | `maps_and_tokens/` |
| `chapter 1: intro.txt` | `chapter_1-intro.txt` | `chapter_1-intro.txt` | `chapter_1-intro.txt` |
| `file!!!.jpg` | `file.jpg` | `file.jpg` | `file.jpg` |

### Convert-ToWebM Parameters

**Parameters:**
- `-Root <string>` — Source directory (default: "." | any valid path)
- `-MaxFPS <int>` — Maximum framerate (default: 30 | range: 1-240)
- `-MaxWidth <int>` — Maximum width in pixels (default: 1920 | range: 64-8192)
- `-Codec <string>` — Video codec (default: "vp9" | "av1")
- `-AlphaMode <string>` — Alpha handling (default: "auto" | "force" | "disable")
- `-MaxBitrateKbps <int>` — Bitrate ceiling (default: 0 - no limit | any positive integer)
- `-ThrottleLimit <int>` — Simultaneous conversions (default: 4 | range: 1-64)
- `-FfmpegPath <string>` — Path to ffmpeg executable (default: "ffmpeg" | any valid path)
- `-FfprobePath <string>` — Path to ffprobe executable (default: "ffprobe" | any valid path)

**Switch Parameters:**
- `-NoRecurse [switch]` — Only process root directory
- `-Parallel [switch]` — Enable multi-threaded processing (PowerShell 7+ only)
- `-Force [switch]` — Re-convert even if destination exists
- `-DeleteSource [switch]` — Send originals to Recycle Bin after conversion
- `-Silent [switch]` — Suppress progress output
- `-WhatIf [switch]` — Preview what would be converted

**Optional Parameters:**
- `-OutputRoot <string>` — Destination directory (mirrors source structure)
- `-AlphaBackground <string>` — Background color when disabling alpha (e.g., '#000000')
- `-LogPath <string>` — Log file path (format: .csv or .json)
- `-IncludeExt <string[]>` — Additional extensions to process
- `-ExcludeExt <string[]>` — Extensions to skip

### Convert-ToWebP Parameters

**Parameters:**
- `-Root <string>` — Source directory (default: "." | any valid path)
- `-Quality <int>` — Compression quality (default: 80 | range: 1-100)
- `-MaxWidth <int>` — Maximum width in pixels (default: 4096 | range: 64-8192)
- `-ThrottleLimit <int>` — Simultaneous conversions (default: 4 | range: 1-64)
- `-FfmpegPath <string>` — Path to ffmpeg executable (default: "ffmpeg" | any valid path)
- `-FfprobePath <string>` — Path to ffprobe executable (default: "ffprobe" | any valid path)

**Switch Parameters:**
- `-Lossless [switch]` — Enable lossless compression
- `-NoRecurse [switch]` — Only process root directory
- `-Parallel [switch]` — Enable multi-threaded processing (PowerShell 7+ only)
- `-Force [switch]` — Re-convert even if destination exists
- `-DeleteSource [switch]` — Send originals to Recycle Bin after conversion
- `-Silent [switch]` — Suppress progress output
- `-WhatIf [switch]` — Preview what would be converted

**Optional Parameters:**
- `-OutputRoot <string>` — Destination directory (mirrors source structure)
- `-LogPath <string>` — Log file path (format: .csv or .json)
- `-IncludeExt <string[]>` — Additional extensions to process
- `-ExcludeExt <string[]>` — Extensions to skip

### Undo-FileNameOptimization Parameters

**Required Parameters:**
- `-UndoLogPath <string>` — Path to undo log file

**Switch Parameters:**
- `-Force [switch]` — Overwrite conflicts
- `-Silent [switch]` — Suppress progress output
- `-WhatIf [switch]` — Preview changes without applying

**Optional Parameters:**
- `-BackupUndoLogPath <string>` — Create backup before processing

## Recommended Settings for Foundry VTT

| Asset Type | Format | MaxWidth | MaxFPS | Quality | Typical Reduction |
|------------|--------|----------|---------|---------|-------------------|
| Battle Maps | WebM/WebP | 2560 | 24 | 80-85 | 50-70% |
| Tokens (Animated) | WebM | 512 | 30 | - | 60-75% |
| Tokens (Static) | WebP | 512 | - | 85-90 | 65-75% |
| Portraits | WebP | 1024 | - | 85-90 | 60-70% |
| Scenes | WebP | 4096 | - | 80-85 | 55-65% |
| UI Elements | WebP | 512 | - | 90-95 | 40-60% |

## Report Generation

Generate comprehensive HTML reports before making changes:

```powershell
# Generate report with automatic naming
Optimize-FileNames -Root "D:\Assets" -RemoveMetadata -GenerateReport

# Custom report path
Optimize-FileNames -Root "D:\Assets" -GenerateReport -ReportPath "C:\Reports\AssetAnalysis.html"

# Report includes:
# - Summary statistics and time estimates
# - Complete list of proposed changes
# - Risk assessment and warnings
# - Operation settings documentation
# - Professional HTML formatting
```

## Logging

The module provides comprehensive logging capabilities for all operations. The log format is automatically determined by the file extension you provide:

- **`.csv` extension** — Creates a CSV file (tabular format, easy to open in Excel)
- **`.json` extension** — Creates a JSON file (nested structure with full details)
- **Any other extension** — Defaults to CSV format

### Examples

```powershell
# Create a CSV log for conversions
Convert-ToWebM -Root "D:\Assets" -LogPath "D:\Logs\webm_conversions.csv"

# Create a JSON log with nested structure
Optimize-FileNames -Root "D:\Assets" -LogPath "D:\Logs\filename_changes.json"

# These will create CSV logs (default for unknown extensions)
Convert-ToWebP -Root "D:\Assets" -LogPath "D:\Logs\conversions.log"
Convert-ToWebP -Root "D:\Assets" -LogPath "D:\Logs\conversions.txt"
```

### Log Contents

**Conversion logs include:**
- Timestamp for each operation
- Source and destination paths
- Status (Converted/Skipped/Failed/WhatIf)
- Processing duration in seconds
- File sizes before and after
- Size reduction (bytes and percentage)
- Settings used (codec, quality, etc.)
- Error messages for failures

**Filename optimization logs include:**
- Timestamp for each operation
- Item type (File/Directory)
- Original and new paths
- Original and new names
- Operation status
- Settings used (RemoveMetadata, SpaceReplacement, etc.)
- Error details if failed
- Undo operation ID for rollback

## Performance & Optimization

### Parallel Processing Performance

| File Count | Sequential | Parallel (8 threads) | Speed Improvement |
|------------|------------|---------------------|-------------------|
| 100 files  | ~100 sec   | ~25 sec            | 4x faster         |
| 1,000 files| ~1000 sec  | ~250 sec           | 4x faster         |
| 10,000 files| ~2.8 hours | ~45 min           | 3.7x faster       |

### Memory Management

The module uses chunked processing to handle large file sets efficiently:

```powershell
# Process 50,000+ files with controlled memory usage
Optimize-FileNames -Root "D:\MassiveLibrary" -Parallel -ChunkSize 2000 -ThrottleLimit 12

# Conservative settings for limited RAM
Optimize-FileNames -Root "D:\Library" -Parallel -ChunkSize 500 -ThrottleLimit 4
```

### Performance Tips

1. **Parallel Processing:**
   - Use `-Parallel` with PS7+ for 3-4x speed improvement
   - Set `-ThrottleLimit` to (CPU cores - 2) for optimal performance
   - Monitor system resources and adjust accordingly

2. **Memory Management:**
   - For 10,000+ files, use chunked processing
   - Adjust `-ChunkSize` based on available RAM
   - Default 1000 items per chunk works for most systems

3. **Enterprise Configurations:**
   ```powershell
   # High-performance server (32 cores, 64GB RAM)
   -Parallel -ThrottleLimit 24 -ChunkSize 5000
   
   # Standard workstation (8 cores, 16GB RAM)
   -Parallel -ThrottleLimit 6 -ChunkSize 1000
   
   # Limited resources (4 cores, 8GB RAM)
   -Parallel -ThrottleLimit 3 -ChunkSize 500
   ```

## Troubleshooting

### Common Issues

1. **"ffmpeg not found" error**
   - Ensure FFmpeg is in system PATH
   - Or specify path: `-FfmpegPath "C:\ffmpeg\bin\ffmpeg.exe"`

2. **Parallel processing not working**
   - Verify PowerShell 7+ is installed: `$PSVersionTable.PSVersion`
   - Ensure ThreadJob module is available: `Get-Module ThreadJob -ListAvailable`

3. **"Cannot be loaded because running scripts is disabled"**
   - Run: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

4. **Memory issues with large file sets**
   ```powershell
   # Reduce chunk size and throttle limit
   Optimize-FileNames -Root "D:\HugeLibrary" -Parallel -ChunkSize 500 -ThrottleLimit 4
   ```

5. **Files not being converted**
   - Check file extensions match defaults or use `-IncludeExt`
   - Verify source files aren't corrupted: `ffprobe "path\to\file"`
   - Check permissions on source and destination directories

6. **Filename optimization issues**
   - Some characters are already illegal in Windows and can't exist in filenames
   - Use `-WhatIf` to preview changes before applying
   - Generate report with `-GenerateReport` for risk assessment
   - Check log file for specific errors if using `-LogPath`

7. **Undo operations failing**
   - Verify undo log file exists and is valid JSON
   - Check that files haven't been moved or deleted
   - Use `-Force` to override conflicts
   - Review validation errors in output

## Version History

### v1.6.0 (Current - 2025-08-25)
- **NEW:** Complete undo system for filename operations
- **NEW:** Professional HTML report generation
- **NEW:** Parallel processing with ThreadJob engine
- **NEW:** Chunked memory management for 50,000+ files
- **NEW:** Configurable thread throttling (1-32 threads)
- **IMPROVED:** 3-4x performance improvement with parallel processing
- **IMPROVED:** Memory efficiency from O(n) to O(chunk_size)
- **IMPROVED:** Modular architecture with 10 focused components

### v1.5.2 (2025-08-21)
- Added Optimize-FileNames function for web-safe filename sanitization
- Added -ExpandAmpersand switch for converting & to 'and'
- Improved handling of brackets, parentheses, and metadata
- Enhanced character replacement logic based on Foundry VTT guidelines

### v1.5.1 (2025-08-20)
- Added real-time progress output with percentage and file names
- Added `-Silent` switch to suppress progress output
- Improved error handling and status reporting

### v1.5.0 (2025-08-20)
- Implemented parallel processing using ThreadJob engine
- Fixed goto/label syntax issues
- Added comprehensive logging with size deltas
- Improved module import handling

### v1.4.x (2025-08-10)
- Initial stable release with sequential processing
- Basic WebM and WebP conversion functionality

## Authors & Credits

- **Andres Yuhnke** — Project creator and lead developer
- **Claude (Anthropic)** — v1.6.0 performance optimizations, undo system, and report generation
- **ChatGPT (OpenAI)** — Initial development and v1.0-1.5 architecture
- **FFmpeg Team** — Core conversion engine

## License

MIT License - See [LICENSE](LICENSE) file for details

## Contributing

Issues, suggestions, and pull requests are welcome!

- **GitHub:** https://github.com/andresyuhnke/ConvertVTTAssets
- **PowerShell Gallery:** https://www.powershellgallery.com/packages/ConvertVTTAssets
- **Email:** andres.yuhnke@gmail.com

## Support

For bugs or feature requests, please open an issue on [GitHub](https://github.com/andresyuhnke/ConvertVTTAssets/issues).

## Acknowledgments

Special thanks to the Foundry VTT community for inspiration and use case validation. Filename sanitization guidelines based on official Foundry VTT media documentation.

---

*Optimizing Foundry VTT assets with enterprise-grade performance and safety* 🎮