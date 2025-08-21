# ConvertVTTAssets v1.5.2

A PowerShell module for optimizing Foundry Virtual Tabletop (VTT) assets through efficient WebM and WebP conversion, and filename sanitization for web server compatibility.

## Features

- **Convert-ToWebM** — Convert animated images/videos (GIF, animated WebP, MP4, MOV, MKV, APNG) to WebM
- **Convert-ToWebP** — Convert static images (PNG, JPG/JPEG, TIFF, BMP) to WebP
- **Optimize-FileNames** — Sanitize filenames and directories for Foundry VTT web server compatibility
- **Parallel Processing** — Multi-threaded conversion using ThreadJob engine (PS7+)
- **Real-time Progress** — Live console output showing conversion status and compression ratios
- **Smart Skip Logic** — Automatically skips already-converted files based on timestamps
- **Safe Source Management** — Optional source deletion to Recycle Bin after successful conversion
- **Comprehensive Logging** — CSV/JSON export with detailed metrics including size deltas

## Prerequisites

### Required Software

1. **PowerShell 7.0 or higher**
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

### Method 1: Automated Installation (Recommended)

1. **Download and extract** the module to: `C:\PowerShell-Scripts\ConvertVTTAssets\`

2. **Unblock the downloaded files** (required for files downloaded from internet):
   ```powershell
   # Navigate to the module folder
   cd "C:\PowerShell-Scripts\ConvertVTTAssets"
   
   # Unblock all files
   Get-ChildItem -Path "C:\PowerShell-Scripts\ConvertVTTAssets" -Recurse | Unblock-File
   ```

3. **Run the installer**:
   ```powershell
   .\Install.ps1
   ```
   
   The installer will:
   - Add the module path to your PSModulePath
   - Configure auto-loading in your PowerShell profile
   - Import the module immediately
   - Display available commands

4. **Restart PowerShell** for auto-loading to take effect in new sessions

### Method 2: Manual Installation

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
# Step 1: Sanitize filenames for web compatibility
Optimize-FileNames -Root "D:\FoundryAssets" -RemoveMetadata -SpaceReplacement Underscore

# Step 2: Convert animated content to WebM
Convert-ToWebM -Root "D:\FoundryAssets" -OutputRoot "D:\FoundryAssets-Optimized" -MaxFPS 24 -Parallel

# Step 3: Convert static images to WebP
Convert-ToWebP -Root "D:\FoundryAssets" -OutputRoot "D:\FoundryAssets-Optimized" -Quality 85 -Parallel
```

### Filename Optimization Examples

```powershell
# Basic filename sanitization
Optimize-FileNames -Root "D:\FoundryVTT\Data"

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
```

### Media Conversion Examples

```powershell
# Convert animated maps to WebM
Convert-ToWebM -Root "D:\FoundryVTT\Data\maps" -OutputRoot "D:\FoundryVTT\Data\maps-optimized"

# Convert static tokens to WebP
Convert-ToWebP -Root "D:\FoundryVTT\Data\tokens" -OutputRoot "D:\FoundryVTT\Data\tokens-optimized"

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
```

## Parameters

### Optimize-FileNames Parameters

- `-Root` — Source directory to scan for files and folders
- `-RemoveMetadata` — Remove content in parentheses/brackets (e.g., dimensions, version info)
- `-SpaceReplacement` — How to handle spaces: 'Underscore' (default), 'Dash', or 'Remove'
- `-ExpandAmpersand` — Replace & with 'and' instead of underscore
- `-LowercaseExtensions` — Force file extensions to lowercase
- `-PreserveCase` — Keep original case (default converts to lowercase)
- `-NoRecurse` — Only process the root directory, not subdirectories
- `-IncludeExt` — Array of extensions to include (e.g., @('.png', '.jpg'))
- `-ExcludeExt` — Array of extensions to exclude
- `-Force` — Overwrite existing files with the same name
- `-LogPath` — Path for log file (format determined by extension: .csv or .json)
- `-Silent` — Suppress progress output
- `-WhatIf` — Preview changes without applying them

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

- `-Root` — Source directory to scan for files
- `-OutputRoot` — Destination directory (mirrors source structure)
- `-MaxFPS` — Maximum framerate (default: 30)
- `-MaxWidth` — Maximum width in pixels (default: 1920)
- `-Codec` — Video codec: 'vp9' (default) or 'av1'
- `-AlphaMode` — Alpha channel handling: 'auto', 'force', or 'disable'
- `-AlphaBackground` — Background color when disabling alpha (e.g., '#000000')
- `-MaxBitrateKbps` — Optional bitrate ceiling
- `-NoRecurse` — Only process root directory
- `-IncludeExt` — Additional extensions to process
- `-ExcludeExt` — Extensions to skip
- `-Parallel` — Enable multi-threaded processing (PS7+ only)
- `-ThrottleLimit` — Number of simultaneous conversions (default: 4)
- `-Force` — Re-convert even if destination exists
- `-DeleteSource` — Send originals to Recycle Bin after conversion
- `-LogPath` — Path for CSV/JSON log file
- `-Silent` — Suppress progress output
- `-WhatIf` — Preview what would be converted without actual conversion

### Convert-ToWebP Parameters

- `-Root` — Source directory to scan for files
- `-OutputRoot` — Destination directory (mirrors source structure)
- `-Quality` — Compression quality 1-100 (default: 80)
- `-Lossless` — Enable lossless compression
- `-MaxWidth` — Maximum width in pixels (default: 4096)
- `-NoRecurse` — Only process root directory
- `-IncludeExt` — Additional extensions to process
- `-ExcludeExt` — Extensions to skip
- `-Parallel` — Enable multi-threaded processing (PS7+ only)
- `-ThrottleLimit` — Number of simultaneous conversions (default: 4)
- `-Force` — Re-convert even if destination exists
- `-DeleteSource` — Send originals to Recycle Bin after conversion
- `-LogPath` — Path for CSV/JSON log file
- `-Silent` — Suppress progress output
- `-WhatIf` — Preview what would be converted without actual conversion

## Recommended Settings for Foundry VTT

| Asset Type | Format | MaxWidth | MaxFPS | Quality | Typical Reduction |
|------------|--------|----------|---------|---------|-------------------|
| Battle Maps | WebM/WebP | 2560 | 24 | 80-85 | 50-70% |
| Tokens (Animated) | WebM | 512 | 30 | - | 60-75% |
| Tokens (Static) | WebP | 512 | - | 85-90 | 65-75% |
| Portraits | WebP | 1024 | - | 85-90 | 60-70% |
| Scenes | WebP | 4096 | - | 80-85 | 55-65% |
| UI Elements | WebP | 512 | - | 90-95 | 40-60% |

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

## Performance

Typical conversion metrics based on real-world usage:

- **File Size Reduction**: 50-75% average
- **Processing Speed**: 
  - Sequential: ~1-2 files per second
  - Parallel (6 threads): ~5-8 files per second
- **Memory Usage**: ~200-500MB per conversion thread
- **CPU Usage**: 80-95% with parallel processing

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

4. **Files not being converted**
   - Check file extensions match defaults or use `-IncludeExt`
   - Verify source files aren't corrupted: `ffprobe "path\to\file"`
   - Check permissions on source and destination directories

5. **Filename optimization issues**
   - Some characters are already illegal in Windows and can't exist in filenames
   - Use `-WhatIf` to preview changes before applying
   - Check log file for specific errors if using `-LogPath`

## Version History

### v1.5.2 (Current)
- Added Optimize-FileNames function for web-safe filename sanitization
- Added -ExpandAmpersand switch for converting & to 'and'
- Improved handling of brackets, parentheses, and metadata
- Enhanced character replacement logic based on Foundry VTT guidelines

### v1.5.1
- Added real-time progress output with percentage and file names
- Added `-Silent` switch to suppress progress output
- Improved error handling and status reporting

### v1.5.0
- Implemented parallel processing using ThreadJob engine
- Fixed goto/label syntax issues
- Added comprehensive logging with size deltas
- Improved module import handling

### v1.4.x
- Initial stable release with sequential processing
- Basic WebM and WebP conversion functionality

## Authors & Credits

- **Andres Yuhnke** — Project creator and primary developer
- **Claude (Anthropic)** — Module architecture, parallel processing, filename optimization, and debugging
- **ChatGPT (OpenAI)** — Initial code development and optimization strategies
- **FFmpeg Team** — Core conversion engine

## License

MIT License - See LICENSE file for details

## Contributing

Issues, suggestions, and pull requests are welcome at:
- GitHub: https://github.com/andresyuhnke/ConvertVTTAssets
- PowerShell Gallery: https://www.powershellgallery.com/packages/ConvertVTTAssets
- Email: andres.yuhnke@gmail.com

## Acknowledgments

Special thanks to the Foundry VTT community for inspiration and use case validation. Filename sanitization guidelines based on official Foundry VTT media documentation.