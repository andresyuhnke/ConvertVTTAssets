# ConvertVTTAssets Changelog

All notable changes to this project will be documented in this file.

## [1.5.2] - 2025-08-21

### Added
- **New Function: Optimize-FileNames** - Comprehensive filename and directory sanitization for Foundry VTT web server compatibility
- `-ExpandAmpersand` switch to convert & symbols to 'and' instead of underscore
- Smart character replacement logic based on Foundry VTT media guidelines
- Directory renaming with automatic path tracking for child items
- Metadata removal option for content in brackets/parentheses
- Support for multiple space replacement strategies (underscore, dash, remove)
- Case preservation options for filenames and extensions

### Changed
- Updated module to three core functions: Convert-ToWebM, Convert-ToWebP, and Optimize-FileNames
- Enhanced documentation to include complete workflow recommendations
- Improved character handling to align with Foundry VTT specifications

### Character Handling Rules
- Apostrophes (') are removed completely
- Brackets [], parentheses (), and braces {} are replaced with dashes when preserving content
- Colons (:) are replaced with dashes
- Ampersands (&) become underscores by default, or 'and' with -ExpandAmpersand
- Special characters (!@#$%^~`) are removed
- Windows-illegal characters are skipped (already prevented by OS)

### Performance
- Filename optimization processes directories depth-first to handle cascading renames
- Maintains renamed path tracking to update child items correctly
- Supports WhatIf mode for safe preview of changes

## [1.5.1] - 2025-08-20

### Added
- Real-time progress output showing percentage completion and current file
- `-Silent` switch to suppress progress output during batch operations
- Enhanced status indicators (✓ converted, ⚠ skipped, ✗ failed)
- File-by-file compression ratio reporting

### Changed
- Improved progress reporting for better user experience
- Enhanced error messages with more descriptive output
- Updated all documentation with progress output examples

### Fixed
- Progress calculation accuracy for large batch operations
- Status reporting consistency across all functions

### Performance
- No performance impact from progress reporting
- Silent mode available for maximum speed

## [1.5.0] - 2025-08-20

### Added
- Fully functional parallel processing using ThreadJob engine
- Comprehensive error handling and retry logic
- Enhanced logging with size delta tracking
- Support for -Force flag to rebuild all files
- Support for -DeleteSource to safely move originals to Recycle Bin

### Changed
- Migrated from ForEach-Object -Parallel to ThreadJob for better reliability
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
- Parallel processing: 3-4x faster than sequential for large batches
- Tested with batches up to 12 files simultaneously

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

### Known Limitations
- No parallel processing support
- Limited progress reporting
- No filename sanitization capabilities