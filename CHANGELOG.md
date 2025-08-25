# ConvertVTTAssets Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.6.0] - 2025-08-25

### 🎉 Major Release - Performance & Safety Update

This release transforms ConvertVTTAssets into an enterprise-grade solution with parallel processing, complete undo capability, and professional reporting features.

### Added

#### 🔄 Complete Undo System
- **New Function: `Undo-FileNameOptimization`** - Full rollback capability for filename operations
- Automatic undo log generation via `-UndoLogPath` parameter
- Two-phase validation: file integrity checking + conflict detection before undo
- Smart dependency tracking for directory rename operations
- Comprehensive error reporting and partial rollback support
- Backup creation option with `-BackupUndoLogPath`

#### 📊 Professional Report Generation
- **New Parameter: `-GenerateReport`** for all optimization functions
- HTML reports with interactive tables and visual statistics
- Risk assessment with color-coded warning system
- Time estimation algorithms for operation planning
- Before/after comparison tables for all proposed changes
- Settings documentation included in reports
- Custom report paths via `-ReportPath` parameter

#### ⚡ Performance Optimizations
- **Parallel Processing** with ThreadJob engine (PowerShell 7+)
  - 3-4x speed improvement for batch operations
  - Configurable thread throttling (1-32 concurrent operations)
  - Automatic fallback to sequential for PS 5.1
- **Memory Management** via chunked processing
  - `-ChunkSize` parameter (100-50,000 items per chunk)
  - Handles 50,000+ files without memory exhaustion
  - Forced garbage collection between chunks
  - Memory usage reduced from O(n) to O(chunk_size)
- **Smart Processing Order**
  - Sequential directory processing (preserves dependencies)
  - Parallel file processing within chunks
  - Depth-first directory traversal for proper cascading

#### 🗃️ Modular Architecture
- **Clean 10-module design** for enhanced maintainability
- **Professional code organization** with focused responsibilities
- **Comprehensive inline documentation** with indexed comments
- Enhanced separation between public interface and internal logic

#### 📚 Documentation & Help System
- **Complete Get-Help integration** - All functions now have comprehensive help
- **Professional parameter documentation** - Every parameter documented with defaults
- **Enhanced installation system** - Flexible Install.ps1 with path detection
- **Comprehensive examples** - Multiple real-world usage scenarios per function
- **Professional about_ConvertVTTAssets.help.txt** - Enterprise-grade technical reference

### Changed

#### Optimize-FileNames Enhancements
- Added `-Parallel` switch for multi-threaded processing
- Added `-ThrottleLimit` parameter (default: 8 threads)
- Added `-ChunkSize` parameter (default: 1000 items)
- Added `-EnableProgressEstimation` for enhanced progress tracking
- Improved progress reporting with chunk-based indicators
- Enhanced validation for parent directory rename cascading

#### Module Architecture
- Expanded `ConvertVTTAssets.Core.ps1` with `Invoke-FileNameOptimizationParallel`
- Improved shared helper functions for report generation
- Added `Get-TimeEstimate`, `Get-FileSizeProjection`, `New-HTMLReport` helpers
- Enhanced error handling throughout all functions

### Performance Metrics

| Operation | File Count | v1.5.2 (Sequential) | v1.6.0 (Parallel) | Improvement |
|-----------|------------|---------------------|-------------------|-------------|
| Optimize-FileNames | 1,000 | ~17 min | ~4 min | 4.25x |
| Convert-ToWebM | 100 | ~25 min | ~6 min | 4.17x |
| Convert-ToWebP | 500 | ~8 min | ~2 min | 4x |

### Fixed
- Memory leaks when processing very large directories
- Path tracking issues with nested directory renames
- Progress calculation accuracy for chunked operations
- ThreadJob module import errors in certain environments

### Technical Details

#### New Parameters Added
- `[switch]$GenerateReport` - Create preview reports
- `[string]$ReportPath` - Custom report output path
- `[string]$UndoLogPath` - Save undo information
- `[switch]$Parallel` - Enable parallel processing
- `[int]$ThrottleLimit` - Thread count (1-32)
- `[int]$ChunkSize` - Items per chunk (100-50,000)
- `[switch]$EnableProgressEstimation` - Enhanced progress

#### Undo Log Structure
```json
{
  "metadata": {
    "timestamp": "ISO 8601 datetime",
    "root_path": "original root",
    "total_operations": count,
    "settings": { ... }
  },
  "operations": [
    {
      "operation_id": unique_id,
      "type": "File|Directory",
      "original_path": "before",
      "new_path": "after",
      "dependencies": []
    }
  ]
}
```

---

## [1.5.2] - 2025-08-21

### Added
- **New Function: Optimize-FileNames** - Comprehensive filename and directory sanitization
- `-ExpandAmpersand` switch to convert & symbols to 'and'
- Smart character replacement logic based on Foundry VTT media guidelines
- Directory renaming with automatic path tracking
- Metadata removal option for content in brackets/parentheses
- Support for multiple space replacement strategies

### Changed
- Updated module to three core functions
- Enhanced documentation with complete workflow recommendations
- Improved character handling to align with Foundry VTT specifications

### Character Handling Rules
- Apostrophes (') removed completely
- Brackets [], parentheses (), braces {} replaced with dashes when preserving content
- Colons (:) replaced with dashes
- Ampersands (&) become underscores or 'and' with -ExpandAmpersand
- Special characters (!@#$%^~`) removed

---

## [1.5.1] - 2025-08-20

### Added
- Real-time progress output showing percentage completion
- `-Silent` switch to suppress progress output
- Enhanced status indicators (✓ converted, ⚠ skipped, ✗ failed)
- File-by-file compression ratio reporting

### Changed
- Improved progress reporting for better user experience
- Enhanced error messages with descriptive output
- Updated documentation with progress output examples

### Fixed
- Progress calculation accuracy for large batch operations
- Status reporting consistency across functions

---

## [1.5.0] - 2025-08-20

### Added
- Fully functional parallel processing using ThreadJob engine
- Comprehensive error handling and retry logic
- Enhanced logging with size delta tracking
- Support for -Force flag to rebuild all files
- Support for -DeleteSource to safely move originals to Recycle Bin

### Changed
- Migrated from ForEach-Object -Parallel to ThreadJob
- Improved module import handling in parallel jobs
- Updated all version references across module files

### Fixed
- Resolved goto/label syntax issues
- Fixed array concatenation errors in parallel processing
- Corrected module import paths for parallel execution
- Eliminated race conditions in parallel job initialization

### Performance
- WebM conversion: ~57% average file size reduction
- WebP conversion: ~74% average file size reduction
- Parallel processing: 3-4x faster than sequential
- Tested with batches up to 12 files simultaneously

---

## [1.4.x] - 2025-08-10

### Initial Release
- Basic Convert-ToWebM function for animated content
- Basic Convert-ToWebP function for static images
- Sequential processing only
- FFmpeg integration for media conversion
- Smart skip logic based on file timestamps
- Basic logging to CSV format

### Features
- VP9 and AV1 codec support for WebM
- Lossy and lossless compression for WebP
- Alpha channel preservation
- FPS and resolution capping
- Recursive directory processing

---

## Upgrade Guide

### From v1.5.x to v1.6.0

1. **No breaking changes** - All existing scripts will continue to work
2. **New features are opt-in** - Use new parameters to enable:
   ```powershell
   # Enable parallel processing
   Optimize-FileNames -Root "D:\Assets" -Parallel
   
   # Generate reports
   Optimize-FileNames -Root "D:\Assets" -GenerateReport
   
   # Create undo logs
   Optimize-FileNames -Root "D:\Assets" -UndoLogPath "undo.json"
   ```
3. **PowerShell 7 recommended** for parallel processing features
4. **Memory improvements** automatic with chunked processing

---

## Links

- [GitHub Repository](https://github.com/andresyuhnke/ConvertVTTAssets)
- [PowerShell Gallery](https://www.powershellgallery.com/packages/ConvertVTTAssets)
- [Issue Tracker](https://github.com/andresyuhnke/ConvertVTTAssets/issues)