# Changelog

All notable changes to macdev will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Homebrew cask support for GUI applications (`--cask` flag)
- Shell completion for bash, zsh, and fish
- Lock files for reproducible environments
- `macdev gc --all` flag to remove all pure packages
- `macdev upgrade` command to upgrade packages
- `macdev check --quiet` for fast environment validation
- Support for multiple Python versions per project
- Python symlink normalization (both `python` and `python3` work)
- Project-specific package listing in `macdev list`

### Changed
- Refactored to library + binary structure for better testability
- Versioned packages use full spec as key in global manifest
- Lock files only include project-specific packages (not global)

### Fixed
- Python 3 symlink now correctly points to project's Python version
- Lock file generation uses correct package specs

## [0.1.0] - YYYY-MM-DD

### Added
- Initial release
- Project-isolated development environments
- Pure (isolated) and impure (system-wide) package management
- Automatic Python virtual environment creation
- direnv integration
- Homebrew tap management
- Garbage collection for unused packages

[Unreleased]: https://github.com/yourusername/macdev/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yourusername/macdev/releases/tag/v0.1.0
